import { describe, expect, it } from '@ohos/hypium';
import {
  DeviceTopologyProvider,
  DeviceTopologySnapshot
} from '../main/ets/communication/DeviceTopologyProvider';
import {
  MeshPeerTransport,
  MeshTimer,
  PeerMeshOrchestrator
} from '../main/ets/communication/PeerMeshOrchestrator';
import { PeerDevice } from '../main/ets/model/AppModels';

const PEER_A: PeerDevice = { deviceId: 'device-a', deviceName: 'A', deviceType: 'phone' };
const PEER_B: PeerDevice = { deviceId: 'device-b', deviceName: 'B', deviceType: 'phone' };
const PEER_C: PeerDevice = { deviceId: 'device-c', deviceName: 'C', deviceType: 'tablet' };

interface TimerEntry {
  id: number;
  dueAtMs: number;
  delayMs: number;
  callback: () => void;
}

class FakeMeshTimer implements MeshTimer {
  scheduledDelays: number[] = [];
  cancelledDelays: number[] = [];
  private currentMs: number = 0;
  private nextId: number = 1;
  private readonly entries = new Map<number, TimerEntry>();

  after(delayMs: number, callback: () => void): number {
    const id = this.nextId++;
    const entry: TimerEntry = { id: id, dueAtMs: this.currentMs + delayMs, delayMs: delayMs, callback: callback };
    this.entries.set(id, entry);
    this.scheduledDelays.push(delayMs);
    return id;
  }

  cancel(id: number): void {
    const entry = this.entries.get(id);
    if (entry !== undefined) this.cancelledDelays.push(entry.delayMs);
    this.entries.delete(id);
  }

  now(): number { return this.currentMs; }

  sleep(delayMs: number): Promise<void> {
    this.advance(delayMs);
    return Promise.resolve();
  }

  advance(delayMs: number): void {
    const target = this.currentMs + delayMs;
    while (true) {
      let next: TimerEntry | undefined;
      for (const entry of this.entries.values()) {
        if (entry.dueAtMs <= target && (next === undefined || entry.dueAtMs < next.dueAtMs ||
          (entry.dueAtMs === next.dueAtMs && entry.id < next.id))) next = entry;
      }
      if (next === undefined) break;
      this.currentMs = next.dueAtMs;
      this.entries.delete(next.id);
      next.callback();
    }
    this.currentMs = target;
  }

  pendingCount(): number { return this.entries.size; }
}

class FakeTopologyProvider implements DeviceTopologyProvider {
  startCalls: number = 0;
  stopCalls: number = 0;
  snapshotCalls: number = 0;
  maxConcurrentSnapshots: number = 0;
  private activeSnapshots: number = 0;
  private listener: (() => void) | undefined;
  private current: DeviceTopologySnapshot;
  private held: boolean = false;
  private releaseWaiter: (() => void) | undefined;

  constructor(snapshot: DeviceTopologySnapshot) { this.current = snapshot; }

  start(onChanged: () => void): void { this.startCalls += 1; this.listener = onChanged; }

  async snapshot(): Promise<DeviceTopologySnapshot> {
    this.snapshotCalls += 1;
    this.activeSnapshots += 1;
    this.maxConcurrentSnapshots = Math.max(this.maxConcurrentSnapshots, this.activeSnapshots);
    if (this.held) {
      await new Promise<void>((resolve: () => void): void => { this.releaseWaiter = resolve; });
    }
    this.activeSnapshots -= 1;
    return this.current;
  }

  stop(): void { this.stopCalls += 1; this.listener = undefined; }
  setSnapshot(snapshot: DeviceTopologySnapshot): void { this.current = snapshot; }
  emitChanged(): void { this.listener?.(); }
  holdSnapshot(): void { this.held = true; }
  releaseSnapshot(): void { this.held = false; this.releaseWaiter?.(); this.releaseWaiter = undefined; }
}

class FakeMeshTransport implements MeshPeerTransport {
  localDeviceIds: string[] = [];
  registrations: string[][] = [];
  connectCalls: string[] = [];
  disconnectCalls: string[] = [];
  private readonly ready = new Set<string>();
  private readonly failures = new Map<string, number>();

  setLocalDeviceId(deviceId: string): void { this.localDeviceIds.push(deviceId); }

  registerPeers(peers: PeerDevice[]): Promise<void> {
    this.registrations.push(peers.map((peer: PeerDevice): string => peer.deviceId));
    return Promise.resolve();
  }

  async connect(peer: PeerDevice): Promise<void> {
    this.connectCalls.push(peer.deviceId);
    const remaining = this.failures.get(peer.deviceId) ?? 0;
    if (remaining > 0) {
      this.failures.set(peer.deviceId, remaining - 1);
      throw new Error('E_TEST_CONNECT_FAILED');
    }
    this.ready.add(peer.deviceId);
  }

  disconnectPeer(deviceId: string): Promise<void> {
    this.disconnectCalls.push(deviceId);
    this.ready.delete(deviceId);
    return Promise.resolve();
  }

  isReady(deviceId: string): boolean { return this.ready.has(deviceId); }
  failNext(deviceId: string, count: number): void { this.failures.set(deviceId, count); }
  markReady(deviceId: string): void { this.ready.add(deviceId); }
}

async function flushAsync(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

export default function peerMeshOrchestratorTest(): void {
  describe('PeerMeshOrchestrator', () => {
    it('dialsPrimaryPeersImmediatelyAndWaitsThreeSecondsForInboundPeers', 0, async () => {
      const provider = new FakeTopologyProvider({ localDeviceId: 'device-b', peers: [PEER_A, PEER_C] });
      const transport = new FakeMeshTransport();
      const timer = new FakeMeshTimer();
      const mesh = new PeerMeshOrchestrator(provider, transport, timer);

      await mesh.reconcile();
      expect(transport.connectCalls).assertDeepEquals(['device-c']);
      timer.advance(2999);
      await flushAsync();
      expect(transport.connectCalls).assertDeepEquals(['device-c']);
      timer.advance(1);
      await flushAsync();
      expect(transport.connectCalls).assertDeepEquals(['device-c', 'device-a']);
    });

    it('backsOffEachPeerIndependently', 0, async () => {
      const provider = new FakeTopologyProvider({ localDeviceId: 'device-a', peers: [PEER_B] });
      const transport = new FakeMeshTransport();
      const timer = new FakeMeshTimer();
      transport.failNext('device-b', 5);
      const mesh = new PeerMeshOrchestrator(provider, transport, timer);

      await mesh.reconcile();
      expect(timer.scheduledDelays).assertDeepEquals([1000]);
      timer.advance(1000); await flushAsync();
      timer.advance(2000); await flushAsync();
      timer.advance(4000); await flushAsync();
      timer.advance(8000); await flushAsync();

      expect(timer.scheduledDelays).assertDeepEquals([1000, 2000, 4000, 8000, 30000]);
    });

    it('removingOnePeerCancelsOnlyItsRetry', 0, async () => {
      const provider = new FakeTopologyProvider({ localDeviceId: 'device-a', peers: [PEER_B, PEER_C] });
      const transport = new FakeMeshTransport();
      const timer = new FakeMeshTimer();
      transport.failNext('device-b', 1);
      transport.failNext('device-c', 1);
      const mesh = new PeerMeshOrchestrator(provider, transport, timer);
      await mesh.reconcile();
      expect(timer.pendingCount()).assertEqual(2);

      provider.setSnapshot({ localDeviceId: 'device-a', peers: [PEER_C] });
      await mesh.reconcile();

      expect(timer.pendingCount()).assertEqual(1);
      expect(timer.cancelledDelays).assertDeepEquals([1000]);
      expect(transport.disconnectCalls).assertDeepEquals(['device-b']);
    });

    it('serializesAndCoalescesConcurrentReconciles', 0, async () => {
      const provider = new FakeTopologyProvider({ localDeviceId: 'device-a', peers: [] });
      const transport = new FakeMeshTransport();
      const timer = new FakeMeshTimer();
      const mesh = new PeerMeshOrchestrator(provider, transport, timer);
      provider.holdSnapshot();

      const first = mesh.reconcile();
      const second = mesh.reconcile();
      expect(provider.snapshotCalls).assertEqual(1);
      provider.releaseSnapshot();
      await Promise.all([first, second]);

      expect(provider.snapshotCalls).assertEqual(2);
      expect(provider.maxConcurrentSnapshots).assertEqual(1);
    });

    it('returnsOnlyReadyPeersWithinTheQueryBudget', 0, async () => {
      const provider = new FakeTopologyProvider({ localDeviceId: 'device-b', peers: [PEER_A, PEER_C] });
      const transport = new FakeMeshTransport();
      const timer = new FakeMeshTimer();
      transport.markReady('device-c');
      const mesh = new PeerMeshOrchestrator(provider, transport, timer);

      const ready = await mesh.ensureReady(100);

      expect(ready).assertDeepEquals(['device-c']);
      expect(timer.now()).assertEqual(100);
    });

    it('stopsAndCancelsAllCallbacksOnDestroy', 0, async () => {
      const provider = new FakeTopologyProvider({ localDeviceId: 'device-b', peers: [PEER_A] });
      const transport = new FakeMeshTransport();
      const timer = new FakeMeshTimer();
      const mesh = new PeerMeshOrchestrator(provider, transport, timer);
      await mesh.start();
      provider.emitChanged();
      expect(timer.pendingCount()).assertEqual(2);

      mesh.destroy();
      timer.advance(3000);
      await flushAsync();

      expect(provider.stopCalls).assertEqual(1);
      expect(timer.pendingCount()).assertEqual(0);
      expect(transport.connectCalls.length).assertEqual(0);
      expect(transport.disconnectCalls).assertDeepEquals(['device-a']);
    });
  });
}
