import { DeviceTopologyProvider, DeviceTopologySnapshot } from './DeviceTopologyProvider';
import { MeshDialRole, planPeerRole } from './PeerMeshPlanner';
import { PeerDevice } from '../model/AppModels';

const INBOUND_GRACE_MS: number = 3000;
const TOPOLOGY_DEBOUNCE_MS: number = 300;
const READY_POLL_MS: number = 25;
const RETRY_DELAYS_MS: number[] = [1000, 2000, 4000, 8000, 30000];

export interface MeshTimer {
  after(delayMs: number, callback: () => void): number;
  cancel(id: number): void;
  now(): number;
  sleep(delayMs: number): Promise<void>;
}

export interface MeshPeerTransport {
  setLocalDeviceId(deviceId: string): void;
  registerPeers(peers: PeerDevice[]): Promise<void>;
  connect(peer: PeerDevice): Promise<void>;
  disconnectPeer(deviceId: string): Promise<void>;
  isReady(deviceId: string): boolean;
}

export interface PeerMeshController {
  start(): Promise<void>;
  reconcile(): Promise<void>;
  ensureReady(waitBudgetMs: number): Promise<string[]>;
  knownPeers(): PeerDevice[];
  destroy(): void;
}

interface PeerMeshState {
  peer: PeerDevice;
  graceTimer: number | undefined;
  retryTimer: number | undefined;
  retryAttempt: number;
  connecting: boolean;
}

class SystemMeshTimer implements MeshTimer {
  after(delayMs: number, callback: () => void): number {
    return setTimeout(callback, delayMs);
  }

  cancel(id: number): void { clearTimeout(id); }
  now(): number { return Date.now(); }

  sleep(delayMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, delayMs);
    });
  }
}

export class PeerMeshOrchestrator implements PeerMeshController {
  private readonly provider: DeviceTopologyProvider;
  private readonly transport: MeshPeerTransport;
  private readonly timer: MeshTimer;
  private readonly states = new Map<string, PeerMeshState>();
  private peers: PeerDevice[] = [];
  private topologyTimer: number | undefined;
  private reconciling: Promise<void> | undefined;
  private reconcileAgain: boolean = false;
  private started: boolean = false;
  private destroyed: boolean = false;

  constructor(provider: DeviceTopologyProvider, transport: MeshPeerTransport, timer?: MeshTimer) {
    this.provider = provider;
    this.transport = transport;
    this.timer = timer ?? new SystemMeshTimer();
  }

  async start(): Promise<void> {
    if (this.destroyed) return;
    if (!this.started) {
      this.started = true;
      this.provider.start((): void => this.scheduleTopologyReconcile());
    }
    await this.reconcile();
  }

  async reconcile(): Promise<void> {
    if (this.destroyed) return;
    if (this.reconciling !== undefined) {
      this.reconcileAgain = true;
      await this.reconciling;
      return;
    }
    const current = this.reconcileOnce();
    this.reconciling = current;
    try {
      await current;
    } finally {
      if (this.reconciling === current) this.reconciling = undefined;
      if (this.reconcileAgain && !this.destroyed) {
        this.reconcileAgain = false;
        await this.reconcile();
      }
    }
  }

  async ensureReady(waitBudgetMs: number): Promise<string[]> {
    await this.reconcile();
    const deadline = this.timer.now() + Math.max(0, waitBudgetMs);
    while (!this.destroyed && this.timer.now() < deadline && this.hasPendingConnections()) {
      const remaining = deadline - this.timer.now();
      await this.timer.sleep(Math.min(READY_POLL_MS, remaining));
    }
    return this.readyDeviceIds();
  }

  knownPeers(): PeerDevice[] {
    return this.peers.slice().sort((left: PeerDevice, right: PeerDevice): number =>
      left.deviceId < right.deviceId ? -1 : (left.deviceId > right.deviceId ? 1 : 0));
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.provider.stop();
    if (this.topologyTimer !== undefined) {
      this.timer.cancel(this.topologyTimer);
      this.topologyTimer = undefined;
    }
    const deviceIds: string[] = [];
    for (const state of this.states.values()) {
      deviceIds.push(state.peer.deviceId);
      this.cancelState(state);
    }
    this.states.clear();
    this.peers = [];
    for (const deviceId of deviceIds) {
      this.transport.disconnectPeer(deviceId).catch((): void => {});
    }
  }

  private async reconcileOnce(): Promise<void> {
    const snapshot: DeviceTopologySnapshot = await this.provider.snapshot();
    if (this.destroyed) return;
    const peers = this.uniqueSortedPeers(snapshot.peers, snapshot.localDeviceId);
    this.transport.setLocalDeviceId(snapshot.localDeviceId);
    await this.transport.registerPeers(peers);
    if (this.destroyed) return;

    const keep = new Set<string>();
    for (const peer of peers) keep.add(peer.deviceId);
    const existingIds: string[] = [];
    for (const deviceId of this.states.keys()) existingIds.push(deviceId);
    for (const deviceId of existingIds) {
      if (keep.has(deviceId)) continue;
      const state = this.states.get(deviceId);
      if (state !== undefined) this.cancelState(state);
      this.states.delete(deviceId);
      try { await this.transport.disconnectPeer(deviceId); } catch (_) {}
    }
    if (this.destroyed) return;

    this.peers = peers;
    for (const peer of peers) {
      let state = this.states.get(peer.deviceId);
      if (state === undefined) {
        state = { peer: peer, graceTimer: undefined, retryTimer: undefined, retryAttempt: 0,
          connecting: false };
        this.states.set(peer.deviceId, state);
      } else {
        state.peer = peer;
      }
      await this.ensurePeer(snapshot.localDeviceId, state);
    }
  }

  private async ensurePeer(localDeviceId: string, state: PeerMeshState): Promise<void> {
    if (this.transport.isReady(state.peer.deviceId)) {
      this.cancelStateTimers(state);
      state.retryAttempt = 0;
      return;
    }
    const role = planPeerRole(localDeviceId, state.peer.deviceId);
    if (role === MeshDialRole.INVALID_SELF) {
      this.cancelStateTimers(state);
      return;
    }
    if (role === MeshDialRole.PRIMARY_DIALER) {
      this.cancelGrace(state);
      if (!state.connecting && state.retryTimer === undefined) await this.attemptConnect(state.peer.deviceId);
      return;
    }
    if (state.connecting || state.retryTimer !== undefined || state.graceTimer !== undefined) return;
    const deviceId = state.peer.deviceId;
    state.graceTimer = this.timer.after(INBOUND_GRACE_MS, (): void => {
      const current = this.states.get(deviceId);
      if (this.destroyed || current !== state) return;
      state.graceTimer = undefined;
      this.attemptConnect(deviceId).catch((): void => {});
    });
  }

  private async attemptConnect(deviceId: string): Promise<void> {
    const state = this.states.get(deviceId);
    if (this.destroyed || state === undefined || state.connecting) return;
    if (this.transport.isReady(deviceId)) {
      this.cancelStateTimers(state);
      state.retryAttempt = 0;
      return;
    }
    state.connecting = true;
    try {
      await this.transport.connect(state.peer);
      if (this.destroyed || this.states.get(deviceId) !== state) {
        if (this.transport.isReady(deviceId)) {
          this.transport.disconnectPeer(deviceId).catch((): void => {});
        }
        return;
      }
      if (!this.transport.isReady(deviceId)) throw new Error('E_PEER_NOT_READY');
      this.cancelStateTimers(state);
      state.retryAttempt = 0;
    } catch (_) {
      if (!this.destroyed && this.states.get(deviceId) === state) this.scheduleRetry(state);
    } finally {
      if (this.states.get(deviceId) === state) state.connecting = false;
    }
  }

  private scheduleRetry(state: PeerMeshState): void {
    if (this.destroyed || state.retryTimer !== undefined) return;
    const index = Math.min(state.retryAttempt, RETRY_DELAYS_MS.length - 1);
    const delayMs = RETRY_DELAYS_MS[index];
    state.retryAttempt += 1;
    const deviceId = state.peer.deviceId;
    state.retryTimer = this.timer.after(delayMs, (): void => {
      const current = this.states.get(deviceId);
      if (this.destroyed || current !== state) return;
      state.retryTimer = undefined;
      this.attemptConnect(deviceId).catch((): void => {});
    });
  }

  private scheduleTopologyReconcile(): void {
    if (this.destroyed) return;
    if (this.topologyTimer !== undefined) this.timer.cancel(this.topologyTimer);
    this.topologyTimer = this.timer.after(TOPOLOGY_DEBOUNCE_MS, (): void => {
      this.topologyTimer = undefined;
      if (this.destroyed) return;
      this.reconcile().catch((): void => {});
    });
  }

  private hasPendingConnections(): boolean {
    for (const state of this.states.values()) {
      if (this.transport.isReady(state.peer.deviceId)) continue;
      if (state.connecting || state.graceTimer !== undefined || state.retryTimer !== undefined) return true;
    }
    return false;
  }

  private readyDeviceIds(): string[] {
    const result: string[] = [];
    for (const state of this.states.values()) {
      if (this.transport.isReady(state.peer.deviceId)) result.push(state.peer.deviceId);
    }
    result.sort();
    return result;
  }

  private cancelState(state: PeerMeshState): void {
    this.cancelStateTimers(state);
    state.connecting = false;
  }

  private cancelStateTimers(state: PeerMeshState): void {
    this.cancelGrace(state);
    if (state.retryTimer !== undefined) {
      this.timer.cancel(state.retryTimer);
      state.retryTimer = undefined;
    }
  }

  private cancelGrace(state: PeerMeshState): void {
    if (state.graceTimer !== undefined) {
      this.timer.cancel(state.graceTimer);
      state.graceTimer = undefined;
    }
  }

  private uniqueSortedPeers(peers: PeerDevice[], localDeviceId: string): PeerDevice[] {
    const unique = new Map<string, PeerDevice>();
    for (const peer of peers) {
      if (peer.deviceId.length > 0 && peer.deviceId !== localDeviceId && !unique.has(peer.deviceId)) {
        unique.set(peer.deviceId, peer);
      }
    }
    return Array.from(unique.values()).sort((left: PeerDevice, right: PeerDevice): number =>
      left.deviceId < right.deviceId ? -1 : (left.deviceId > right.deviceId ? 1 : 0));
  }
}
