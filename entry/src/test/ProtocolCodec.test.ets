import { describe, expect, it } from '@ohos/hypium';
import { ProtocolCodec } from '../main/ets/protocol/ProtocolCodec';
import { MessageType, ProtocolEnvelope, QueryPayload, ResultPayload, ErrorPayload, QueryAckPayload, MAX_QUESTION_CHARS, MAX_SUMMARY_CHARS, MAX_MESSAGE_BYTES } from '../main/ets/protocol/ProtocolModels';
import { AppError } from '../main/ets/common/AppError';

export default function protocolCodecTest(): void {
  describe('ProtocolCodec', () => {
    const codec: ProtocolCodec = new ProtocolCodec();

    it('roundTripsQuery', 0, () => {
      const qPayload: QueryPayload = { question: '测试问题' };
      const envelope: ProtocolEnvelope = {
        version: '1.0', type: MessageType.QUERY, messageId: 'm1', sessionId: 's1',
        requestId: 'r1', sentAt: 1000, payload: qPayload
      };
      const decoded: ProtocolEnvelope = codec.decode(codec.encode(envelope));
      expect(decoded.requestId).assertEqual('r1');
      expect((decoded.payload as QueryPayload).question).assertEqual('测试问题');
    });

    it('rejectsMalformedJson', 0, () => {
      let code: string = '';
      try { codec.decode('{bad'); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('rejectsOversizedQuestion', 0, () => {
      const payload: QueryPayload = { question: 'x'.repeat(MAX_QUESTION_CHARS + 1) };
      let code: string = '';
      try { codec.createQuery('m1', 's1', 'r1', 1000, payload); }
      catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_QUERY_INVALID');
    });

    it('rejectsUnknownVersion', 0, () => {
      const text: string = '{"version":"9.9","type":"QUERY","messageId":"m1","sessionId":"s1","requestId":"r1","sentAt":1000,"payload":{"question":"test"}}';
      let code: string = '';
      try { codec.decode(text); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('rejectsUnknownMessageType', 0, () => {
      const text: string = '{"version":"1.0","type":"UNKNOWN","messageId":"m1","sessionId":"s1","requestId":"r1","sentAt":1000,"payload":{}}';
      let code: string = '';
      try { codec.decode(text); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('rejectsMissingField', 0, () => {
      const text: string = '{"version":"1.0","type":"QUERY","messageId":"m1","sessionId":"s1","requestId":"r1"}';
      let code: string = '';
      try { codec.decode(text); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('rejectsEmptyQuestion', 0, () => {
      let code: string = '';
      const emptyQueryPayload: QueryPayload = { question: '' };
      try { codec.createQuery('m1', 's1', 'r1', 1000, emptyQueryPayload); }
      catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_QUERY_INVALID');
    });

    it('acceptsMaxLengthSummary', 0, () => {
      const summary: string = 'x'.repeat(MAX_SUMMARY_CHARS);
      const resultPayload: ResultPayload = {
        summary: summary, sourceDeviceAlias: 'B', processingMs: 5
      };
      const envelope: ProtocolEnvelope = codec.createResult('m1', 's1', 'r1', 1000, resultPayload);
      const decoded: ProtocolEnvelope = codec.decode(codec.encode(envelope));
      const decodedPayload: ResultPayload = decoded.payload as ResultPayload;
      expect(decodedPayload.summary.length).assertEqual(MAX_SUMMARY_CHARS);
    });

    it('rejectsOversizedSummary', 0, () => {
      const summary: string = 'x'.repeat(MAX_SUMMARY_CHARS + 1);
      let code: string = '';
      const oversizeResultPayload: ResultPayload = {
        summary: summary, sourceDeviceAlias: 'B', processingMs: 5
      };
      try {
        codec.createResult('m1', 's1', 'r1', 1000, oversizeResultPayload);
      } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_QUERY_INVALID');
    });

    it('rejectsOversizedEncodedMessage', 0, () => {
      const bigValue: string = 'x'.repeat(MAX_MESSAGE_BYTES + 100);
      const bigText: string = '{"version":"1.0","type":"QUERY","messageId":"m1","sessionId":"s1","requestId":"r1","sentAt":1000,"payload":{"question":"' + bigValue + '"}}';
      let code: string = '';
      try { codec.decode(bigText); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('roundTripsAck', 0, () => {
      const ackPayload: QueryAckPayload = { acceptedAt: 1010 };
      const envelope: ProtocolEnvelope = codec.createAck('m2', 's1', 'r1', 1010, ackPayload);
      expect(envelope.type).assertEqual(MessageType.QUERY_ACK);
      const decoded: ProtocolEnvelope = codec.decode(codec.encode(envelope));
      expect((decoded.payload as QueryAckPayload).acceptedAt).assertEqual(1010);
    });

    it('roundTripsResult', 0, () => {
      const resultPayload: ResultPayload = {
        summary: '摘要内容', sourceDeviceAlias: 'B', processingMs: 5
      };
      const envelope: ProtocolEnvelope = codec.createResult('m3', 's1', 'r1', 1020, resultPayload);
      const decoded: ProtocolEnvelope = codec.decode(codec.encode(envelope));
      const payload: ResultPayload = decoded.payload as ResultPayload;
      expect(payload.summary).assertEqual('摘要内容');
      expect(payload.sourceDeviceAlias).assertEqual('B');
      expect(payload.processingMs).assertEqual(5);
    });

    it('roundTripsError', 0, () => {
      const errorPayload: ErrorPayload = {
        code: 'E_BUSY', message: '设备忙碌'
      };
      const envelope: ProtocolEnvelope = codec.createError('m4', 's1', 'r1', 1030, errorPayload);
      const decoded: ProtocolEnvelope = codec.decode(codec.encode(envelope));
      const payload: ErrorPayload = decoded.payload as ErrorPayload;
      expect(payload.code).assertEqual('E_BUSY');
      expect(payload.message).assertEqual('设备忙碌');
    });

    it('rejectsNonObjectPayload', 0, () => {
      const text: string = '{"version":"1.0","type":"QUERY","messageId":"m1","sessionId":"s1","requestId":"r1","sentAt":1000,"payload":"not-an-object"}';
      let code: string = '';
      try { codec.decode(text); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_PROTOCOL_INVALID');
    });

    it('rejectsTrimsWhitespaceQuestion', 0, () => {
      let code: string = '';
      const wsPayload: QueryPayload = { question: '   ' };
      try { codec.createQuery('m1', 's1', 'r1', 1000, wsPayload); }
      catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_QUERY_INVALID');
    });
  });
}
