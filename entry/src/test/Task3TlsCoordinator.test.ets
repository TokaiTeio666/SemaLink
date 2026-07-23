import { describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityConnectionManager } from '@kit.DistributedServiceKit';
import { BindingTokenGenerator } from '../main/ets/communication/PeerConnectionPool';
import {
  CollaborationApi,
  SessionConnectResult,
  SessionEventInfo
} from '../main/ets/communication/control/CollaborationApi';
import { DskDataFrame } from '../main/ets/communication/control/DskDataChannel';
import {
  Task3TlsCoordinator,
  Task3TlsCoordinatorOptions
} from '../main/ets/communication/tls/Task3TlsCoordinator';
import { PeerDevice } from '../main/ets/model/AppModels';

const PEER_B: PeerDevice = { deviceId: 'remote-b', deviceName: 'B', deviceType: 'phone' };
const PEER_C: PeerDevice = { deviceId: 'remote-c', deviceName: 'C', deviceType: 'phone' };

interface BindPayload {
  deviceId: string;
  endpointVersion: number;
  sessionEpoch: string;
}

interface BindEnvelope {
  type: string;
  payload: BindPayload;
}

interface BindAckPayload {
  deviceId: string;
  endpointVersion: number;
  sessionEpoch: string;
  acceptedAtMs: number;
}

interface BindAckEnvelope {
  type: string;
  payload: BindAckPayload;
}

class FixedTokenGenerator implements BindingTokenGenerator {
  async generate(): Promise<string> { return 'fixed-bind-token'; }
}

class FakeCollaborationApi implements CollaborationApi {
  connectCalls: number = 0;
  disconnects: number[] = [];
  private nextId: number = 1;
  private readonly connectCallbacks = new Map<number, (info: SessionEventInfo) => void>();
  private readonly disconnectCallbacks = new Map<number, (info: SessionEventInfo) => void>();
  private readonly messageCallbacks = new Map<number, (info: SessionEventInfo) => void>();

  create(_service: string, _context: common.UIAbilityContext, _peer: abilityConnectionManager.PeerInfo,
    _options: abilityConnectionManager.ConnectOptions): number {
    return this.nextId++;
  }

  onConnect(sessionId: number, callback: (info: SessionEventInfo) => void): void {
    this.connectCallbacks.set(sessionId, callback);
  }

  onDisconnect(sessionId: number, callback: (info: SessionEventInfo) => void): void {
    this.disconnectCallbacks.set(sessionId, callback);
  }

  onMessage(sessionId: number, callback: (info: SessionEventInfo) => void): void {
    this.messageCallbacks.set(sessionId, callback);
  }

  offAll(sessionId: number): void {
    this.connectCallbacks.delete(sessionId);
    this.disconnectCallbacks.delete(sessionId);
    this.messageCallbacks.delete(sessionId);
  }

  connect(_sessionId: number): Promise<SessionConnectResult> {
    this.connectCalls += 1;
    const result: SessionConnectResult = { isConnected: true };
    return Promise.resolve(result);
  }

  accept(_sessionId: number, _token: string): Promise<void> { return Promise.resolve(); }

  send(sessionId: number, text: string): Promise<void> {
    const frame = JSON.parse(text) as DskDataFrame;
    if (frame.channel !== 'DATA') return Promise.resolve();
    const envelope = JSON.parse(frame.payload) as BindEnvelope;
    if (envelope.type !== 'DATA_BIND') return Promise.resolve();
    const ackEnvelope: BindAckEnvelope = { type: 'DATA_BIND_ACK', payload: {
      deviceId: envelope.payload.deviceId,
      endpointVersion: envelope.payload.endpointVersion,
      sessionEpoch: envelope.payload.sessionEpoch,
      acceptedAtMs: 1
    } };
    const ackText = JSON.stringify(ackEnvelope);
    const ack: DskDataFrame = { channel: 'DATA', version: '1.0', frameId: 'ack-' + sessionId.toString(),
      index: 0, total: 1, textLength: ackText.length, payload: ackText };
    this.messageCallbacks.get(sessionId)?.({ sessionId: sessionId, msg: JSON.stringify(ack) });
    return Promise.resolve();
  }

  disconnect(sessionId: number): void { this.disconnects.push(sessionId); }
  destroy(_sessionId: number): void {}
  emitConnect(sessionId: number): void { this.connectCallbacks.get(sessionId)?.({ sessionId: sessionId }); }
}

const acceptWant = (deviceId: string): Record<string, Object> => {
  const peerInfo: abilityConnectionManager.PeerInfo = {
    deviceId: deviceId, bundleName: 'b', moduleName: 'entry', abilityName: 'EntryAbility'
  };
  const options: abilityConnectionManager.ConnectOptions = {
    needSendData: false, parameters: { 'semalink.channel': 'DSK_DATA' }
  };
  const inner = new Object() as Record<string, Object>;
  inner['PeerInfo'] = peerInfo;
  inner['ConnectOption'] = options;
  inner['ohos.dms.collabToken'] = 'token-' + deviceId;
  const want = new Object() as Record<string, Object>;
  want['ohos.extra.param.key.supportCollaborateIndex'] = inner;
  return want;
};

function coordinator(api: FakeCollaborationApi): Task3TlsCoordinator {
  const options: Task3TlsCoordinatorOptions = {
    context: {} as common.UIAbilityContext,
    bundleName: 'b',
    collaborationApi: api,
    tokenGenerator: new FixedTokenGenerator()
  };
  return new Task3TlsCoordinator(options);
}

export default function task3TlsCoordinatorTest(): void {
  describe('Task3TlsCoordinator', () => {
    it('registersPeersWithoutDialing', 0, async () => {
      const api = new FakeCollaborationApi();
      const tls = coordinator(api);

      await tls.registerPeers([PEER_B, PEER_C]);

      expect(api.connectCalls).assertEqual(0);
      expect(tls.isReady('remote-b')).assertFalse();
      expect(tls.pool.stateOf('remote-c')).assertEqual('DISCONNECTED');
      await tls.destroy();
    });

    it('connectsAndDisconnectsPeersIndependently', 0, async () => {
      const api = new FakeCollaborationApi();
      const tls = coordinator(api);
      await tls.registerPeers([PEER_B, PEER_C]);

      await tls.connect(PEER_B);
      await tls.connect(PEER_C);
      expect(tls.isReady('remote-b')).assertTrue();
      expect(tls.isReady('remote-c')).assertTrue();

      await tls.disconnectPeer('remote-b');
      expect(tls.isReady('remote-b')).assertFalse();
      expect(tls.isReady('remote-c')).assertTrue();
      await tls.destroy();
    });

    it('passesTheLocalDeviceIdToCanonicalSessionSelection', 0, async () => {
      const api = new FakeCollaborationApi();
      const tls = coordinator(api);
      tls.setLocalDeviceId('device-a');
      await tls.registerPeers([{ deviceId: 'device-b', deviceName: 'B', deviceType: 'phone' }]);

      await tls.connect({ deviceId: 'device-b', deviceName: 'B', deviceType: 'phone' });
      expect(tls.accept(acceptWant('device-b'))).assertTrue();
      api.emitConnect(2);

      expect(tls.dsk.canonicalSessionDirection('device-b')).assertEqual('OUTBOUND');
      await tls.destroy();
    });

    it('registersAnInboundPeerBeforeBinding', 0, async () => {
      const api = new FakeCollaborationApi();
      const tls = coordinator(api);
      const observed: string[] = [];
      tls.onConnectionStateChanged((peer: PeerDevice): void => { observed.push(peer.deviceId); });

      expect(tls.accept(acceptWant('remote-b'))).assertTrue();

      expect(observed[0]).assertEqual('remote-b');
      await tls.destroy();
    });
  });
}
