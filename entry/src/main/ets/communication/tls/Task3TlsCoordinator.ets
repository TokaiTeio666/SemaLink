import { common } from '@kit.AbilityKit';
import { DskControlHub, DskControlHubListener } from '../control/DskControlHub';
import { ControlEnvelope } from '../control/ControlModels';
import { AppError } from '../../common/AppError';
import { Logger } from '../../common/Logger';
import { PeerDevice } from '../../model/AppModels';
import { PeerConnectionPool, PeerConnectionStateListener } from '../PeerConnectionPool';

interface IncomingPeerInfo { deviceId?: string; }
interface DataFrameMessage { type: string; payload: Object; }
interface TimestampPayload { sentAtMs: number; }
interface DataFrameEnvelope { type: string; payload: TimestampPayload; }

export interface Task3TlsCoordinatorOptions {
  context: common.UIAbilityContext;
  bundleName: string;
  logger?: Logger;
}

export type Task3ConnectionStateObserver = (peer: PeerDevice, failureCode: string) => void;

/** Task3 compatibility facade. Data now stays entirely on authenticated DSK/SoftBus. */
export class Task3TlsCoordinator implements DskControlHubListener {
  readonly dsk: DskControlHub;
  readonly pool: PeerConnectionPool;
  private readonly logger: Logger;
  private readonly peers = new Map<string, PeerDevice>();
  private readonly connecting = new Map<string, Promise<void>>();
  private readonly dataObservers = new Set<(deviceId: string, text: string) => void>();
  private readonly connectionObservers = new Set<Task3ConnectionStateObserver>();
  private readonly failures = new Map<string, string>();
  private readonly installedDataHandlers = new Set<string>();
  private readonly poolStateObserver: PeerConnectionStateListener;
  private destroyed: boolean = false;

  constructor(options: Task3TlsCoordinatorOptions) {
    this.logger = options.logger ?? new Logger();
    this.dsk = new DskControlHub(options.context, options.bundleName, this.logger, undefined, this);
    this.pool = new PeerConnectionPool(this.dsk);
    this.poolStateObserver = (deviceId: string): void => this.publishConnectionState(deviceId);
    this.pool.onStateChanged(this.poolStateObserver);
  }

  async connect(peer: PeerDevice): Promise<void> {
    const pending = this.connecting.get(peer.deviceId);
    if (pending !== undefined) {
      await pending;
      return;
    }
    const attempt = this.connectInternal(peer);
    this.connecting.set(peer.deviceId, attempt);
    try {
      await attempt;
    } finally {
      if (this.connecting.get(peer.deviceId) === attempt) {
        this.connecting.delete(peer.deviceId);
      }
    }
  }

  private async connectInternal(peer: PeerDevice): Promise<void> {
    this.logger.info('DSK_PROBE_CONNECT_START', 'device=' + this.mask(peer.deviceId));
    this.peers.set(peer.deviceId, peer);
    this.failures.delete(peer.deviceId);
    await this.pool.refreshPeers(Array.from(this.peers.values()));
    this.publishConnectionState(peer.deviceId);
    this.installDataHandler(peer.deviceId);
    if (this.dsk.stateOf(peer.deviceId) === 'READY' && this.pool.stateOf(peer.deviceId) === 'FAILED') {
      await this.dsk.disconnect(peer.deviceId);
    }
    if (this.dsk.stateOf(peer.deviceId) === 'READY' && this.pool.stateOf(peer.deviceId) === 'READY') {
      return;
    }
    try {
      const controlAttempt: Promise<void> = this.dsk.connect(peer);
      this.publishConnectionState(peer.deviceId);
      await controlAttempt;
      this.logger.info('DSK_PROBE_SESSION_READY', 'device=' + this.mask(peer.deviceId));
      const bound = await this.pool.beginBinding(peer.deviceId);
      if (!bound) {
        this.logger.error('DSK_PROBE_BIND_FAILED', 'device=' + this.mask(peer.deviceId));
        throw new Error('E_DSK_BIND_FAILED');
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      const failureCode: string = error instanceof AppError ? error.code :
        (message.indexOf('E_') === 0 ? message : 'E_CONNECT_FAILED');
      this.failures.set(peer.deviceId, failureCode);
      this.publishConnectionState(peer.deviceId);
      this.logger.error('DSK_PROBE_CONNECT_FAILED', 'device=' + this.mask(peer.deviceId) +
        ' error=' + (message.length > 0 ? message : 'unknown') +
        ' detail=' + JSON.stringify(error));
      throw error as Error;
    }
    this.logger.info('DATA_BIND_ACK', 'device=' + this.mask(peer.deviceId));
  }

  accept(want: Record<string, Object>): boolean {
    const raw = want['ohos.extra.param.key.supportCollaborateIndex'];
    const params = typeof raw === 'object' && raw !== null ? raw as Record<string, Object> : want;
    const peer = (params['PeerInfo'] ?? params['ohos.collaboration.key.peerInfo']) as IncomingPeerInfo;
    if (peer !== undefined && typeof peer.deviceId === 'string' && peer.deviceId.length > 0) {
      const device: PeerDevice = { deviceId: peer.deviceId, deviceName: '', deviceType: 'phone' };
      this.peers.set(device.deviceId, device);
      this.pool.refreshPeers(Array.from(this.peers.values())).then((): void => {
        this.installDataHandler(device.deviceId);
      }).catch((): void => {});
    }
    const accepted: boolean = this.dsk.accept(want);
    if (peer !== undefined && typeof peer.deviceId === 'string') this.publishConnectionState(peer.deviceId);
    return accepted;
  }

  onControlReady(deviceId: string): void { this.publishConnectionState(deviceId); }
  onControlMessage(_deviceId: string, _envelope: ControlEnvelope): void {}
  onControlClosed(deviceId: string, error?: AppError): void {
    this.failures.set(deviceId, error?.code ?? 'E_SESSION_CLOSED');
    this.installedDataHandlers.delete(deviceId);
    this.pool.close(deviceId).then((): void => this.publishConnectionState(deviceId)).catch((): void => {
      this.publishConnectionState(deviceId);
    });
  }

  onConnectionStateChanged(observer: Task3ConnectionStateObserver): void {
    this.connectionObservers.add(observer);
  }

  removeConnectionStateChanged(observer: Task3ConnectionStateObserver): void {
    this.connectionObservers.delete(observer);
  }

  onDataMessage(observer: (deviceId: string, text: string) => void): void {
    this.dataObservers.add(observer);
  }

  removeDataMessage(observer: (deviceId: string, text: string) => void): void {
    this.dataObservers.delete(observer);
  }

  async probe(deviceId: string): Promise<void> {
    if (this.pool.stateOf(deviceId) !== 'READY') throw new Error('E_DSK_NOT_READY');
    const pong = new Promise<boolean>((resolve) => {
      const timer = setTimeout((): void => resolve(false), 5000);
      this.pool.onDataMessage(deviceId, (text: string): void => {
        let message: DataFrameMessage;
        try { message = JSON.parse(text) as DataFrameMessage; } catch (_) { return; }
        if (message.type === 'DATA_PONG') { clearTimeout(timer); resolve(true); }
        if (message.type === 'DATA_PING') {
          const response: DataFrameEnvelope = { type: 'DATA_PONG', payload: { sentAtMs: Date.now() } };
          this.pool.send(deviceId, JSON.stringify(response)).catch((): void => {});
        }
      });
    });
    const ping: DataFrameEnvelope = { type: 'DATA_PING', payload: { sentAtMs: Date.now() } };
    await this.pool.send(deviceId, JSON.stringify(ping));
    this.logger.info('DATA_PING', 'device=' + this.mask(deviceId));
    if (!(await pong)) throw new Error('E_DATA_PONG_TIMEOUT');
    this.logger.info('DATA_PONG', 'device=' + this.mask(deviceId));
  }

  async destroy(): Promise<void> {
    if (this.destroyed) return;
    this.destroyed = true;
    this.pool.removeStateChanged(this.poolStateObserver);
    this.dsk.destroy();
    await this.pool.destroy();
    this.connectionObservers.clear();
    this.failures.clear();
  }

  private installDataHandler(deviceId: string): void {
    if (this.installedDataHandlers.has(deviceId)) return;
    this.installedDataHandlers.add(deviceId);
    this.pool.onDataMessage(deviceId, (text: string): void => {
      let message: DataFrameMessage;
      try { message = JSON.parse(text) as DataFrameMessage; } catch (_) { return; }
      for (const observer of this.dataObservers) observer(deviceId, text);
      if (message.type !== 'DATA_PING') return;
      const pong: DataFrameEnvelope = { type: 'DATA_PONG', payload: { sentAtMs: Date.now() } };
      this.pool.send(deviceId, JSON.stringify(pong))
        .then((): void => this.logger.info('DATA_PONG', 'device=' + this.mask(deviceId)))
        .catch((error: Error): void => this.logger.error('DATA_PONG_FAILED', error.message));
    });
  }

  private publishConnectionState(deviceId: string): void {
    const peer: PeerDevice | undefined = this.peers.get(deviceId);
    if (peer === undefined) return;
    const failureCode: string = this.failures.get(deviceId) ?? '';
    for (const observer of this.connectionObservers) observer(peer, failureCode);
  }

  private mask(deviceId: string): string { return deviceId.length <= 4 ? '****' : '****' + deviceId.slice(-4); }
}
