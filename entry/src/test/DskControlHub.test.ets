import { describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityConnectionManager } from '@kit.DistributedServiceKit';
import { PeerDevice } from '../main/ets/model/AppModels';
import { Logger } from '../main/ets/common/Logger';
import { AppError } from '../main/ets/common/AppError';
import { CollaborationApi, SessionEventInfo, SessionConnectResult } from '../main/ets/communication/control/CollaborationApi';
import { ControlCodec } from '../main/ets/communication/control/ControlCodec';
import { ControlEnvelope } from '../main/ets/communication/control/ControlModels';
import { DskControlHub, DskControlHubListener } from '../main/ets/communication/control/DskControlHub';

class FakeApi implements CollaborationApi {
  next: number = 1; connectCallbacks: Map<number, (i: SessionEventInfo) => void> = new Map();
  disconnectCallbacks: Map<number, (i: SessionEventInfo) => void> = new Map();
  messageCallbacks: Map<number, (i: SessionEventInfo) => void> = new Map();
  peers: Map<number, string> = new Map(); disconnects: number[] = []; sent: string[] = [];
  create(_s: string, _c: common.UIAbilityContext, _p: abilityConnectionManager.PeerInfo, _o: abilityConnectionManager.ConnectOptions): number { return this.next++; }
  onConnect(id: number, cb: (i: SessionEventInfo) => void): void { this.connectCallbacks.set(id, cb); }
  onDisconnect(id: number, cb: (i: SessionEventInfo) => void): void { this.disconnectCallbacks.set(id, cb); }
  onMessage(id: number, cb: (i: SessionEventInfo) => void): void { this.messageCallbacks.set(id, cb); }
  offAll(_id: number): void {}
  connect(_id: number): Promise<SessionConnectResult> { const result: SessionConnectResult = { isConnected: true }; return Promise.resolve(result); }
  accept(_id: number, _t: string): Promise<void> { return Promise.resolve(); }
  send(_id: number, text: string): Promise<void> { this.sent.push(text); return Promise.resolve(); }
  disconnect(id: number): void { this.disconnects.push(id); }
  destroy(_id: number): void {}
  emitDisconnect(id: number, reason: number): void { this.disconnectCallbacks.get(id)?.({ sessionId: id, reason: reason }); }
  emitMessage(id: number, text: string): void { this.messageCallbacks.get(id)?.({ sessionId: id, msg: text }); }
  emitConnect(id: number): void { this.connectCallbacks.get(id)?.({ sessionId: id }); }
}
const peer = (id: string): PeerDevice => ({ deviceId: id, deviceName: id, deviceType: 'phone' });
const close = (id: string): ControlEnvelope => ({ version: '1.0', type: 'CONTROL_CLOSE', messageId: id, deviceId: id, sentAtMs: Date.now(), payload: { reason: 'done' } });
const acceptWant = (id: string): Record<string, Object> => {
  const peerInfo: abilityConnectionManager.PeerInfo = {
    deviceId: id, bundleName: 'b', moduleName: 'entry', abilityName: 'EntryAbility'
  };
  const options: abilityConnectionManager.ConnectOptions = { needSendData: false, parameters: { 'semalink.channel': 'DSK_DATA' } };
  const collabParam = new Object() as Record<string, Object>;
  collabParam['PeerInfo'] = peerInfo;
  collabParam['ConnectOption'] = options;
  collabParam['ohos.dms.collabToken'] = 'token-' + id;
  const wantParam = new Object() as Record<string, Object>;
  wantParam['ohos.extra.param.key.supportCollaborateIndex'] = collabParam;
  return wantParam;
};

const acceptWantWithApi24InnerKeys = (id: string): Record<string, Object> => {
  const peerInfo: abilityConnectionManager.PeerInfo = {
    deviceId: id, bundleName: 'b', moduleName: 'entry', abilityName: 'EntryAbility'
  };
  const options: abilityConnectionManager.ConnectOptions = { needSendData: false, parameters: { 'semalink.channel': 'DSK_DATA' } };
  const collabParam = new Object() as Record<string, Object>;
  collabParam[abilityConnectionManager.CollaborationKeys.PEER_INFO] = peerInfo;
  collabParam[abilityConnectionManager.CollaborationKeys.CONNECT_OPTIONS] = options;
  collabParam['ohos.collaboration.key.token'] = 'token-' + id;
  const wantParam = new Object() as Record<string, Object>;
  wantParam['ohos.extra.param.key.supportCollaborateIndex'] = collabParam;
  return wantParam;
};

class TestListener implements DskControlHubListener {
  private readonly onMessageCallback: (id: string) => void;
  private readonly onClosedCallback: (id: string) => void;

  constructor(onMessage: (id: string) => void = (_id: string): void => {},
    onClosed: (id: string) => void = (_id: string): void => {}) {
    this.onMessageCallback = onMessage;
    this.onClosedCallback = onClosed;
  }

  onControlReady(_id: string): void {}
  onControlMessage(id: string, _envelope: ControlEnvelope): void { this.onMessageCallback(id); }
  onControlClosed(id: string, _error?: AppError): void { this.onClosedCallback(id); }
}
export default function dskControlHubTest(): void {
  describe('DskControlHub', () => {
    it('keeps outbound sessions isolated', 0, async () => { const api = new FakeApi(); const hub = new DskControlHub({} as common.UIAbilityContext, 'b', new Logger(), api); await hub.connect(peer('remote-b')); await hub.connect(peer('remote-c')); expect(hub.stateOf('remote-b')).assertEqual('READY'); await hub.disconnect('remote-b'); expect(hub.stateOf('remote-c')).assertEqual('READY'); await hub.send('remote-c', close('c')); expect(api.sent.length).assertEqual(1); });
    it('keeps inbound sessions isolated', 0, () => {
      const api = new FakeApi();
      const hub = new DskControlHub({} as common.UIAbilityContext, 'b', new Logger(), api);

      expect(hub.accept(acceptWant('remote-b'))).assertTrue();
      expect(hub.accept(acceptWant('remote-c'))).assertTrue();
      expect(hub.deviceIds().length).assertEqual(2);
      expect(hub.stateOf('remote-b')).assertEqual('CONNECTING');
      expect(hub.stateOf('remote-c')).assertEqual('CONNECTING');
    });
    it('acceptsApi24KeysInsideLegacyCollaborationContainer', 0, () => {
      const api = new FakeApi();
      const hub = new DskControlHub({} as common.UIAbilityContext, 'b', new Logger(), api);
      expect(hub.accept(acceptWantWithApi24InnerKeys('remote-api24'))).assertTrue();
      expect(hub.deviceIds().length).assertEqual(1);
    });
    it('waits for an inbound connect callback before sending', 0, async () => {
      const api = new FakeApi();
      const hub = new DskControlHub({} as common.UIAbilityContext, 'b', new Logger(), api);
      expect(hub.accept(acceptWant('remote-b'))).assertTrue();
      const sendPromise = hub.send('remote-b', close('delayed'));
      setTimeout(() => api.emitConnect(1), 50);
      await sendPromise;
      expect(api.sent.length).assertEqual(1);
    });
    it('isolatesDisconnectAndSendByDevice', 0, async () => {
      const api = new FakeApi();
      const closed: string[] = [];
      const hub = new DskControlHub({} as common.UIAbilityContext, 'b', new Logger(), api,
        new TestListener((_id: string): void => {}, (id: string): void => { closed.push(id); }));

      await hub.connect(peer('remote-b'));
      await hub.connect(peer('remote-c'));
      api.emitDisconnect(1, 1001);

      expect(hub.stateOf('remote-b')).assertEqual('FAILED');
      expect(hub.stateOf('remote-c')).assertEqual('READY');
      expect(closed[0]).assertEqual('remote-b');
      await hub.send('remote-c', close('close-c'));
      expect(api.sent.length).assertEqual(1);
    });
    it('dispatchesDuplicateControlMessageOnce', 0, () => {
      const api = new FakeApi();
      const messages: string[] = [];
      const hub = new DskControlHub({} as common.UIAbilityContext, 'b', new Logger(), api,
        new TestListener((id: string): void => { messages.push(id); }));
      const envelope: ControlEnvelope = close('same-message');

      hub.connect(peer('remote-b'));
      api.emitMessage(1, new ControlCodec().encode(envelope));
      api.emitMessage(1, new ControlCodec().encode(envelope));

      expect(messages.length).assertEqual(1);
    });
    it('rejectsOversizedControlEnvelopeWithStableCode', 0, () => {
      const codec = new ControlCodec();
      let code = '';
      try {
        codec.encode({ version: '1.0', type: 'CONTROL_CLOSE', messageId: 'x', deviceId: 'd', sentAtMs: 1, payload: { reason: 'x'.repeat(2000) } });
      } catch (e) {
        code = (e as AppError).code;
      }
      expect(code).assertEqual('E_CONTROL_FRAME_TOO_LARGE');
    });
  });
}
