import { common } from '@kit.AbilityKit';
import { abilityConnectionManager } from '@kit.DistributedServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppError, ErrorStage } from '../../common/AppError';
import { Logger } from '../../common/Logger';
import { PeerDevice } from '../../model/AppModels';
import { CollaborationApi, ProductionCollaborationApi, SessionEventInfo } from './CollaborationApi';
import { ControlCodec, utf8ByteLength } from './ControlCodec';
import { ControlEnvelope, ControlChannelState } from './ControlModels';
import { DskDataTransport } from './DskDataChannel';

const SERVICE = 'semalink.dsk.data.v1';
const MODULE = 'entry'; const ABILITY = 'EntryAbility';
const KEY = 'ohos.extra.param.key.supportCollaborateIndex';
const PEER_INFO_KEY = abilityConnectionManager.CollaborationKeys.PEER_INFO;
const CONNECT_OPTIONS_KEY = abilityConnectionManager.CollaborationKeys.CONNECT_OPTIONS;
const CHANNEL_KEY = 'semalink.channel';
const CHANNEL_VALUE = 'DSK_DATA';
const SEND_READY_TIMEOUT_MS = 3000;
const SEND_READY_POLL_MS = 25;
export interface DskControlHubListener { onControlReady(deviceId: string): void; onControlMessage(deviceId: string, envelope: ControlEnvelope): void; onControlClosed(deviceId: string, error?: AppError): void; }
export type DskDataMessageHandler = (deviceId: string, frame: Object) => void;
export type SessionDirection = 'INBOUND' | 'OUTBOUND';
interface Session {
  device: PeerDevice;
  id: number;
  state: ControlChannelState;
  direction: SessionDirection;
  createdOrder: number;
}
export class DskControlHub implements DskDataTransport {
  private readonly sessionsByDevice = new Map<string, Session[]>(); private readonly deviceBySession = new Map<number, string>();
  private readonly terminalStates = new Map<string, ControlChannelState>();
  private readonly codec = new ControlCodec(); private destroyed = false;
  private readonly dataHandlers = new Set<DskDataMessageHandler>();
  private readonly seenByDevice = new Map<string, string[]>();
  private createdOrder: number = 0;
  private localDeviceId: string;
  private readonly context: common.UIAbilityContext; private readonly bundleName: string; private readonly logger: Logger; private readonly api: CollaborationApi; private readonly listener: DskControlHubListener | null;
  constructor(context: common.UIAbilityContext, bundleName: string, logger: Logger, api?: CollaborationApi,
    listener?: DskControlHubListener, localDeviceId: string = '') {
    this.context = context;
    this.bundleName = bundleName;
    this.logger = logger;
    this.api = api ?? new ProductionCollaborationApi();
    this.listener = listener ?? null;
    this.localDeviceId = localDeviceId;
  }
  async connect(peer: PeerDevice): Promise<void> {
    if (this.destroyed) throw new AppError('E_TRANSPORT_DESTROYED', 'transport destroyed', ErrorStage.CONNECTION, false);
    const info: abilityConnectionManager.PeerInfo = { deviceId: peer.deviceId, bundleName: this.bundleName, moduleName: MODULE, abilityName: ABILITY };
    const parameters: Record<string, string> = { 'semalink.role': 'RESPONDER' };
    parameters[CHANNEL_KEY] = CHANNEL_VALUE;
    const options: abilityConnectionManager.ConnectOptions = { needSendData: true, startOptions: abilityConnectionManager.StartOptionParams.START_IN_FOREGROUND, parameters: parameters };
    let id: number; try { id = this.api.create(SERVICE, this.context, info, options); } catch (_) { throw new AppError('E_CONNECT_FAILED', 'connection session creation failed', ErrorStage.CONNECTION, true); } const session: Session = { device: peer, id, state: 'CONNECTING', direction: 'OUTBOUND', createdOrder: this.createdOrder++ };
    const list = this.sessionsByDevice.get(peer.deviceId) ?? []; list.push(session); this.sessionsByDevice.set(peer.deviceId, list); this.deviceBySession.set(id, peer.deviceId); this.bind(session);
    try {
      const result = await this.api.connect(id);
      if (!result.isConnected) {
        const reason = result.reason ?? 'connection rejected';
        const error = new AppError('E_CONNECT_REJECTED', reason, ErrorStage.CONNECTION, true, result.errorCode);
        this.logger.error('DSK_CONNECT_REJECTED', 'device=' + peer.deviceId.slice(-4) +
          ' code=' + (result.errorCode ?? -1).toString() + ' reason=' + reason);
        this.fail(id, error);
        throw error;
      }
      this.ready(id);
    } catch (e) {
      const businessError = e as BusinessError;
      const error = e instanceof AppError ? e : new AppError(
        'E_CONNECT_FAILED',
        businessError.message ?? 'connection failed',
        ErrorStage.CONNECTION,
        true,
        businessError.code
      );
      this.logger.error('DSK_CONNECT_FAILED', 'device=' + peer.deviceId.slice(-4) +
        ' code=' + (error.systemCode ?? -1).toString() + ' message=' + error.message);
      this.fail(id, error);
      throw error;
    }
  }
  accept(want: Record<string, Object>): boolean {
    if (this.destroyed) return false;
    const raw = want[KEY];
    let peer: abilityConnectionManager.PeerInfo;
    let options: abilityConnectionManager.ConnectOptions;
    let token: Object | undefined;
    if (typeof raw === 'object' && raw !== null) {
      const p = raw as Record<string, Object>;
      peer = (p['PeerInfo'] ?? p[PEER_INFO_KEY]) as abilityConnectionManager.PeerInfo;
      options = (p['ConnectOption'] ?? p[CONNECT_OPTIONS_KEY]) as abilityConnectionManager.ConnectOptions;
      token = p['ohos.dms.collabToken'] ?? p['ohos.collaboration.key.token'] ??
        p['ohos.collaboration.key.collaborationToken'];
    } else {
      peer = want[PEER_INFO_KEY] as abilityConnectionManager.PeerInfo;
      options = want[CONNECT_OPTIONS_KEY] as abilityConnectionManager.ConnectOptions;
      token = want['ohos.dms.collabToken'] ?? want['ohos.collaboration.key.token'] ??
        want['ohos.collaboration.key.collaborationToken'];
    }
    const innerKeys: string = typeof raw === 'object' && raw !== null ?
      Object.keys(raw as Record<string, Object>).join(',') : '';
    this.logger.info('DSK_COLLAB_RECEIVED', 'topKeys=' + Object.keys(want).join(',') +
      ' innerKeys=' + innerKeys + ' peer=' + (typeof peer === 'object').toString() +
      ' options=' + (typeof options === 'object').toString() +
      ' tokenLength=' + (typeof token === 'string' ? (token as string).length : 0).toString());
    const parameters = options?.parameters as Record<string, string>;
    if (typeof peer !== 'object' || typeof options !== 'object' || typeof token !== 'string' ||
      (token as string).length === 0 || typeof parameters !== 'object' ||
      parameters[CHANNEL_KEY] !== CHANNEL_VALUE) {
      this.logger.error('DSK_COLLAB_REJECTED', 'reason=required_field_or_channel_missing');
      return false;
    }
    if (typeof peer.deviceId !== 'string' || peer.deviceId.length === 0) {
      this.logger.error('DSK_COLLAB_REJECTED', 'reason=peer_device_id_missing');
      return false;
    }
    const device: PeerDevice = { deviceId: peer.deviceId, deviceName: '', deviceType: '' }; let id: number;
    try { id = this.api.create(SERVICE, this.context, peer, options); } catch (_) { return false; }
    const session: Session = { device, id, state: 'CONNECTING', direction: 'INBOUND', createdOrder: this.createdOrder++ }; const list = this.sessionsByDevice.get(device.deviceId) ?? []; list.push(session); this.sessionsByDevice.set(device.deviceId, list); this.deviceBySession.set(id, device.deviceId); this.bind(session); try { this.api.accept(id, token as string).catch((e: BusinessError) => this.fail(id, new AppError('E_ACCEPT_FAILED', e.message ?? 'accept failed', ErrorStage.CONNECTION, true, e.code))); } catch (_) { this.remove(session, false); return false; } return true;
  }
  async send(deviceId: string, envelope: ControlEnvelope): Promise<void> {
    const session: Session | undefined = await this.waitForReady(deviceId);
    if (session === undefined) throw new AppError('E_SESSION_NOT_READY', 'session not ready', ErrorStage.CONNECTION, true);
    await this.api.send(session.id, this.codec.encode(envelope));
  }
  async sendData(deviceId: string, frame: Object): Promise<void> {
    const session: Session | undefined = await this.waitForReady(deviceId);
    if (session === undefined) throw new AppError('E_SESSION_NOT_READY', 'session not ready', ErrorStage.CONNECTION, true);
    const text = JSON.stringify(frame);
    if (utf8ByteLength(text) > 1024) throw new AppError('E_CONTROL_FRAME_TOO_LARGE', 'data frame exceeds limit', ErrorStage.PROTOCOL, false);
    await this.api.send(session.id, text);
  }
  onDataMessage(handler: DskDataMessageHandler): void { this.dataHandlers.add(handler); }
  setLocalDeviceId(deviceId: string): void { this.localDeviceId = deviceId; }
  canonicalSessionDirection(deviceId: string): SessionDirection | undefined { return this.canonical(deviceId)?.direction; }
  async disconnect(deviceId: string): Promise<void> { const list = this.sessionsByDevice.get(deviceId) ?? []; list.slice().forEach((s: Session) => this.remove(s, true)); this.seenByDevice.delete(deviceId); }
  deviceIds(): string[] { const ids: string[] = []; for (const deviceId of this.sessionsByDevice.keys()) ids.push(deviceId); ids.sort(); return ids; }
  stateOf(deviceId: string): ControlChannelState { const list = this.sessionsByDevice.get(deviceId) ?? []; if (list.some((s: Session) => s.state === 'READY')) return 'READY'; if (list.some((s: Session) => s.state === 'CONNECTING')) return 'CONNECTING'; return this.terminalStates.get(deviceId) ?? 'DISCONNECTED'; }
  destroy(): void { if (this.destroyed) return; this.destroyed = true; for (const list of this.sessionsByDevice.values()) list.slice().forEach((s: Session) => this.remove(s, true)); this.sessionsByDevice.clear(); this.deviceBySession.clear(); this.seenByDevice.clear(); }
  private bind(s: Session): void { this.api.onConnect(s.id, () => this.ready(s.id)); this.api.onDisconnect(s.id, (i: SessionEventInfo) => this.closed(s.id, i)); this.api.onMessage(s.id, (i: SessionEventInfo) => this.message(s.id, i.msg ?? '')); }
  private ready(id: number): void {
    const d = this.deviceBySession.get(id);
    if (d === undefined) return;
    const s = (this.sessionsByDevice.get(d) ?? []).find((x: Session) => x.id === id);
    if (s === undefined || s.state === 'READY') return;
    s.state = 'READY';
    const canonical = this.canonical(d);
    const preferred = this.preferredDirection(d);
    if (canonical !== undefined && preferred !== undefined && canonical.direction === preferred) {
      const redundant = (this.sessionsByDevice.get(d) ?? []).filter((item: Session): boolean =>
        item.id !== canonical.id && (item.state === 'READY' || item.state === 'CONNECTING'));
      redundant.forEach((item: Session): void => this.remove(item, true));
    }
    this.terminalStates.delete(d);
    this.logger.info('DSK_SESSION_READY', 'device=' + d.slice(-4));
    if (canonical?.id === id) this.listener?.onControlReady(d);
  }
  private async waitForReady(deviceId: string): Promise<Session | undefined> {
    const deadline: number = Date.now() + SEND_READY_TIMEOUT_MS;
    while (Date.now() < deadline) {
      const list = this.sessionsByDevice.get(deviceId) ?? [];
      const ready: Session | undefined = this.canonical(deviceId);
      if (ready !== undefined) return ready;
      if (!list.some((session: Session) => session.state === 'CONNECTING')) return undefined;
      await new Promise<void>((resolve) => setTimeout(resolve, SEND_READY_POLL_MS));
    }
    return this.canonical(deviceId);
  }
  private message(id: number, text: string): void { const d = this.deviceBySession.get(id); if (d === undefined) return; const s = (this.sessionsByDevice.get(d) ?? []).find((x: Session) => x.id === id); if (s === undefined) return; try { const parsed = JSON.parse(text) as Object; if (parsed !== null && typeof parsed === 'object' && (parsed as Record<string, Object>)['channel'] === 'DATA') { this.logger.info('DSK_DATA_FRAME_RECEIVED', 'device=' + d.slice(-4)); this.dataHandlers.forEach((handler: DskDataMessageHandler): void => handler(d, parsed)); return; } const e = this.codec.decode(text); if (this.isDuplicate(d, e.messageId)) return; this.listener?.onControlMessage(d, e); } catch (_) { this.fail(id, new AppError('E_CONTROL_INVALID', 'invalid control message', ErrorStage.PROTOCOL, false)); } }
  private closed(id: number, info: SessionEventInfo): void { const d = this.deviceBySession.get(id); if (d === undefined) return; this.fail(id, new AppError('E_SESSION_CLOSED', 'session closed', ErrorStage.CONNECTION, true, info.reason)); }
  private fail(id: number, error: AppError): void {
    const d = this.deviceBySession.get(id);
    if (d === undefined) return;
    const s = (this.sessionsByDevice.get(d) ?? []).find((x: Session) => x.id === id);
    if (s === undefined) return;
    s.state = 'FAILED';
    this.remove(s, false);
    const remaining = this.sessionsByDevice.get(d) ?? [];
    if (remaining.some((item: Session): boolean => item.state === 'READY' || item.state === 'CONNECTING')) return;
    this.terminalStates.set(d, 'FAILED');
    this.listener?.onControlClosed(d, error);
  }
  private preferredDirection(deviceId: string): SessionDirection | undefined {
    if (this.localDeviceId.length === 0 || this.localDeviceId === deviceId) return undefined;
    return this.localDeviceId < deviceId ? 'OUTBOUND' : 'INBOUND';
  }
  private canonical(deviceId: string): Session | undefined {
    const ready = (this.sessionsByDevice.get(deviceId) ?? [])
      .filter((item: Session): boolean => item.state === 'READY');
    const preferred = this.preferredDirection(deviceId);
    const preferredSession = ready.find((item: Session): boolean => item.direction === preferred);
    if (preferredSession !== undefined) return preferredSession;
    ready.sort((left: Session, right: Session): number => left.createdOrder - right.createdOrder);
    return ready[0];
  }
  private isDuplicate(deviceId: string, messageId: string): boolean {
    const ids = this.seenByDevice.get(deviceId) ?? [];
    if (ids.indexOf(messageId) >= 0) return true;
    ids.push(messageId);
    if (ids.length > 256) ids.shift();
    this.seenByDevice.set(deviceId, ids);
    return false;
  }
  private remove(s: Session, disconnect: boolean): void { this.api.offAll(s.id); if (disconnect) this.api.disconnect(s.id); this.api.destroy(s.id); const list = this.sessionsByDevice.get(s.device.deviceId) ?? []; const index = list.findIndex((x: Session) => x.id === s.id); if (index >= 0) list.splice(index, 1); if (list.length === 0) { this.sessionsByDevice.delete(s.device.deviceId); this.seenByDevice.delete(s.device.deviceId); if (disconnect) this.terminalStates.set(s.device.deviceId, 'DISCONNECTED'); } this.deviceBySession.delete(s.id); }
}
