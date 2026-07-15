import { describe, expect, it, beforeEach } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityConnectionManager } from '@kit.DistributedServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppError, ErrorStage } from '../main/ets/common/AppError';
import { Logger } from '../main/ets/common/Logger';
import { PeerDevice } from '../main/ets/model/AppModels';
import { CollaborationApi, CollaborationTransport } from
  '../main/ets/communication/CollaborationTransport';
import { TransportListener } from '../main/ets/communication/Transport';

const PEER: PeerDevice = { deviceId: 'd1', deviceName: 'MatePad', deviceType: 'tablet' };
const SERVICE_NAME: string = 'semalink.communication.v1';
const COLLAB_PARAM_KEY: string = 'ohos.extra.param.key.supportCollaborateIndex';
const COLLAB_PEER_KEY: string = 'PeerInfo';
const COLLAB_OPTION_KEY: string = 'ConnectOption';
const COLLAB_TOKEN_KEY: string = 'ohos.dms.collabToken';

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

class TestBusinessError extends Error implements BusinessError {
  code: number;

  constructor(code: number, message: string) {
    super(message);
    this.name = 'TestBusinessError';
    this.code = code;
  }
}

class TestListener implements TransportListener {
  connectedCalls: number = 0;
  errorCalls: number = 0;

  onConnected(): void {
    this.connectedCalls += 1;
  }

  onMessage(text: string): void {
  }

  onDisconnected(reason?: number): void {
  }

  onError(error: AppError): void {
    this.errorCalls += 1;
  }
}

class FakeCollaborationApi implements CollaborationApi {
  sessionId: number = 100;
  connectResult: SessionConnectResult = { isConnected: true, errorCode: 0, reason: '' };
  offAllCalls: number = 0;
  destroyCalls: number = 0;
  createCalls: number = 0;
  sentMessages: Array<string> = [];
  acceptToken: string = '';
  createdServiceName: string = '';
  createdPeerInfo: abilityConnectionManager.PeerInfo | null = null;
  createdConnectOptions: abilityConnectionManager.ConnectOptions | null = null;
  acceptError: TestBusinessError | null = null;
  createError: TestBusinessError | null = null;
  private connectCallback?: (info: SessionEventInfo) => void;
  private disconnectCallback?: (info: SessionEventInfo) => void;
  private messageCallback?: (info: SessionEventInfo) => void;

  create(serviceName: string, context: common.UIAbilityContext,
    peerInfo: abilityConnectionManager.PeerInfo,
    connectOptions: abilityConnectionManager.ConnectOptions): number {
    if (this.createError !== null) {
      throw this.createError;
    }
    this.createCalls += 1;
    this.createdServiceName = serviceName;
    this.createdPeerInfo = peerInfo;
    this.createdConnectOptions = connectOptions;
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
    this.offAllCalls += 1;
    this.connectCallback = undefined;
    this.disconnectCallback = undefined;
    this.messageCallback = undefined;
  }

  async connect(sessionId: number): Promise<SessionConnectResult> {
    return this.connectResult;
  }

  async accept(sessionId: number, token: string): Promise<void> {
    this.acceptToken = token;
    if (this.acceptError !== null) {
      throw this.acceptError;
    }
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

function createPeerInfo(): abilityConnectionManager.PeerInfo {
  return {
    deviceId: 'd1',
    bundleName: 'com.example.test',
    moduleName: 'entry',
    abilityName: 'EntryAbility',
    serviceName: SERVICE_NAME
  };
}

function createConnectOptions(): abilityConnectionManager.ConnectOptions {
  return {
    needSendData: false,
    startOptions: abilityConnectionManager.StartOptionParams.START_IN_FOREGROUND,
    parameters: {
      'semalink.role': 'RESPONDER',
      'system.trace': 'preserve-me'
    }
  };
}

function createCollaborateWant(peerInfo: abilityConnectionManager.PeerInfo,
  connectOptions: abilityConnectionManager.ConnectOptions,
  token: string | null): Record<string, Object> {
  const collabParam = new Object() as Record<string, Object>;
  collabParam[COLLAB_PEER_KEY] = peerInfo;
  collabParam[COLLAB_OPTION_KEY] = connectOptions;
  if (token !== null) {
    collabParam[COLLAB_TOKEN_KEY] = token;
  }
  const wantParam = new Object() as Record<string, Object>;
  wantParam[COLLAB_PARAM_KEY] = collabParam;
  return wantParam;
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
      expect(api.offAllCalls).assertEqual(1);
      expect(api.destroyCalls).assertEqual(1);
    });

    it('notifiesInitiatorWhenConnectPromiseSucceeds', 0, async () => {
      const listener = new TestListener();
      transport.setListener(listener);
      await transport.connect(PEER);
      expect(listener.connectedCalls).assertEqual(1);
      expect(transport.isConnected()).assertTrue();
      api.emitConnected();
      expect(listener.connectedCalls).assertEqual(1);
    });

    it('releasesPreviousSessionBeforeReconnect', 0, async () => {
      await transport.connect(PEER);
      await transport.connect(PEER);
      expect(api.offAllCalls).assertEqual(1);
      expect(api.destroyCalls).assertEqual(1);
      expect(transport.isConnected()).assertTrue();
    });

    it('parsesNestedCollaborateParameters', 0, () => {
      const accepted: boolean = transport.accept(
        createCollaborateWant(createPeerInfo(), createConnectOptions(), 'system-token')
      );
      expect(accepted).assertTrue();
      expect(api.createCalls).assertEqual(1);
    });

    it('doesNotUseLegacyRootParameters', 0, () => {
      const wantParam = new Object() as Record<string, Object>;
      wantParam[COLLAB_PEER_KEY] = createPeerInfo();
      wantParam[COLLAB_OPTION_KEY] = createConnectOptions();
      wantParam[COLLAB_TOKEN_KEY] = 'root-token';
      expect(transport.accept(wantParam)).assertFalse();
      expect(api.createCalls).assertEqual(0);
    });

    it('doesNotUseSdkEnumKeyNamesForInnerParameters', 0, () => {
      const collabParam = new Object() as Record<string, Object>;
      collabParam[abilityConnectionManager.CollaborationKeys.PEER_INFO] = createPeerInfo();
      collabParam[abilityConnectionManager.CollaborationKeys.CONNECT_OPTIONS] = createConnectOptions();
      collabParam[COLLAB_TOKEN_KEY] = 'token-with-legacy-keys';
      const wantParam = new Object() as Record<string, Object>;
      wantParam[COLLAB_PARAM_KEY] = collabParam;
      expect(transport.accept(wantParam)).assertFalse();
      expect(api.createCalls).assertEqual(0);
    });

    it('rejectsMissingInnerParameters', 0, () => {
      const wantParam = new Object() as Record<string, Object>;
      expect(transport.accept(wantParam)).assertFalse();
      expect(api.createCalls).assertEqual(0);
    });

    it('rejectsMissingCollaborationToken', 0, () => {
      const wantParam = createCollaborateWant(createPeerInfo(), createConnectOptions(), null);
      expect(transport.accept(wantParam)).assertFalse();
      expect(api.createCalls).assertEqual(0);
    });

    it('passesOriginalPeerInfoToCreate', 0, () => {
      const peerInfo = createPeerInfo();
      transport.accept(createCollaborateWant(peerInfo, createConnectOptions(), 'system-token'));
      expect(api.createdPeerInfo === peerInfo).assertTrue();
      expect(api.createdServiceName).assertEqual(SERVICE_NAME);
    });

    it('passesOriginalConnectOptionsIncludingParametersToCreate', 0, () => {
      const connectOptions = createConnectOptions();
      transport.accept(createCollaborateWant(createPeerInfo(), connectOptions, 'system-token'));
      expect(api.createdConnectOptions === connectOptions).assertTrue();
      expect(api.createdConnectOptions!.parameters!['system.trace']).assertEqual('preserve-me');
    });

    it('acceptsWithSystemToken', 0, () => {
      transport.accept(createCollaborateWant(createPeerInfo(), createConnectOptions(), 'dms-token-24'));
      expect(api.acceptToken).assertEqual('dms-token-24');
    });

    it('cleansUpOnceWhenAcceptFails', 0, async () => {
      const listener = new TestListener();
      transport.setListener(listener);
      api.acceptError = new TestBusinessError(16000050, 'accept denied');
      expect(transport.accept(
        createCollaborateWant(createPeerInfo(), createConnectOptions(), 'system-token')
      )).assertTrue();
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 0));
      expect(api.offAllCalls).assertEqual(1);
      expect(api.destroyCalls).assertEqual(1);
      expect(listener.errorCalls).assertEqual(1);
      transport.destroy();
      expect(api.offAllCalls).assertEqual(1);
      expect(api.destroyCalls).assertEqual(1);
    });

    it('returnsFalseWhenSessionCreationFailsSynchronously', 0, () => {
      api.createError = new TestBusinessError(401, 'bad peer info');
      expect(transport.accept(
        createCollaborateWant(createPeerInfo(), createConnectOptions(), 'system-token')
      )).assertFalse();
      expect(api.offAllCalls).assertEqual(0);
      expect(api.destroyCalls).assertEqual(0);
    });

    it('destroysSessionIdempotently', 0, () => {
      transport.accept(
        createCollaborateWant(createPeerInfo(), createConnectOptions(), 'system-token')
      );
      transport.destroy();
      transport.destroy();
      expect(api.offAllCalls).assertEqual(1);
      expect(api.destroyCalls).assertEqual(1);
    });

    it('disconnectDoesNotPermanentlyDisposeTransport', 0, () => {
      const api = new FakeCollaborationApi();
      api.connectResult = { isConnected: true };
      const transport = new CollaborationTransport(
        { applicationInfo: { name: 'com.example.test' } } as common.UIAbilityContext,
        'com.example.test', new Logger(), api);
      transport.setListener(new TestListener());
      transport.connect(PEER).then(() => {
        api.emitConnected();
        expect(transport.isConnected()).assertTrue();
        transport.disconnect().then(() => {
          expect(transport.isConnected()).assertFalse();
        });
      });
    });

    it('canConnectAgainAfterDisconnect', 0, () => {
      const api = new FakeCollaborationApi();
      api.connectResult = { isConnected: true };
      const transport = new CollaborationTransport(
        { applicationInfo: { name: 'com.example.test' } } as common.UIAbilityContext,
        'com.example.test', new Logger(), api);
      transport.setListener(new TestListener());
      transport.connect(PEER).then(() => {
        api.emitConnected();
        transport.disconnect().then(() => {
          expect(api.destroyCalls).assertEqual(1);
          transport.connect(PEER).then(() => {
            api.emitConnected();
            expect(transport.isConnected()).assertTrue();
            expect(api.createCalls).assertEqual(2);
          });
        });
      });
    });

    it('connectAfterDestroyIsRejected', 0, () => {
      const api = new FakeCollaborationApi();
      api.connectResult = { isConnected: true };
      const transport = new CollaborationTransport(
        { applicationInfo: { name: 'com.example.test' } } as common.UIAbilityContext,
        'com.example.test', new Logger(), api);
      transport.setListener(new TestListener());
      transport.destroy();
      transport.connect(PEER).catch((error: Object) => {
        const appError = error as AppError;
        expect(appError.code).assertEqual('E_TRANSPORT_DESTROYED');
      });
    });
  });
}
