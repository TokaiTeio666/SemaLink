import { beforeEach, describe, expect, it } from '@ohos/hypium';
import { AppError } from '../main/ets/common/AppError';
import { SequenceIdGenerator } from '../main/ets/common/IdGenerator';
import { Scheduler } from '../main/ets/common/Scheduler';
import { QueryCoordinator } from '../main/ets/application/QueryCoordinator';
import { AvailableDeviceProvider, TrustedDeviceResolver } from
  '../main/ets/communication/TrustedDeviceResolver';
import { SessionManager } from '../main/ets/communication/SessionManager';
import { Transport, TransportListener } from '../main/ets/communication/Transport';
import { AppSnapshot, ConnectionState, DeviceRole, maskDeviceId, PeerDevice } from '../main/ets/model/AppModels';
import { ProtocolCodec } from '../main/ets/protocol/ProtocolCodec';
import { ProtocolEnvelope, QueryPayload, ResultPayload } from '../main/ets/protocol/ProtocolModels';
import { AppStateStore } from '../main/ets/state/AppStateStore';
import { MockSummaryService } from '../main/ets/task/MockSummaryService';
import { FakeScheduler } from './support/FakeScheduler';

const PEER: PeerDevice = { deviceId: 'd1', deviceName: 'MatePad', deviceType: 'tablet' };
const WANT_PARAM: Record<string, Object> = {};

class FakeProvider implements AvailableDeviceProvider {
  released: boolean = false;
  devices: Array<PeerDevice> = [];

  constructor(devices: Array<PeerDevice> = []) {
    this.devices = devices;
  }

  list(): Promise<Array<PeerDevice>> {
    return Promise.resolve(this.devices);
  }

  release(): void {
    this.released = true;
  }
}

class RecordingTransport implements Transport {
  private listener: TransportListener | null = null;
  connectedPeerId: string = '';
  sentMessages: Array<string> = [];
  disconnectCalls: number = 0;
  destroyCalls: number = 0;

  setListener(listener: TransportListener): void {
    this.listener = listener;
  }

  connect(peer: PeerDevice): Promise<void> {
    this.connectedPeerId = peer.deviceId;
    return Promise.resolve();
  }

  accept(_wantParam: Record<string, Object>): boolean {
    return true;
  }

  send(text: string): Promise<void> {
    this.sentMessages.push(text);
    return Promise.resolve();
  }

  disconnect(): Promise<void> {
    this.disconnectCalls += 1;
    return Promise.resolve();
  }

  destroy(): void {
    this.destroyCalls += 1;
  }

  isConnected(): boolean {
    return this.connectedPeerId.length > 0 && this.disconnectCalls === 0;
  }

  getPeerDevice(): PeerDevice | null {
    return null;
  }

  emitConnected(): void {
    this.listener?.onConnected();
  }

  emitMessage(text: string): void {
    this.listener?.onMessage(text);
  }

  emitDisconnected(): void {
    this.listener?.onDisconnected();
  }
}

export default function queryCoordinatorTest(): void {
  describe('QueryCoordinator', () => {
    let transport: RecordingTransport;
    let codec: ProtocolCodec;
    let scheduler: Scheduler;
    let session: SessionManager;
    let store: AppStateStore;
    let provider: FakeProvider;
    let nowMs: number;
    let coordinator: QueryCoordinator;

    beforeEach(() => {
      transport = new RecordingTransport();
      codec = new ProtocolCodec();
      scheduler = new FakeScheduler();
      session = new SessionManager(
        transport, codec, new SequenceIdGenerator(() => 1000), scheduler, 3000, 10000
      );
      store = new AppStateStore();
      provider = new FakeProvider([PEER]);
      nowMs = 1000;
      coordinator = new QueryCoordinator(
        session,
        store,
        new MockSummaryService(),
        () => new TrustedDeviceResolver(provider),
        () => nowMs
      );
    });

    it('publishesStoreUpdatesAndSupportsUnsubscribe', 0, () => {
      let notifications: number = 0;
      let latestRole: DeviceRole = DeviceRole.UNSELECTED;
      const unsubscribe: () => void = store.subscribe((snapshot: AppSnapshot) => {
        notifications += 1;
        latestRole = snapshot.role;
      });

      store.update({ role: DeviceRole.INITIATOR });
      unsubscribe();
      store.update({ role: DeviceRole.RESPONDER });

      expect(notifications).assertEqual(2);
      expect(latestRole).assertEqual(DeviceRole.INITIATOR);
    });

    it('connectsOnlyResolvedPeer', 0, async () => {
      coordinator.selectInitiator();
      await coordinator.connect();

      expect(transport.connectedPeerId).assertEqual('d1');
      expect(provider.released).assertTrue();
      expect(store.snapshot().connectionState).assertEqual(ConnectionState.CONNECTING);
    });

    it('publishesDeviceSelectionErrors', 0, async () => {
      provider = new FakeProvider([]);
      coordinator = new QueryCoordinator(
        session, store, new MockSummaryService(),
        () => new TrustedDeviceResolver(provider), () => nowMs
      );
      coordinator.selectInitiator();

      let code: string = '';
      try {
        await coordinator.connect();
      } catch (error) {
        code = (error as AppError).code;
      }

      expect(code).assertEqual('E_DEVICE_NOT_FOUND');
      expect(store.snapshot().connectionState).assertEqual(ConnectionState.ERROR);
      expect(store.snapshot().error?.code).assertEqual('E_DEVICE_NOT_FOUND');
    });

    it('rejectsMultipleResolvedPeers', 0, async () => {
      provider = new FakeProvider([
        PEER,
        { deviceId: 'd2', deviceName: 'Phone', deviceType: 'phone' }
      ]);
      coordinator = new QueryCoordinator(
        session, store, new MockSummaryService(),
        () => new TrustedDeviceResolver(provider), () => nowMs
      );
      coordinator.selectInitiator();

      let code: string = '';
      try {
        await coordinator.connect();
      } catch (error) {
        code = (error as AppError).code;
      }

      expect(code).assertEqual('E_MULTIPLE_DEVICES');
      expect(store.snapshot().connectionState).assertEqual(ConnectionState.ERROR);
    });

    it('writesInitiatorResultAndMetricsToStore', 0, async () => {
      coordinator.selectInitiator();
      await coordinator.connect();
      transport.emitConnected();

      const pending: Promise<void> = coordinator.submit('项目状态');
      const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      nowMs = 1042;
      transport.emitMessage(codec.encode(codec.createAck(
        'm2', query.sessionId, query.requestId, 1010, { acceptedAt: 1010 }
      )));
      transport.emitMessage(codec.encode(codec.createResult(
        'm3', query.sessionId, query.requestId, 1042,
        { summary: '摘要', sourceDeviceAlias: '响应端设备', processingMs: 5 }
      )));
      await pending;

      const snapshot: AppSnapshot = store.snapshot();
      expect(snapshot.summary).assertEqual('摘要');
      expect(snapshot.question).assertEqual('项目状态');
      expect(snapshot.requestId).assertEqual(query.requestId);
      expect(snapshot.roundTripMs).assertEqual(42);
      expect(snapshot.connectionState).assertEqual(ConnectionState.CONNECTED);
      expect(snapshot.bytesSent).assertLarger(0);
      expect(snapshot.bytesReceived).assertLarger(0);
    });

    it('preservesSingleRequestLimit', 0, async () => {
      coordinator.selectInitiator();
      await coordinator.connect();
      transport.emitConnected();
      const first: Promise<void> = coordinator.submit('first');
      first.catch((_error: Object) => {});

      let code: string = '';
      try {
        await coordinator.submit('second');
      } catch (error) {
        code = (error as AppError).code;
      }

      expect(code).assertEqual('E_BUSY');
      expect(store.snapshot().error?.code).assertEqual('E_BUSY');
      transport.emitDisconnected();
    });

    it('handlesIncomingQueryOnResponder', 0, async () => {
      expect(coordinator.acceptCollaboration(WANT_PARAM)).assertTrue();
      transport.emitConnected();
      const query: ProtocolEnvelope = codec.createQuery(
        'm1', 's1', 'r1', 1000, { question: '项目状态' }
      );

      await coordinator.onIncomingQuery(query);

      expect(store.snapshot().role).assertEqual(DeviceRole.RESPONDER);
      expect(transport.sentMessages.length).assertEqual(2);
      const ack: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      const result: ProtocolEnvelope = codec.decode(transport.sentMessages[1]);
      expect(ack.requestId).assertEqual('r1');
      expect((result.payload as ResultPayload).summary).assertContain('未执行真实文档检索');
      expect(store.snapshot().question).assertEqual(
        (query.payload as QueryPayload).question
      );
    });

    it('publishesDisconnectedState', 0, async () => {
      coordinator.selectInitiator();
      await coordinator.connect();
      transport.emitConnected();
      await coordinator.disconnect();

      expect(transport.disconnectCalls).assertEqual(1);
      expect(store.snapshot().connectionState).assertEqual(ConnectionState.DISCONNECTED);
    });

    it('destroysSessionOnlyOnce', 0, () => {
      coordinator.destroy();
      coordinator.destroy();

      expect(transport.destroyCalls).assertEqual(1);
    });

    it('reconnectSucceedsAfterManualDisconnect', 0, () => {
      const transport = new RecordingTransport();
      const scheduler = new FakeScheduler();
      const session = new SessionManager(
        transport, new ProtocolCodec(), new SequenceIdGenerator(() => 5000),
        scheduler, 3000, 10000
      );
      const provider = new FakeProvider();
      provider.devices = [PEER];
      const resolverFactory = () => new TrustedDeviceResolver(provider);
      const store = new AppStateStore();
      const coordinator = new QueryCoordinator(
        session, store, new MockSummaryService(), resolverFactory
      );
      coordinator.selectInitiator();
      coordinator.connect().then(() => {
        transport.emitConnected();
        expect(store.snapshot().connectionState).assertEqual(ConnectionState.CONNECTED);
        coordinator.disconnect().then(() => {
          expect(store.snapshot().connectionState).assertEqual(ConnectionState.DISCONNECTED);
          coordinator.connect().then(() => {
            transport.emitConnected();
            expect(store.snapshot().connectionState).assertEqual(ConnectionState.CONNECTED);
          });
        });
      });
    });

    it('updatesRealPeerInformation', 0, () => {
      const transport = new RecordingTransport();
      const scheduler = new FakeScheduler();
      const session = new SessionManager(
        transport, new ProtocolCodec(), new SequenceIdGenerator(() => 5000),
        scheduler, 3000, 10000
      );
      const provider = new FakeProvider();
      const testPeer: PeerDevice = { deviceId: 'dev-abc-123', deviceName: 'TestPad', deviceType: 'tablet' };
      provider.devices = [testPeer];
      const resolverFactory = () => new TrustedDeviceResolver(provider);
      const store = new AppStateStore();
      const coordinator = new QueryCoordinator(
        session, store, new MockSummaryService(), resolverFactory
      );
      coordinator.selectInitiator();
      coordinator.connect().then(() => {
        const snapshot = store.snapshot();
        expect(snapshot.peerDeviceName).assertEqual('TestPad');
        expect(snapshot.peerDeviceIdMasked).assertEqual(maskDeviceId('dev-abc-123'));
        expect(snapshot.peerDeviceIdMasked.includes('dev-abc-123')).assertFalse();
      });
    });

    it('doesNotConfusePeerWithLocalDevice', 0, () => {
      const transport = new RecordingTransport();
      const scheduler = new FakeScheduler();
      const session = new SessionManager(
        transport, new ProtocolCodec(), new SequenceIdGenerator(() => 5000),
        scheduler, 3000, 10000
      );
      const provider = new FakeProvider();
      const testPeer: PeerDevice = { deviceId: 'remote-123', deviceName: 'RemoteDevice', deviceType: 'phone' };
      provider.devices = [testPeer];
      const resolverFactory = () => new TrustedDeviceResolver(provider);
      const store = new AppStateStore();
      const coordinator = new QueryCoordinator(
        session, store, new MockSummaryService(), resolverFactory
      );
      coordinator.selectInitiator();
      coordinator.connect().then(() => {
        const snapshot = store.snapshot();
        expect(snapshot.peerDeviceName).assertEqual('RemoteDevice');
        expect(snapshot.peerDeviceName === '设备 B').assertFalse();
        expect(snapshot.peerDeviceName === '设备 A').assertFalse();
      });
    });
  });
}
