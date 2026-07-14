import { common } from '@kit.AbilityKit';
import { abilityConnectionManager } from '@kit.DistributedServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppError, ErrorStage } from '../common/AppError';
import { Logger } from '../common/Logger';
import { PeerDevice } from '../model/AppModels';
import { Transport, TransportListener } from './Transport';

const SERVICE_NAME: string = 'semalink.communication.v1';
const SERVICE_TOKEN: string = 'semalink-mvp-v1';
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

class PeerInfoData {
  deviceId: string = '';
  bundleName: string = '';
  moduleName: string = '';
  abilityName: string = '';
}

class ConnectOptionsData {
  needSendData: boolean = false;
  startOptions: number = 0;
}

export interface CollaborationApi {
  create(serviceName: string, context: common.UIAbilityContext,
    deviceId: string, bundleName: string, moduleName: string, abilityName: string,
    needSendData: boolean, startOptions: number, role: string): number;
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
    deviceId: string, bundleName: string, moduleName: string, abilityName: string,
    needSendData: boolean, startOptions: number, role: string): number {
    return abilityConnectionManager.createAbilityConnectionSession(serviceName, context, {
      deviceId: deviceId,
      bundleName: bundleName,
      moduleName: moduleName,
      abilityName: abilityName
    }, {
      needSendData: needSendData,
      startOptions: startOptions,
      parameters: role.length > 0 ? { 'semalink.role': role } : undefined
    });
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
    this.sessionId = this.api.create(SERVICE_NAME, this.context, peer.deviceId, this.bundleName,
      MODULE_NAME, ABILITY_NAME, false,
      abilityConnectionManager.StartOptionParams.START_IN_FOREGROUND, 'RESPONDER');

    this.api.onConnect(this.sessionId, (info: SessionEventInfo) => {
      this.connected = true;
      this.logger.info('collaboration.connected', 'sessionId=' + this.sessionId.toString());
      if (this.listener !== null) {
        this.listener.onConnected();
      }
    });

    this.api.onDisconnect(this.sessionId, (info: SessionEventInfo) => {
      this.connected = false;
      let r: number = 0;
      if (info.reason !== undefined) {
        r = info.reason;
      }
      this.logger.info('collaboration.disconnected',
        'sessionId=' + this.sessionId.toString() + ' reason=' + r.toString());
      if (this.listener !== null) {
        this.listener.onDisconnected(info.reason);
      }
    });

    this.api.onMessage(this.sessionId, (info: SessionEventInfo) => {
      let text: string = '';
      if (info.msg !== undefined) {
        text = info.msg;
      }
      this.logger.info('collaboration.messageReceived',
        'sessionId=' + this.sessionId.toString() + ' bytes=' + text.length.toString());
      if (this.listener !== null) {
        this.listener.onMessage(text);
      }
    });

    try {
      let result: SessionConnectResult = await this.api.connect(this.sessionId);
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
        this.api.offAll(this.sessionId);
        this.api.destroy(this.sessionId);
        this.sessionId = -1;
        throw new AppError('E_CONNECT_REJECTED',
          '连接被拒绝: ' + rs, ErrorStage.CONNECTION, true, result.errorCode);
      }
    } catch (error) {
      if (error instanceof AppError) {
        throw error;
      }
      this.api.offAll(this.sessionId);
      this.api.destroy(this.sessionId);
      this.sessionId = -1;
      throw this.mapBusinessError(error as BusinessError);
    }
  }

  accept(wantParam: Record<string, Object>): boolean {
    let rawPeer = wantParam[abilityConnectionManager.CollaborationKeys.PEER_INFO];
    let rawOptions = wantParam[abilityConnectionManager.CollaborationKeys.CONNECT_OPTIONS];
    if (rawPeer === undefined || rawOptions === undefined) {
      this.logger.error('collaboration.acceptInvalidParams', 'missing peerInfo or connectOptions');
      return false;
    }

    let peer = rawPeer as PeerInfoData;
    let deviceId: string = peer.deviceId;
    let bundleName: string = peer.bundleName;
    let moduleName: string = peer.moduleName;
    let abilityName: string = peer.abilityName;

    let opts = rawOptions as ConnectOptionsData;
    let needSendData: boolean = opts.needSendData;
    let startOptions: number = opts.startOptions;

    this.sessionId = this.api.create(SERVICE_NAME, this.context, deviceId, bundleName,
      moduleName, abilityName, needSendData, startOptions, '');

    this.api.onConnect(this.sessionId, (info: SessionEventInfo) => {
      this.connected = true;
      this.logger.info('collaboration.connected', 'sessionId=' + this.sessionId.toString());
      if (this.listener !== null) {
        this.listener.onConnected();
      }
    });

    this.api.onDisconnect(this.sessionId, (info: SessionEventInfo) => {
      this.connected = false;
      let r: number = 0;
      if (info.reason !== undefined) {
        r = info.reason;
      }
      this.logger.info('collaboration.disconnected',
        'sessionId=' + this.sessionId.toString() + ' reason=' + r.toString());
      if (this.listener !== null) {
        this.listener.onDisconnected(info.reason);
      }
    });

    this.api.onMessage(this.sessionId, (info: SessionEventInfo) => {
      let text: string = '';
      if (info.msg !== undefined) {
        text = info.msg;
      }
      this.logger.info('collaboration.messageReceived',
        'sessionId=' + this.sessionId.toString() + ' bytes=' + text.length.toString());
      if (this.listener !== null) {
        this.listener.onMessage(text);
      }
    });

    this.api.accept(this.sessionId, SERVICE_TOKEN)
      .catch((error: BusinessError) => {
        this.logger.error('collaboration.acceptFailed', 'code=' + error.code.toString());
        if (this.listener !== null) {
          this.listener.onError(this.mapBusinessError(error));
        }
      });

    return true;
  }

  async send(text: string): Promise<void> {
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
    }
    this.destroy();
  }

  destroy(): void {
    if (this.destroyed) {
      return;
    }
    this.destroyed = true;
    if (this.sessionId >= 0) {
      this.api.offAll(this.sessionId);
      this.api.destroy(this.sessionId);
      this.sessionId = -1;
    }
    this.connected = false;
    this.listener = null;
  }

  isConnected(): boolean {
    return this.connected;
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
}
