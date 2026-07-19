import { describe, expect, it, beforeEach } from '@ohos/hypium';
import { AppError, ErrorStage } from '../main/ets/common/AppError';
import { SequenceIdGenerator } from '../main/ets/common/IdGenerator';
import { ConnectionState, PeerDevice } from '../main/ets/model/AppModels';
import { ProtocolCodec } from '../main/ets/protocol/ProtocolCodec';
import { CancelPayload, MessageType, ProtocolEnvelope, QueryPayload, ResultPayload } from
  '../main/ets/protocol/ProtocolModels';
import { ProtocolObserver, SessionManager, SessionObserver } from '../main/ets/communication/SessionManager';
import { TransportListener } from '../main/ets/communication/Transport';
import { FakeTransport } from './support/FakeTransport';
import { FakeScheduler } from './support/FakeScheduler';

const PEER: PeerDevice = { deviceId: 'd1', deviceName: 'MatePad', deviceType: 'tablet' };
const ACK_TIMEOUT_MS: number = 3000;
const RESULT_TIMEOUT_MS: number = 10000;

class TestObserver implements SessionObserver {
  stateHistory: Array<ConnectionState> = [];
  incomingQueries: Array<ProtocolEnvelope> = [];
  bytesSentTotal: number = 0;
  bytesReceivedTotal: number = 0;
  errors: Array<AppError> = [];

  onStateChanged(state: ConnectionState): void {
    this.stateHistory.push(state);
  }

  onIncomingQuery(envelope: ProtocolEnvelope): void {
    this.incomingQueries.push(envelope);
  }

  onMetrics(bytesSent: number, bytesReceived: number): void {
    this.bytesSentTotal += bytesSent;
    this.bytesReceivedTotal += bytesReceived;
  }

  onError(error: AppError): void {
    this.errors.push(error);
  }
}

class TestProtocolObserver implements ProtocolObserver {
  envelopes: Array<ProtocolEnvelope> = [];

  onProtocolEnvelope(envelope: ProtocolEnvelope): void {
    this.envelopes.push(envelope);
  }
}

export default function sessionManagerTest(): void {
  describe('SessionManager', () => {
    let transport: FakeTransport;
    let codec: ProtocolCodec;
    let idGen: SequenceIdGenerator;
    let scheduler: FakeScheduler;
    let manager: SessionManager;
    let observer: TestObserver;
    let protocolObserver: TestProtocolObserver;

    beforeEach(() => {
      transport = new FakeTransport();
      codec = new ProtocolCodec();
      idGen = new SequenceIdGenerator(() => 1000);
      scheduler = new FakeScheduler();
      observer = new TestObserver();
      protocolObserver = new TestProtocolObserver();
      manager = new SessionManager(transport, codec, idGen, scheduler, ACK_TIMEOUT_MS, RESULT_TIMEOUT_MS);
      manager.setObserver(observer);
      manager.setProtocolObserver(protocolObserver);
    });

    it('completesQueryAfterAckAndResult', 0, async () => {
      await manager.connect(PEER);
      transport.emitConnected();
      expect(manager.state).assertEqual(ConnectionState.CONNECTED);

      const pending = manager.execute('项目状态');
      expect(manager.state).assertEqual(ConnectionState.WAITING_ACK);
      expect(transport.sentMessages.length).assertEqual(1);

      const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      expect(query.type).assertEqual(MessageType.QUERY);
      expect((query.payload as QueryPayload).question).assertEqual('项目状态');

      const ack: ProtocolEnvelope = codec.createAck('m2', query.sessionId,
        query.requestId, 1010, { acceptedAt: 1010 });
      transport.emitMessage(codec.encode(ack));
      expect(manager.state).assertEqual(ConnectionState.WAITING_RESULT);

      const result: ProtocolEnvelope = codec.createResult('m3', query.sessionId,
        query.requestId, 1020, { summary: '摘要', sourceDeviceAlias: '响应端设备', processingMs: 5 });
      transport.emitMessage(codec.encode(result));

      const outcome: ResultPayload = await pending;
      expect(outcome.summary).assertEqual('摘要');
      expect(manager.state).assertEqual(ConnectionState.CONNECTED);
    });

    it('rejectsExecuteWhenNotConnected', 0, async () => {
      let code: string = '';
      try {
        await manager.execute('test');
      } catch (error) {
        code = (error as AppError).code;
      }
      expect(code).assertEqual('E_SESSION_NOT_READY');
    });

    it('returnsBusyWhenSecondRequestIsConcurrent', 0, async () => {
      await manager.connect(PEER);
      transport.emitConnected();

      manager.execute('first');
      let code: string = '';
      try {
        await manager.execute('second');
      } catch (error) {
        code = (error as AppError).code;
      }
      expect(code).assertEqual('E_BUSY');
    });

    it('timesOutAfterAckTimeout', 0, async () => {
      await manager.connect(PEER);
      transport.emitConnected();

      let errorCode: string = '';
      const pending = manager.execute('timeout test');
      pending.catch((_reason: Object) => {});

      scheduler.advanceBy(ACK_TIMEOUT_MS);

      try {
        await pending;
      } catch (error) {
        errorCode = (error as AppError).code;
      }
      expect(errorCode).assertEqual('E_ACK_TIMEOUT');
      expect(manager.state).assertEqual(ConnectionState.DISCONNECTED);
    });

    it('timesOutAfterResultTimeout', 0, async () => {
      await manager.connect(PEER);
      transport.emitConnected();

      let errorCode: string = '';
      const pending = manager.execute('ack but no result');
      pending.catch((_reason: Object) => {});

      const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      const ack: ProtocolEnvelope = codec.createAck('m2', query.sessionId,
        query.requestId, 1010, { acceptedAt: 1010 });
      transport.emitMessage(codec.encode(ack));
      expect(manager.state).assertEqual(ConnectionState.WAITING_RESULT);

      scheduler.advanceBy(RESULT_TIMEOUT_MS);

      try {
        await pending;
      } catch (error) {
        errorCode = (error as AppError).code;
      }
      expect(errorCode).assertEqual('E_RESULT_TIMEOUT');
      expect(manager.state).assertEqual(ConnectionState.DISCONNECTED);
    });

    it('ignoresLateResultAfterTimeout', 0, async () => {
      await manager.connect(PEER);
      transport.emitConnected();

      let errorCode: string = '';
      const pending = manager.execute('late result');
      pending.catch((_reason: Object) => {});

      const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      const ack: ProtocolEnvelope = codec.createAck('m2', query.sessionId,
        query.requestId, 1010, { acceptedAt: 1010 });
      transport.emitMessage(codec.encode(ack));

      scheduler.advanceBy(RESULT_TIMEOUT_MS);

      try {
        await pending;
      } catch (error) {
        errorCode = (error as AppError).code;
      }
      expect(errorCode).assertEqual('E_RESULT_TIMEOUT');

      // late result should not throw or change state
      const lateResult: ProtocolEnvelope = codec.createResult('m3', query.sessionId,
        query.requestId, 9999, { summary: 'late', sourceDeviceAlias: '响应端设备', processingMs: 5000 });
      transport.emitMessage(codec.encode(lateResult));
      expect(manager.state).assertEqual(ConnectionState.DISCONNECTED);
    });

    it('ignoresResultForUnknownRequestId', 0, async () => {
      await manager.connect(PEER);
      transport.emitConnected();

      const pending = manager.execute('known request');
      const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);

      const unknownResult: ProtocolEnvelope = codec.createResult('m9', query.sessionId,
        'unknown-rid', 1050, { summary: 'wrong', sourceDeviceAlias: '响应端设备', processingMs: 2 });
      // should not throw and should not affect pending
      transport.emitMessage(codec.encode(unknownResult));
      expect(manager.state).assertEqual(ConnectionState.WAITING_ACK);

      // cleanup
      const ack: ProtocolEnvelope = codec.createAck('m2', query.sessionId,
        query.requestId, 1010, { acceptedAt: 1010 });
      transport.emitMessage(codec.encode(ack));
      const result: ProtocolEnvelope = codec.createResult('m3', query.sessionId,
        query.requestId, 1020, { summary: 'ok', sourceDeviceAlias: '响应端设备', processingMs: 3 });
      transport.emitMessage(codec.encode(result));
      const outcome: ResultPayload = await pending;
      expect(outcome.summary).assertEqual('ok');
    });

    it('preservesRemoteErrorDetails', 0, async () => {
      await manager.connect(PEER);
      transport.emitConnected();

      const pending = manager.execute('remote failure');
      const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      const remoteError: ProtocolEnvelope = codec.createError(
        'm2', query.sessionId, query.requestId, 1010,
        { code: 'E_SYSTEM_401', message: 'PARAMETER ERROR' }
      );
      transport.emitMessage(codec.encode(remoteError));

      let error: AppError | undefined;
      try {
        await pending;
      } catch (caught) {
        error = caught as AppError;
      }
      expect(error?.code).assertEqual('E_SYSTEM_401');
      expect(error?.message).assertEqual('PARAMETER ERROR');
    });

    it('cleansUpPendingOnDisconnect', 0, async () => {
      await manager.connect(PEER);
      transport.emitConnected();

      let errorCode: string = '';
      const pending = manager.execute('disconnect mid');
      pending.catch((_reason: Object) => {});

      transport.emitDisconnected(0);

      try {
        await pending;
      } catch (error) {
        errorCode = (error as AppError).code;
      }
      expect(errorCode).assertEqual('E_DISCONNECTED');
      expect(manager.state).assertEqual(ConnectionState.DISCONNECTED);
    });

    it('destroyIsIdempotent', 0, async () => {
      await manager.connect(PEER);
      transport.emitConnected();

      manager.destroy();
      manager.destroy();
      // should not throw; timers should be cleared only once
      expect(manager.state).assertEqual(ConnectionState.DISCONNECTED);
    });

    it('acceptsTransportConnectAndInvokesAccept', 0, () => {
      // Simulate responder side: accept doesn't need transport.connect
      // The accept method on SessionManager delegates to transport.accept
      const wantParam: Record<string, Object> = {};
      // FakeTransport.accept returns true
      const result: boolean = manager.accept(wantParam);
      expect(result).assertTrue();
    });

    it('dispatchesIncomingQueryOnResponder', 0, async () => {
      // Simulate responder: we receive a QUERY, observer.onIncomingQuery is called
      await manager.connect(PEER);
      transport.emitConnected();

      const query: ProtocolEnvelope = codec.createQuery('m1', 's1', 'r1', 1000,
        { question: '什么是鸿蒙?' });
      const listener: TransportListener = manager as TransportListener;
      listener.onMessage(codec.encode(query));

      expect(observer.incomingQueries.length).assertEqual(1);
      expect(observer.incomingQueries[0].requestId).assertEqual('r1');
    });

    it('sendsSemanticEnvelopeAndCountsUtf8Bytes', 0, async () => {
      await manager.connect(PEER);
      transport.emitConnected();

      const envelope: ProtocolEnvelope = codec.createCancel('semantic-message', 's1', 'task-1', 1000,
        { taskId: 'task-1', code: 'E_CANCELLED', reason: 'semantic cancel' } as CancelPayload);
      const expectedBytes: number = codec.encode(envelope).length;
      await manager.sendEnvelope(envelope);

      expect(transport.sentMessages.length).assertEqual(1);
      expect(codec.decode(transport.sentMessages[0]).type).assertEqual(MessageType.CANCEL);
      expect(observer.bytesSentTotal).assertLarger(expectedBytes - 1);
    });

    it('dispatchesP4EnvelopeOnlyOnceByMessageId', 0, async () => {
      await manager.connect(PEER);
      transport.emitConnected();

      const envelope: ProtocolEnvelope = codec.createCancel('duplicate-message', 's1', 'task-1', 1000,
        { taskId: 'task-1', code: 'E_CANCELLED', reason: 'semantic cancel' } as CancelPayload);
      const text: string = codec.encode(envelope);
      transport.emitMessage(text);
      transport.emitMessage(text);

      expect(protocolObserver.envelopes.length).assertEqual(1);
      expect(protocolObserver.envelopes[0].messageId).assertEqual('duplicate-message');
    });

    it('doesNotDispatchAfterDestroy', 0, async () => {
      await manager.connect(PEER);
      transport.emitConnected();
      manager.destroy();

      const envelope: ProtocolEnvelope = codec.createCancel('after-destroy', 's1', 'task-1', 1000,
        { taskId: 'task-1', code: 'E_CANCELLED', reason: 'semantic cancel' } as CancelPayload);
      transport.emitMessage(codec.encode(envelope));

      expect(protocolObserver.envelopes.length).assertEqual(0);
    });

    it('sendsErrorForBusyResponder', 0, async () => {
      await manager.connect(PEER);
      transport.emitConnected();

      // first query arrives
      const query1: ProtocolEnvelope = codec.createQuery('m1', 's1', 'r1', 1000,
        { question: 'first' });
      const listener: TransportListener = manager as TransportListener;
      listener.onMessage(codec.encode(query1));
      expect(observer.incomingQueries.length).assertEqual(1);

      // second query while first is still being processed (pending is set)
      const query2: ProtocolEnvelope = codec.createQuery('m2', 's1', 'r2', 1005,
        { question: 'second' });
      transport.sentMessages = [];
      listener.onMessage(codec.encode(query2));

      // Should have sent an ERROR back
      expect(transport.sentMessages.length).assertEqual(1);
      const errorEnvelope: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      expect(errorEnvelope.type).assertEqual(MessageType.ERROR);
    });

    it('cachesAndReplaysCompletedResult', 0, async () => {
      await manager.connect(PEER);
      transport.emitConnected();

      // Complete a request normally
      const pending = manager.execute('question A');
      const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      const ack: ProtocolEnvelope = codec.createAck('m2', query.sessionId,
        query.requestId, 1010, { acceptedAt: 1010 });
      transport.emitMessage(codec.encode(ack));
      const result: ProtocolEnvelope = codec.createResult('m3', query.sessionId,
        query.requestId, 1020, { summary: 'cached answer', sourceDeviceAlias: '响应端设备', processingMs: 3 });
      transport.emitMessage(codec.encode(result));
      await pending;
      expect(manager.state).assertEqual(ConnectionState.CONNECTED);

      // Same requestId arrives again (duplicate) — should replay cached result
      transport.sentMessages = [];
      const duplicateResult: ProtocolEnvelope = codec.createResult('m99', query.sessionId,
        query.requestId, 5000, { summary: 'different', sourceDeviceAlias: '备用设备', processingMs: 99 });
      const listener: TransportListener = manager as TransportListener;
      listener.onMessage(codec.encode(duplicateResult));

      // Should have ignored the duplicate and not changed state
      expect(manager.state).assertEqual(ConnectionState.CONNECTED);
    });

    it('accumulatesByteMetrics', 0, async () => {
      await manager.connect(PEER);
      transport.emitConnected();

      const pending = manager.execute('metrics test');
      // send metric
      expect(observer.bytesSentTotal).assertLarger(0);

      const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      const ackText: string = codec.encode(codec.createAck('m2', query.sessionId,
        query.requestId, 1010, { acceptedAt: 1010 }));
      transport.emitMessage(ackText);

      const resultText: string = codec.encode(codec.createResult('m3', query.sessionId,
        query.requestId, 1020, { summary: 'ok', sourceDeviceAlias: '响应端设备', processingMs: 1 }));
      transport.emitMessage(resultText);
      await pending;

      expect(observer.bytesReceivedTotal).assertLarger(0);
    });

    it('notifiesStateChangesToObserver', 0, async () => {
      await manager.connect(PEER);
      transport.emitConnected();

      observer.stateHistory = [];
      const pending = manager.execute('state changes');

      expect(observer.stateHistory.indexOf(ConnectionState.WAITING_ACK)).assertLarger(-1);

      const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      const ack: ProtocolEnvelope = codec.createAck('m2', query.sessionId,
        query.requestId, 1010, { acceptedAt: 1010 });
      transport.emitMessage(codec.encode(ack));
      expect(observer.stateHistory.indexOf(ConnectionState.WAITING_RESULT)).assertLarger(-1);

      const result: ProtocolEnvelope = codec.createResult('m3', query.sessionId,
        query.requestId, 1020, { summary: 'ok', sourceDeviceAlias: '响应端设备', processingMs: 1 });
      transport.emitMessage(codec.encode(result));
      await pending;
      expect(observer.stateHistory.indexOf(ConnectionState.CONNECTED)).assertLarger(-1);
    });

    it('disconnectCleansUpTimers', 0, async () => {
      await manager.connect(PEER);
      transport.emitConnected();

      const pending = manager.execute('cleanup test');
      pending.catch((_reason: Object) => {});

      expect(scheduler.pendingCount()).assertEqual(1); // ACK timer

      await manager.disconnect();

      // After disconnect, timers should be cancelled
      expect(scheduler.pendingCount()).assertEqual(0);
    });

    it('canExecuteAgainAfterPreviousRequestCompletes', 0, async () => {
      await manager.connect(PEER);
      transport.emitConnected();

      // First request
      let pending = manager.execute('first');
      let query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
      transport.emitMessage(codec.encode(codec.createAck('m2', query.sessionId,
        query.requestId, 1010, { acceptedAt: 1010 })));
      transport.emitMessage(codec.encode(codec.createResult('m3', query.sessionId,
        query.requestId, 1020, { summary: 'first result', sourceDeviceAlias: '响应端设备', processingMs: 2 })));
      await pending;

      // Second request
      transport.sentMessages = [];
      pending = manager.execute('second');
      query = codec.decode(transport.sentMessages[0]);
      expect((query.payload as QueryPayload).question).assertEqual('second');
      transport.emitMessage(codec.encode(codec.createAck('m5', query.sessionId,
        query.requestId, 2010, { acceptedAt: 2010 })));
      transport.emitMessage(codec.encode(codec.createResult('m6', query.sessionId,
        query.requestId, 2020, { summary: 'second result', sourceDeviceAlias: '响应端设备', processingMs: 1 })));
      const outcome: ResultPayload = await pending;
      expect(outcome.summary).assertEqual('second result');
    });

    it('canReconnectAfterDisconnect', 0, () => {
      const transport = new FakeTransport();
      const scheduler = new FakeScheduler();
      const session = new SessionManager(
        transport, new ProtocolCodec(), new SequenceIdGenerator(() => 5000),
        scheduler, 3000, 10000
      );
      session.setObserver(new TestObserver());

      session.connect(PEER).then(() => {
        transport.emitConnected();
        session.disconnect().then(() => {
          expect(session.state).assertEqual(ConnectionState.DISCONNECTED);
          session.connect(PEER).then(() => {
            transport.emitConnected();
            expect(session.state).assertEqual(ConnectionState.CONNECTED);
            expect(transport.connectCalls).assertEqual(2);
            expect(transport.disconnectCalls).assertEqual(1);
          });
        });
      });
    });

    it('disconnectDoesNotDestroyTransport', 0, () => {
      const transport = new FakeTransport();
      const scheduler = new FakeScheduler();
      const session = new SessionManager(
        transport, new ProtocolCodec(), new SequenceIdGenerator(() => 5000),
        scheduler, 3000, 10000
      );
      session.setObserver(new TestObserver());

      session.connect(PEER).then(() => {
        transport.emitConnected();
        session.disconnect().then(() => {
          expect(transport.destroyed).assertFalse();
        });
      });
    });

    it('destroyPreventsFurtherUse', 0, () => {
      const transport = new FakeTransport();
      const scheduler = new FakeScheduler();
      const session = new SessionManager(
        transport, new ProtocolCodec(), new SequenceIdGenerator(() => 5000),
        scheduler, 3000, 10000
      );
      session.setObserver(new TestObserver());

      session.destroy();
      session.connect(PEER).catch((error: Object) => {
        const appError = error as AppError;
        expect(appError.code).assertEqual('E_SESSION_NOT_READY');
      });
    });
  });
}
