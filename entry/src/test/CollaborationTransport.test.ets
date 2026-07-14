import { describe, expect, it, beforeEach } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityConnectionManager } from '@kit.DistributedServiceKit';
import { AppError, ErrorStage } from '../main/ets/common/AppError';
import { Logger } from '../main/ets/common/Logger';
import { PeerDevice } from '../main/ets/model/AppModels';
import { CollaborationApi, CollaborationTransport } from
  '../main/ets/communication/CollaborationTransport';

const PEER: PeerDevice = { deviceId: 'd1', deviceName: 'MatePad', deviceType: 'tablet' };

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

class TestPeerInfo {
  deviceId: string = '';
  bundleName: string = '';
  moduleName: string = '';
  abilityName: string = '';
}

class TestConnectOptions {
  needSendData: boolean = false;
  startOptions: number = 0;
}

class FakeCollaborationApi implements CollaborationApi {
  sessionId: number = 100;
  connectResult: SessionConnectResult = { isConnected: true, errorCode: 0, reason: '' };
  offCalls: number = 0;
  destroyCalls: number = 0;
  sentMessages: Array<string> = [];
  acceptToken: string = '';
  private connectCallback?: (info: SessionEventInfo) => void;
  private disconnectCallback?: (info: SessionEventInfo) => void;
  private messageCallback?: (info: SessionEventInfo) => void;

  create(serviceName: string, context: common.UIAbilityContext,
    deviceId: string, bundleName: string, moduleName: string, abilityName: string,
    needSendData: boolean, startOptions: number, role: string): number {
    return this.sessionId;
  }

  onConnect(sessionId: number, callback: (info: SessionEventInfo) => void): void {
    this.connectCallback = callback;
  }

  onDisconnect(sessionId: number, callback: (info: SessionEventInfo) => void): void {
    this.disconnectCallback = callback;
  }

  onMessage(sessionId: number, callback: (info: SessionEventInfo) => void): void {
    this.messageCallback = callback;
  }

  offAll(sessionId: number): void {
    this.offCalls += 3;
    this.connectCallback = undefined;
    this.disconnectCallback = undefined;
    this.messageCallback = undefined;
  }

  async connect(sessionId: number): Promise<SessionConnectResult> {
    return this.connectResult;
  }

  async accept(sessionId: number, token: string): Promise<void> {
    this.acceptToken = token;
  }

  async send(sessionId: number, text: string): Promise<void> {
    this.sentMessages.push(text);
  }

  disconnect(sessionId: number): void {
  }

  destroy(sessionId: number): void {
    this.destroyCalls += 1;
  }

  emitConnected(): void {
    if (this.connectCallback !== undefined) {
      this.connectCallback({ sessionId: this.sessionId });
    }
  }

  emitDisconnected(reason?: number): void {
    if (this.disconnectCallback !== undefined) {
      this.disconnectCallback({ sessionId: this.sessionId, reason: reason });
    }
  }

  emitMessage(text: string): void {
    if (this.messageCallback !== undefined) {
      this.messageCallback({ sessionId: this.sessionId, msg: text });
    }
  }
}

export default function collaborationTransportTest(): void {
  describe('CollaborationTransport', () => {
    let api: FakeCollaborationApi;
    let transport: CollaborationTransport;
    let logger: Logger;

    beforeEach(() => {
      api = new FakeCollaborationApi();
      logger = new Logger();
      transport = new CollaborationTransport(
        { applicationInfo: { name: 'com.example.test' } } as common.UIAbilityContext,
        'com.example.test',
        logger,
        api
      );
    });

    it('mapsRejectedConnection', 0, async () => {
      api.connectResult = { isConnected: false, errorCode: 2, reason: 'wifi off' };
      let code: string = '';
      try {
        await transport.connect(PEER);
      } catch (error) {
        code = (error as AppError).code;
      }
      expect(code).assertEqual('E_CONNECT_REJECTED');
      expect(api.offCalls).assertEqual(3);
      expect(api.destroyCalls).assertEqual(1);
    });

    it('removesListenersBeforeDestroy', 0, () => {
      let wantParam: Record<string, Object> = new Object() as Record<string, Object>;

      let peerInfo = new TestPeerInfo();
      peerInfo.deviceId = 'd1';
      peerInfo.bundleName = 'com.example.test';
      peerInfo.moduleName = 'entry';
      peerInfo.abilityName = 'EntryAbility';
      wantParam[abilityConnectionManager.CollaborationKeys.PEER_INFO] = peerInfo;

      let connectOpts = new TestConnectOptions();
      connectOpts.needSendData = false;
      connectOpts.startOptions = 0;
      wantParam[abilityConnectionManager.CollaborationKeys.CONNECT_OPTIONS] = connectOpts;

      transport.accept(wantParam);

      transport.destroy();
      transport.destroy();
      expect(api.offCalls).assertEqual(3);
      expect(api.destroyCalls).assertEqual(1);
    });
  });
}
