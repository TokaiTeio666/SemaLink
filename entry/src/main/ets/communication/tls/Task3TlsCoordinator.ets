import { common } from '@kit.AbilityKit';
import { DskControlHub, DskControlHubListener } from '../control/DskControlHub';
import { ControlEnvelope } from '../control/ControlModels';
import { AppError } from '../../common/AppError';
import { Logger } from '../../common/Logger';
import { PeerDevice } from '../../model/AppModels';
import { PeerConnectionPool } from '../PeerConnectionPool';

interface IncomingPeerInfo { deviceId?: string; }
interface DataFrameMessage { type: string; payload: Object; }
interface TimestampPayload { sentAtMs: number; }
interface DataFrameEnvelope { type: string; payload: TimestampPayload; }

export interface Task3TlsCoordinatorOptions {
  context: common.UIAbilityContext;
  bundleName: string;
  logger?: Logger;
}

/** Task3 compatibility facade. Data now stays entirely on authenticated DSK/SoftBus. */
export class Task3TlsCoordinator implements DskControlHubListener {
  readonly dsk: DskControlHub;
  readonly pool: PeerConnectionPool;
  private readonly logger: Logger;
  private readonly peers = new Map<string, PeerDevice>();
  private destroyed: boolean = false;

  constructor(options: Task3TlsCoordinatorOptions) {
    this.logger = options.logger ?? new Logger();
    this.dsk = new DskControlHub(options.context, options.bundleName, this.logger, undefined, this);
    this.pool = new PeerConnectionPool(this.dsk);
  }

  async connect(peer: PeerDevice): Promise<void> {
    this.logger.info('DSK_PROBE_CONNECT_START', 'device=' + this.mask(peer.deviceId));
    this.peers.set(peer.deviceId, peer);
    await this.pool.refreshPeers(Array.from(this.peers.values()));
    this.installDataHandler(peer.deviceId);
    if (this.dsk.stateOf(peer.deviceId) === 'READY' && this.pool.stateOf(peer.deviceId) === 'FAILED') {
      await this.dsk.disconnect(peer.deviceId);
    }
    if (this.dsk.stateOf(peer.deviceId) === 'READY' && this.pool.stateOf(peer.deviceId) === 'READY') {
      return;
    }
    try {
      await this.dsk.connect(peer);
      this.logger.info('DSK_PROBE_SESSION_READY', 'device=' + this.mask(peer.deviceId));
      const bound = await this.pool.beginBinding(peer.deviceId);
      if (!bound) {
        this.logger.error('DSK_PROBE_BIND_FAILED', 'device=' + this.mask(peer.deviceId));
        throw new Error('E_DSK_BIND_FAILED');
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : 'unknown';
      this.logger.error('DSK_PROBE_CONNECT_FAILED', 'device=' + this.mask(peer.deviceId) + ' error=' + message);
      throw error as Error;
    }
    this.logger.info('DATA_BIND_ACK', 'device=' + this.mask(peer.deviceId));
  }

  accept(want: Record<string, Object>): boolean {
    const raw = want['ohos.extra.param.key.supportCollaborateIndex'];
    if (typeof raw === 'object' && raw !== null) {
      const params = raw as Record<string, Object>;
      const peer = params['PeerInfo'] as IncomingPeerInfo;
      if (peer !== undefined && typeof peer.deviceId === 'string' && peer.deviceId.length > 0) {
        const device: PeerDevice = { deviceId: peer.deviceId, deviceName: '', deviceType: 'phone' };
        this.peers.set(device.deviceId, device);
        this.pool.refreshPeers(Array.from(this.peers.values())).then((): void => {
          this.installDataHandler(device.deviceId);
        }).catch((): void => {});
      }
    }
    return this.dsk.accept(want);
  }

  onControlReady(_deviceId: string): void {}
  onControlMessage(_deviceId: string, _envelope: ControlEnvelope): void {}
  onControlClosed(deviceId: string, _error?: AppError): void { this.pool.close(deviceId).catch((): void => {}); }

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
    this.dsk.destroy();
    await this.pool.destroy();
  }

  private installDataHandler(deviceId: string): void {
    this.pool.onDataMessage(deviceId, (text: string): void => {
      let message: DataFrameMessage;
      try { message = JSON.parse(text) as DataFrameMessage; } catch (_) { return; }
      if (message.type !== 'DATA_PING') return;
      const pong: DataFrameEnvelope = { type: 'DATA_PONG', payload: { sentAtMs: Date.now() } };
      this.pool.send(deviceId, JSON.stringify(pong))
        .then((): void => this.logger.info('DATA_PONG', 'device=' + this.mask(deviceId)))
        .catch((error: Error): void => this.logger.error('DATA_PONG_FAILED', error.message));
    });
  }

  private mask(deviceId: string): string { return deviceId.length <= 4 ? '****' : '****' + deviceId.slice(-4); }
}
