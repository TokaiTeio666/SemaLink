import { common } from '@kit.AbilityKit';
import { abilityConnectionManager } from '@kit.DistributedServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppError, ErrorStage } from '../common/AppError';
import { Logger } from '../common/Logger';
import { PeerDevice, maskDeviceId } from '../model/AppModels';
import { Transport, TransportListener } from './Transport';

const SERVICE_NAME: string = 'semalink.communication.v1';
const COLLAB_PARAM_KEY: string = 'ohos.extra.param.key.supportCollaborateIndex';
const COLLAB_PEER_KEY: string = 'PeerInfo';
const COLLAB_OPTION_KEY: string = 'ConnectOption';
const COLLAB_TOKEN_KEY: string = 'ohos.dms.collabToken';

const MODULE_NAME: string = 'entry';
const ABILITY_NAME: string = 'EntryAbility';

interface SessionEventInfo {
  sessionId: number;
  reason?: number;
  msg?: string;
}

interface SessionConnectResult {
  isConnected: boolean;
  errorCode?: number;
  reason?: string;
}

export interface CollaborationApi {
  create(serviceName: string, context: common.UIAbilityContext,
    peerInfo: abilityConnectionManager.PeerInfo,
    connectOptions: abilityConnectionManager.ConnectOptions): number;
  onConnect(sessionId: number, callback: (info: SessionEventInfo) => void): void;
  onDisconnect(sessionId: number, callback: (info: SessionEventInfo) => void): void;
  onMessage(sessionId: number, callback: (info: SessionEventInfo) => void): void;
  offAll(sessionId: number): void;
  connect(sessionId: number): Promise<SessionConnectResult>;
  accept(sessionId: number, token: string): Promise<void>;
  send(sessionId: number, text: string): Promise<void>;
  disconnect(sessionId: number): void;
  destroy(sessionId: number): void;
}

class ProductionCollaborationApi implements CollaborationApi {
  create(serviceName: string, context: common.UIAbilityContext,
    peerInfo: abilityConnectionManager.PeerInfo,
    connectOptions: abilityConnectionManager.ConnectOptions): number {
    try {
      return abilityConnectionManager.createAbilityConnectionSession(
        serviceName,
        context,
        peerInfo,
        connectOptions
      );
    } catch (error) {
      throw error as Error;
    }
  }

  onConnect(sessionId: number, callback: (info: SessionEventInfo) => void): void {
    abilityConnectionManager.on('connect', sessionId, callback);
  }

  onDisconnect(sessionId: number, callback: (info: SessionEventInfo) => void): void {
    abilityConnectionManager.on('disconnect', sessionId, callback);
  }

  onMessage(sessionId: number, callback: (info: SessionEventInfo) => void): void {
    abilityConnectionManager.on('receiveMessage', sessionId, callback);
  }

  offAll(sessionId: number): void {
    abilityConnectionManager.off('connect', sessionId);
    abilityConnectionManager.off('disconnect', sessionId);
    abilityConnectionManager.off('receiveMessage', sessionId);
  }

  connect(sessionId: number): Promise<SessionConnectResult> {
    return abilityConnectionManager.connect(sessionId);
  }

  accept(sessionId: number, token: string): Promise<void> {
    return abilityConnectionManager.acceptConnect(sessionId, token);
  }

  send(sessionId: number, text: string): Promise<void> {
    return abilityConnectionManager.sendMessage(sessionId, text);
  }

  disconnect(sessionId: number): void {
    abilityConnectionManager.disconnect(sessionId);
  }

  destroy(sessionId: number): void {
    abilityConnectionManager.destroyAbilityConnectionSession(sessionId);
  }
}

export class CollaborationTransport implements Transport {
  private listener: TransportListener | null = null;
  private sessionId: number = -1;
  private connected: boolean = false;
  private destroyed: boolean = false;
  private peerDevice: PeerDevice | null = null;
  private api: CollaborationApi;
  private context: common.UIAbilityContext;
  private bundleName: string;
  private logger: Logger;

  constructor(context: common.UIAbilityContext, bundleName: string, logger: Logger,
    api?: CollaborationApi) {
    this.context = context;
    this.bundleName = bundleName;
    this.logger = logger;
    this.api = api ?? new ProductionCollaborationApi();
  }

  setListener(listener: TransportListener): void {
    this.listener = listener;
  }

  async connect(peer: PeerDevice): Promise<void> {
    if (this.destroyed) {
      throw new AppError('E_TRANSPORT_DESTROYED', '传输组件已销毁', ErrorStage.CONNECTION, false);
    }
    if (this.sessionId >= 0) {
      this.releaseSession(this.sessionId);
    }
    this.peerDevice = peer;
    const peerInfo: abilityConnectionManager.PeerInfo = {
      deviceId: peer.deviceId,
      bundleName: this.bundleName,
      moduleName: MODULE_NAME,
      abilityName: ABILITY_NAME
    };
    const connectOptions: abilityConnectionManager.ConnectOptions = {
      needSendData: true,
      startOptions: abilityConnectionManager.StartOptionParams.START_IN_FOREGROUND,
      parameters: { 'semalink.role': 'RESPONDER' }
    };
    try {
      this.sessionId = this.api.create(SERVICE_NAME, this.context, peerInfo, connectOptions);
    } catch (error) {
      throw this.mapBusinessError(error as BusinessError);
    }
    const sessionId: number = this.sessionId;

    this.api.onConnect(sessionId, (info: SessionEventInfo) => {
      this.markConnected(sessionId);
    });

    this.api.onDisconnect(sessionId, (info: SessionEventInfo) => {
      this.handleDisconnect(sessionId, info);
    });

    this.api.onMessage(sessionId, (info: SessionEventInfo) => {
      this.handleMessage(sessionId, info);
    });

    try {
      let result: SessionConnectResult = await this.api.connect(sessionId);
      if (!result.isConnected) {
        let ec: number = 0;
        if (result.errorCode !== undefined) {
          ec = result.errorCode;
        }
        let rs: string = '';
        if (result.reason !== undefined) {
          rs = result.reason;
        }
        this.logger.error('collaboration.connectRejected',
          'errorCode=' + ec.toString() + ' reason=' + rs);
        this.releaseSession(sessionId);
        throw new AppError('E_CONNECT_REJECTED',
          '连接被拒绝: ' + rs, ErrorStage.CONNECTION, true, result.errorCode);
      }
      this.markConnected(sessionId);
    } catch (error) {
      if (error instanceof AppError) {
        throw error;
      }
      this.releaseSession(sessionId);
      throw this.mapBusinessError(error as BusinessError);
    }
  }

  accept(wantParam: Record<string, Object>): boolean {
    if (this.destroyed) {
      return false;
    }
    const rawCollabParam = wantParam[COLLAB_PARAM_KEY];
    if (rawCollabParam === undefined || rawCollabParam === null ||
      typeof rawCollabParam !== 'object') {
      this.logger.error('COLLAB_INNER_PARAM_MISSING',
        'hasPeerInfo=false hasConnectOptions=false hasToken=false tokenLength=0');
      return false;
    }
    const collabParam = rawCollabParam as Record<string, Object>;
    this.logger.info('COLLAB_INNER_PARAM_FOUND', '');

    const rawPeer = collabParam[COLLAB_PEER_KEY];
    const rawOptions = collabParam[COLLAB_OPTION_KEY];
    const rawToken = collabParam[COLLAB_TOKEN_KEY];
    const hasPeerInfo: boolean = rawPeer !== undefined && rawPeer !== null && typeof rawPeer === 'object';
    const hasConnectOptions: boolean = rawOptions !== undefined && rawOptions !== null &&
      typeof rawOptions === 'object';
    const hasToken: boolean = typeof rawToken === 'string' && (rawToken as string).length > 0;
    const tokenLength: number = typeof rawToken === 'string' ? (rawToken as string).length : 0;

    if (!hasPeerInfo || !hasConnectOptions || !hasToken) {
      this.logger.error('COLLAB_REQUIRED_FIELD_MISSING',
        'hasPeerInfo=' + hasPeerInfo.toString() +
        ' hasConnectOptions=' + hasConnectOptions.toString() +
        ' hasToken=' + hasToken.toString() +
        ' tokenLength=' + tokenLength.toString());
      return false;
    }

    const peerInfo = rawPeer as abilityConnectionManager.PeerInfo;
    const connectOptions = rawOptions as abilityConnectionManager.ConnectOptions;
    const collabToken = rawToken as string;

    this.peerDevice = {
      deviceId: peerInfo.deviceId,
      deviceName: '',
      deviceType: ''
    };
    this.logger.info('COLLAB_PEER_FOUND', 'hasPeerInfo=true peerId=' + maskDeviceId(peerInfo.deviceId));
    this.logger.info('COLLAB_OPTIONS_FOUND', 'hasConnectOptions=true');
    this.logger.info('COLLAB_TOKEN_FOUND',
      'hasToken=true tokenLength=' + tokenLength.toString());

    if (this.sessionId >= 0) {
      this.releaseSession(this.sessionId);
    }
    try {
      this.sessionId = this.api.create(SERVICE_NAME, this.context, peerInfo, connectOptions);
    } catch (error) {
      const businessError = error as BusinessError;
      this.logger.error('COLLAB_SESSION_CREATE_FAILED',
        'code=' + businessError.code.toString() + ' message=' + businessError.message);
      return false;
    }
    const acceptedSessionId: number = this.sessionId;
    this.logger.info('COLLAB_SESSION_CREATED', '');

    this.api.onConnect(acceptedSessionId, (info: SessionEventInfo) => {
      this.markConnected(acceptedSessionId);
    });

    this.api.onDisconnect(acceptedSessionId, (info: SessionEventInfo) => {
      this.handleDisconnect(acceptedSessionId, info);
    });

    this.api.onMessage(acceptedSessionId, (info: SessionEventInfo) => {
      this.handleMessage(acceptedSessionId, info);
    });

    try {
      const acceptResult: Promise<void> = this.api.accept(acceptedSessionId, collabToken);
      this.logger.info('COLLAB_ACCEPT_CALLED', '');
      acceptResult
        .then(() => {
          this.logger.info('collaboration.acceptSucceeded',
            'sessionId=' + acceptedSessionId.toString());
          this.logger.info('COLLAB_ACCEPT_SUCCEEDED', '');
        })
        .catch((error: BusinessError) => {
          this.handleAcceptFailure(error, acceptedSessionId);
        });
    } catch (error) {
      this.logger.info('COLLAB_ACCEPT_CALLED', '');
      this.handleAcceptFailure(error as BusinessError, acceptedSessionId);
    }

    return true;
  }

  async send(text: string): Promise<void> {
    if (this.sessionId < 0) {
      throw new AppError(
        'E_SESSION_NOT_READY',
        '协同会话尚未建立',
        ErrorStage.CONNECTION,
        true
      );
    }
    try {
      await this.api.send(this.sessionId, text);
      this.logger.info('collaboration.messageSent',
        'sessionId=' + this.sessionId.toString() + ' bytes=' + text.length.toString());
    } catch (error) {
      throw this.mapBusinessError(error as BusinessError);
    }
  }

  async disconnect(): Promise<void> {
    if (this.sessionId >= 0) {
      this.api.disconnect(this.sessionId);
      this.releaseSession(this.sessionId);
    }
    this.connected = false;
  }

  destroy(): void {
    if (this.destroyed) {
      return;
    }
    this.destroyed = true;
    if (this.sessionId >= 0) {
      this.releaseSession(this.sessionId);
    }
    this.connected = false;
    this.peerDevice = null;
    this.listener = null;
  }

  isConnected(): boolean {
    return this.connected;
  }

  getPeerDevice(): PeerDevice | null {
    return this.peerDevice;
  }

  private mapBusinessError(error: BusinessError): AppError {
    return new AppError(
      'E_SYSTEM_' + error.code,
      error.message,
      ErrorStage.CONNECTION,
      false,
      error.code
    );
  }

  private handleAcceptFailure(error: BusinessError, acceptedSessionId: number): void {
    const message: string = error.message ?? '';
    this.logger.error('collaboration.acceptFailed',
      'code=' + error.code.toString() + ' message=' + message);
    this.logger.error('COLLAB_ACCEPT_FAILED',
      'code=' + error.code.toString() + ' message=' + message);
    const listener = this.listener;
    this.releaseSession(acceptedSessionId);
    if (listener !== null) {
      listener.onError(this.mapBusinessError(error));
    }
  }

  private handleDisconnect(sessionId: number, info: SessionEventInfo): void {
    if (this.sessionId !== sessionId) {
      return;
    }
    this.connected = false;
    const reason: number = info.reason ?? 0;
    this.logger.info('collaboration.disconnected',
      'sessionId=' + sessionId.toString() + ' reason=' + reason.toString());
    if (this.listener !== null) {
      this.listener.onDisconnected(info.reason);
    }
  }

  private handleMessage(sessionId: number, info: SessionEventInfo): void {
    if (this.sessionId !== sessionId) {
      return;
    }
    const text: string = info.msg ?? '';
    this.logger.info('collaboration.messageReceived',
      'sessionId=' + sessionId.toString() + ' bytes=' + text.length.toString());
    if (this.listener !== null) {
      this.listener.onMessage(text);
    }
  }

  private releaseSession(sessionId: number): void {
    if (this.sessionId !== sessionId || sessionId < 0) {
      return;
    }
    this.api.offAll(sessionId);
    this.api.destroy(sessionId);
    this.sessionId = -1;
    this.connected = false;
  }

  private markConnected(sessionId: number): void {
    if (this.sessionId !== sessionId || this.connected) {
      return;
    }
    this.connected = true;
    this.logger.info('collaboration.connected', 'sessionId=' + sessionId.toString());
    if (this.listener !== null) {
      this.listener.onConnected();
    }
  }
}
