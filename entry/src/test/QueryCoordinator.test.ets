import { beforeEach, describe, expect, it } from '@ohos/hypium';
import { AppError } from '../main/ets/common/AppError';
import { SequenceIdGenerator } from '../main/ets/common/IdGenerator';
import { Scheduler } from '../main/ets/common/Scheduler';
import { QueryCoordinator } from '../main/ets/application/QueryCoordinator';
import {
  CollaborationRecord,
  CollaborationRecordStatus
} from '../main/ets/collaboration/CollaborationModels';
import { AvailableDeviceProvider, TrustedDeviceResolver } from
  '../main/ets/communication/TrustedDeviceResolver';
import { SessionManager } from '../main/ets/communication/SessionManager';
import { Transport, TransportListener } from '../main/ets/communication/Transport';
import { AppSnapshot, ConnectionState, DeviceRole, maskDeviceId, PeerDevice } from '../main/ets/model/AppModels';
import { ProtocolCodec } from '../main/ets/protocol/ProtocolCodec';
import {
  MAX_KNOWLEDGE_PAYLOAD_BYTES, ProtocolEnvelope, QueryPayload, ResultPayload
} from '../main/ets/protocol/ProtocolModels';
import { AppStateStore } from '../main/ets/state/AppStateStore';
import { FakeScheduler } from './support/FakeScheduler';
import { LocalKnowledgeGateway } from '../main/ets/contracts/knowledge/LocalKnowledgeGateway';
import {
  KnowledgeProfile,
  LocalKnowledgeQuery,
  LocalKnowledgeResult
} from '../main/ets/contracts/knowledge/KnowledgeModels';
import { L2KnowledgePayload } from '../main/ets/contracts/knowledge/KnowledgePayloadSchemas';

const PEER: PeerDevice = { deviceId: 'd1', deviceName: 'MatePad', deviceType: 'tablet' };
const WANT_PARAM: Record<string, Object> = {};

class FakeKnowledgeGateway implements LocalKnowledgeGateway {
  lastRequest: LocalKnowledgeQuery | undefined;

  query(request: LocalKnowledgeQuery): Promise<LocalKnowledgeResult> {
    this.lastRequest = request;
    const payload: L2KnowledgePayload = {
      schemaVersion: '1.0',
      level: 'L2',
      items: [{
        evidenceId: 'ev-1', documentId: 'doc-1', chunkId: 'chunk-1', title: '项目资料',
        snippet: '项目状态与计划', relevance: 0.9, truncated: false
      }]
    };
    const result: LocalKnowledgeResult = {
      contractVersion: '1.0', requestId: request.requestId, level: 'L2', itemCount: 1,
      payloadJson: JSON.stringify(payload), truncated: false, retrievalMs: 2,
      indexVersion: 'index-test', generatedAt: 1000
    };
    return Promise.resolve(result);
  }

  getKnowledgeProfile(): Promise<KnowledgeProfile> {
    const profile: KnowledgeProfile = {
      contractVersion: '1.0', profileVersion: 'profile-test', indexState: 'READY',
      knowledgeDomains: [], documentCount: 1, chunkCount: 1, modalities: ['text'],
      retrievalModes: ['keyword'], supportedLevels: ['L1', 'L2'], indexVersion: 'index-test',
      embeddingModelVersion: '', updatedAt: 1000
    };
    return Promise.resolve(profile);
  }
}

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

class FailingKnowledgeGateway implements LocalKnowledgeGateway {
  query(request: LocalKnowledgeQuery): Promise<LocalKnowledgeResult> {
    return Promise.reject<LocalKnowledgeResult>(new Error('知识库检索失败'));
  }

  getKnowledgeProfile(): Promise<KnowledgeProfile> {
    const profile: KnowledgeProfile = {
      contractVersion: '1.0', profileVersion: 'profile-test', indexState: 'READY',
      knowledgeDomains: [], documentCount: 1, chunkCount: 1, modalities: ['text'],
      retrievalModes: ['keyword'], supportedLevels: ['L1', 'L2'], indexVersion: 'index-test',
      embeddingModelVersion: '', updatedAt: 1000
    };
    return Promise.resolve(profile);
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
    let knowledgeGateway: FakeKnowledgeGateway;
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
      knowledgeGateway = new FakeKnowledgeGateway();
      coordinator = new QueryCoordinator(
        session,
        store,
        knowledgeGateway,
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
        session, store, new FakeKnowledgeGateway(),
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
        session, store, new FakeKnowledgeGateway(),
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

    it('mapsRemoteKnowledgeResultForDisplay', 0, async () => {
      coordinator.selectInitiator();
      await coordinator.connect();
      transport.emitConnected();

      const pending: Promise<void> = coordinator.submit('项目状态');
      const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      const knowledgeResult: LocalKnowledgeResult = await new FakeKnowledgeGateway().query({
        contractVersion: '1.0', requestId: query.requestId, queryText: '项目状态', topK: 5,
        requestedLevel: 'L2', maxPayloadBytes: 8192
      });
      transport.emitMessage(codec.encode(codec.createAck(
        'm2', query.sessionId, query.requestId, 1010, { acceptedAt: 1010 }
      )));
      transport.emitMessage(codec.encode(codec.createResult(
        'm3', query.sessionId, query.requestId, 1020,
        {
          summary: '命中 1 条', sourceDeviceAlias: '响应端设备', processingMs: 2,
          resultType: 'KNOWLEDGE', knowledgeResult: knowledgeResult
        }
      )));
      await pending;

      expect(store.snapshot().knowledgeQueryStatus).assertEqual('SUCCESS');
      expect(store.snapshot().knowledgeItems.length).assertEqual(1);
      expect(store.snapshot().knowledgeItems[0].title).assertEqual('项目资料');
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
      expect((result.payload as ResultPayload).resultType).assertEqual('KNOWLEDGE');
      expect((result.payload as ResultPayload).knowledgeResult?.itemCount).assertEqual(1);
      expect(knowledgeGateway.lastRequest?.maxPayloadBytes).assertEqual(MAX_KNOWLEDGE_PAYLOAD_BYTES);
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
        session, store, new FakeKnowledgeGateway(), resolverFactory
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
        session, store, new FakeKnowledgeGateway(), resolverFactory
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
        session, store, new FakeKnowledgeGateway(), resolverFactory
      );
      coordinator.selectInitiator();
      coordinator.connect().then(() => {
        const snapshot = store.snapshot();
        expect(snapshot.peerDeviceName).assertEqual('RemoteDevice');
        expect(snapshot.peerDeviceName === '设备 B').assertFalse();
        expect(snapshot.peerDeviceName === '设备 A').assertFalse();
      });
    });

    it('createsSendingRecordOnInitiatorSubmit', 0, async () => {
      coordinator.selectInitiator();
      await coordinator.connect();
      transport.emitConnected();

      const pending: Promise<void> = coordinator.submit('项目状态');
      const snapshot: AppSnapshot = store.snapshot();
      expect(snapshot.collaborationRecords.length).assertEqual(1);
      const record: CollaborationRecord = snapshot.collaborationRecords[0];
      expect(record.status).assertEqual(CollaborationRecordStatus.SENDING);
      expect(record.question).assertEqual('项目状态');
      expect(record.sourceDeviceName).assertEqual('本机');
      expect(record.targetDeviceName).assertEqual('MatePad');
      expect(record.id).assertEqual(snapshot.requestId);
      expect(record.createdAt).assertEqual(1000);
      expect(snapshot.selectedCollaborationRecordId).assertEqual(record.id);

      const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      transport.emitMessage(codec.encode(codec.createAck(
        'm2', query.sessionId, query.requestId, 1010, { acceptedAt: 1010 }
      )));
      transport.emitMessage(codec.encode(codec.createResult(
        'm3', query.sessionId, query.requestId, 1042,
        { summary: '摘要', sourceDeviceAlias: '响应端设备', processingMs: 5 }
      )));
      await pending;
    });

    it('updatesRecordToSyncedOnSuccess', 0, async () => {
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

      const records: Array<CollaborationRecord> = store.snapshot().collaborationRecords;
      expect(records.length).assertEqual(1);
      expect(records[0].status).assertEqual(CollaborationRecordStatus.SYNCED);
      expect(records[0].summary).assertEqual('摘要');
      expect(records[0].evidenceCount).assertEqual(0);
      expect(records[0].question).assertEqual('项目状态');
      expect(records[0].errorMessage).assertEqual('');
    });

    it('updatesRecordWithKnowledgeEvidenceCount', 0, async () => {
      coordinator.selectInitiator();
      await coordinator.connect();
      transport.emitConnected();

      const pending: Promise<void> = coordinator.submit('项目状态');
      const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      const knowledgeResult: LocalKnowledgeResult = await new FakeKnowledgeGateway().query({
        contractVersion: '1.0', requestId: query.requestId, queryText: '项目状态', topK: 5,
        requestedLevel: 'L2', maxPayloadBytes: 8192
      });
      transport.emitMessage(codec.encode(codec.createAck(
        'm2', query.sessionId, query.requestId, 1010, { acceptedAt: 1010 }
      )));
      transport.emitMessage(codec.encode(codec.createResult(
        'm3', query.sessionId, query.requestId, 1020,
        {
          summary: '命中 1 条', sourceDeviceAlias: '响应端设备', processingMs: 2,
          resultType: 'KNOWLEDGE', knowledgeResult: knowledgeResult
        }
      )));
      await pending;

      const records: Array<CollaborationRecord> = store.snapshot().collaborationRecords;
      expect(records[0].status).assertEqual(CollaborationRecordStatus.SYNCED);
      expect(records[0].evidenceCount).assertEqual(1);
      expect(records[0].summary).assertEqual('命中 1 条');
    });

    it('prepareFollowUpRestoresQuestionWithoutSending', 0, async () => {
      coordinator.selectInitiator();
      await coordinator.connect();
      transport.emitConnected();

      const pending: Promise<void> = coordinator.submit('原始问题');
      const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      transport.emitMessage(codec.encode(codec.createAck(
        'm2', query.sessionId, query.requestId, 1010, { acceptedAt: 1010 }
      )));
      transport.emitMessage(codec.encode(codec.createResult(
        'm3', query.sessionId, query.requestId, 1020,
        { summary: '原始摘要', sourceDeviceAlias: '响应端设备', processingMs: 5 }
      )));
      await pending;

      store.update({ question: '其他问题', summary: '其他摘要' });
      const sentBeforeFollowUp: number = transport.sentMessages.length;
      const recordId: string = store.snapshot().collaborationRecords[0].id;

      const result: boolean = coordinator.prepareFollowUp(recordId);
      expect(result).assertTrue();
      expect(store.snapshot().question).assertEqual('原始问题');
      expect(store.snapshot().summary).assertEqual('');
      expect(transport.sentMessages.length).assertEqual(sentBeforeFollowUp);
    });

    it('prepareFollowUpReturnsFalseForMissingId', 0, async () => {
      coordinator.selectInitiator();
      await coordinator.connect();
      transport.emitConnected();

      const pending: Promise<void> = coordinator.submit('原始问题');
      const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      transport.emitMessage(codec.encode(codec.createAck(
        'm2', query.sessionId, query.requestId, 1010, { acceptedAt: 1010 }
      )));
      transport.emitMessage(codec.encode(codec.createResult(
        'm3', query.sessionId, query.requestId, 1020,
        { summary: '原始摘要', sourceDeviceAlias: '响应端设备', processingMs: 5 }
      )));
      await pending;

      const questionBefore: string = store.snapshot().question;
      const summaryBefore: string = store.snapshot().summary;
      const selectedBefore: string = store.snapshot().selectedCollaborationRecordId;

      const result: boolean = coordinator.prepareFollowUp('missing-id');
      expect(result).assertFalse();
      expect(store.snapshot().question).assertEqual(questionBefore);
      expect(store.snapshot().summary).assertEqual(summaryBefore);
      expect(store.snapshot().selectedCollaborationRecordId).assertEqual(selectedBefore);
    });

    it('selectCollaborationRecordUpdatesSelection', 0, async () => {
      coordinator.selectInitiator();
      await coordinator.connect();
      transport.emitConnected();

      const pending: Promise<void> = coordinator.submit('项目状态');
      const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      transport.emitMessage(codec.encode(codec.createAck(
        'm2', query.sessionId, query.requestId, 1010, { acceptedAt: 1010 }
      )));
      transport.emitMessage(codec.encode(codec.createResult(
        'm3', query.sessionId, query.requestId, 1020,
        { summary: '摘要', sourceDeviceAlias: '响应端设备', processingMs: 5 }
      )));
      await pending;

      store.update({ selectedCollaborationRecordId: '' });
      const recordId: string = store.snapshot().collaborationRecords[0].id;

      const result: boolean = coordinator.selectCollaborationRecord(recordId);
      expect(result).assertTrue();
      expect(store.snapshot().selectedCollaborationRecordId).assertEqual(recordId);
    });

    it('selectCollaborationRecordReturnsFalseForMissingId', 0, async () => {
      coordinator.selectInitiator();
      await coordinator.connect();
      transport.emitConnected();

      const pending: Promise<void> = coordinator.submit('项目状态');
      const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      transport.emitMessage(codec.encode(codec.createAck(
        'm2', query.sessionId, query.requestId, 1010, { acceptedAt: 1010 }
      )));
      transport.emitMessage(codec.encode(codec.createResult(
        'm3', query.sessionId, query.requestId, 1020,
        { summary: '摘要', sourceDeviceAlias: '响应端设备', processingMs: 5 }
      )));
      await pending;

      const selectedBefore: string = store.snapshot().selectedCollaborationRecordId;
      const result: boolean = coordinator.selectCollaborationRecord('missing-id');
      expect(result).assertFalse();
      expect(store.snapshot().selectedCollaborationRecordId).assertEqual(selectedBefore);
    });

    it('mapsAckTimeoutToTimeoutStatus', 0, async () => {
      coordinator.selectInitiator();
      await coordinator.connect();
      transport.emitConnected();

      const pending: Promise<void> = coordinator.submit('ACK超时测试');
      (scheduler as FakeScheduler).advanceBy(3000);

      let code: string = '';
      try {
        await pending;
      } catch (error) {
        code = (error as AppError).code;
      }
      expect(code).assertEqual('E_ACK_TIMEOUT');

      const records: Array<CollaborationRecord> = store.snapshot().collaborationRecords;
      expect(records.length).assertEqual(1);
      expect(records[0].status).assertEqual(CollaborationRecordStatus.TIMEOUT);
      expect(records[0].question).assertEqual('ACK超时测试');
      expect(records[0].errorMessage.length).assertLarger(0);
    });

    it('mapsResultTimeoutToTimeoutStatus', 0, async () => {
      coordinator.selectInitiator();
      await coordinator.connect();
      transport.emitConnected();

      const pending: Promise<void> = coordinator.submit('结果超时测试');
      const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      transport.emitMessage(codec.encode(codec.createAck(
        'm2', query.sessionId, query.requestId, 1010, { acceptedAt: 1010 }
      )));
      (scheduler as FakeScheduler).advanceBy(10000);

      let code: string = '';
      try {
        await pending;
      } catch (error) {
        code = (error as AppError).code;
      }
      expect(code).assertEqual('E_RESULT_TIMEOUT');

      const records: Array<CollaborationRecord> = store.snapshot().collaborationRecords;
      expect(records.length).assertEqual(1);
      expect(records[0].status).assertEqual(CollaborationRecordStatus.TIMEOUT);
      expect(records[0].question).assertEqual('结果超时测试');
      expect(records[0].errorMessage.length).assertLarger(0);
    });

    it('mapsDisconnectedToOfflineStatus', 0, async () => {
      coordinator.selectInitiator();
      await coordinator.connect();
      transport.emitConnected();

      const pending: Promise<void> = coordinator.submit('断连测试');
      transport.emitDisconnected();

      let code: string = '';
      try {
        await pending;
      } catch (error) {
        code = (error as AppError).code;
      }
      expect(code).assertEqual('E_DISCONNECTED');

      const records: Array<CollaborationRecord> = store.snapshot().collaborationRecords;
      expect(records.length).assertEqual(1);
      expect(records[0].status).assertEqual(CollaborationRecordStatus.OFFLINE);
      expect(records[0].question).assertEqual('断连测试');
      expect(records[0].errorMessage.length).assertLarger(0);
    });

    it('mapsRemoteErrorToFailedStatus', 0, async () => {
      coordinator.selectInitiator();
      await coordinator.connect();
      transport.emitConnected();

      const pending: Promise<void> = coordinator.submit('远端错误测试');
      const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      const remoteError: ProtocolEnvelope = codec.createError(
        'm2', query.sessionId, query.requestId, 1010,
        { code: 'E_REMOTE_FAILURE', message: '远端处理失败' }
      );
      transport.emitMessage(codec.encode(remoteError));

      let code: string = '';
      try {
        await pending;
      } catch (error) {
        code = (error as AppError).code;
      }
      expect(code).assertEqual('E_REMOTE_FAILURE');

      const records: Array<CollaborationRecord> = store.snapshot().collaborationRecords;
      expect(records.length).assertEqual(1);
      expect(records[0].status).assertEqual(CollaborationRecordStatus.FAILED);
      expect(records[0].question).assertEqual('远端错误测试');
      expect(records[0].errorMessage).assertEqual('远端处理失败');
    });

    it('createsSendingRecordOnResponderIncomingQuery', 0, async () => {
      expect(coordinator.acceptCollaboration(WANT_PARAM)).assertTrue();
      transport.emitConnected();
      const query: ProtocolEnvelope = codec.createQuery(
        'm1', 's1', 'r1', 1000, { question: '项目状态' }
      );

      const pending: Promise<void> = coordinator.onIncomingQuery(query);
      const records: Array<CollaborationRecord> = store.snapshot().collaborationRecords;
      expect(records.length).assertEqual(1);
      expect(records[0].status).assertEqual(CollaborationRecordStatus.SENDING);
      expect(records[0].question).assertEqual('项目状态');
      expect(records[0].sourceDeviceName).assertEqual('远端设备');
      expect(records[0].targetDeviceName).assertEqual('本机');
      expect(records[0].id).assertEqual('r1');
      expect(store.snapshot().selectedCollaborationRecordId).assertEqual('r1');
      await pending;
    });

    it('updatesResponderRecordToSyncedOnSuccess', 0, async () => {
      expect(coordinator.acceptCollaboration(WANT_PARAM)).assertTrue();
      transport.emitConnected();
      const query: ProtocolEnvelope = codec.createQuery(
        'm1', 's1', 'r1', 1000, { question: '项目状态' }
      );

      await coordinator.onIncomingQuery(query);

      const records: Array<CollaborationRecord> = store.snapshot().collaborationRecords;
      expect(records.length).assertEqual(1);
      expect(records[0].status).assertEqual(CollaborationRecordStatus.SYNCED);
      expect(records[0].evidenceCount).assertEqual(1);
      expect(records[0].summary).assertEqual('命中 1 条，检索耗时 2 ms');
      expect(records[0].question).assertEqual('项目状态');
    });

    it('updatesResponderRecordToFailedOnError', 0, async () => {
      const failingGateway: FailingKnowledgeGateway = new FailingKnowledgeGateway();
      const failingCoordinator: QueryCoordinator = new QueryCoordinator(
        session, store, failingGateway,
        () => new TrustedDeviceResolver(provider), () => nowMs
      );
      expect(failingCoordinator.acceptCollaboration(WANT_PARAM)).assertTrue();
      transport.emitConnected();
      const query: ProtocolEnvelope = codec.createQuery(
        'm1', 's1', 'r1', 1000, { question: '失败查询' }
      );

      await failingCoordinator.onIncomingQuery(query);

      const records: Array<CollaborationRecord> = store.snapshot().collaborationRecords;
      expect(records.length).assertEqual(1);
      expect(records[0].status).assertEqual(CollaborationRecordStatus.FAILED);
      expect(records[0].question).assertEqual('失败查询');
      expect(records[0].errorMessage.length).assertLarger(0);
    });
  });
}
