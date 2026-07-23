import { describe, expect, it } from '@ohos/hypium';
import {
  CrossDeviceEnvelope,
  CrossDeviceProtocolMessageType
} from '../main/ets/crossdevice/protocol/CrossDeviceProtocolModels';
import { CrossDeviceProtocolCodec } from
  '../main/ets/crossdevice/protocol/CrossDeviceProtocolCodec';
import { TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';

class QueryPayload {
  query: TaskRequest = {
    semanticContractVersion: '1.0', taskId: 'task-1',
    queryText: 'distributed knowledge', requiredConcepts: ['knowledge'],
    requiredConfidence: 0.8, coverageThreshold: 0.8, latencyBudgetMs: 1000,
    byteBudget: 4096, privacyLevel: 'PRIVATE_GROUP', acceptableLevels: ['L1']
  };
  knowledgeDomain: string = 'knowledge';
}

function throws(action: () => void): boolean {
  try {
    action();
    return false;
  } catch (_) {
    return true;
  }
}

export default function crossDeviceProtocolCodecTest(): void {
  describe('CrossDeviceProtocolCodec', () => {
    it('round trips the strict common envelope', 0, () => {
      const codec = new CrossDeviceProtocolCodec();
      const envelope = new CrossDeviceEnvelope(
        'QUERY_REQUEST' as CrossDeviceProtocolMessageType,
        'message-1',
        'request-1',
        'task-1',
        'app-instance',
        100,
        200,
        0,
        new QueryPayload()
      );
      const decoded = codec.decode(codec.encode(envelope));
      expect(decoded.messageType).assertEqual('QUERY_REQUEST');
      expect(decoded.requestId).assertEqual('request-1');
      expect(decoded.sequence).assertEqual(0);
    });

    it('rejects malformed json and missing common fields', 0, () => {
      const codec = new CrossDeviceProtocolCodec();
      expect(throws((): void => { codec.decode('{'); })).assertTrue();
      expect(throws((): void => { codec.decode('{"protocolVersion":1}'); })).assertTrue();
    });

    it('rejects query terminal responses with a missing taskId', 0, () => {
      const codec = new CrossDeviceProtocolCodec();
      const raw = '{"protocolVersion":1,"messageType":"QUERY_RESPONSE",' +
        '"messageId":"message","requestId":"request",' +
        '"senderAppInstanceId":"peer","sentAtMs":100,"deadlineAtMs":200,' +
        '"sequence":0,"payload":{"status":"OK","evidence":[],"truncated":false}}';
      expect(throws((): void => { codec.decode(raw); })).assertTrue();
    });

    it('allows an empty knowledgeDomain when routing found no domain match', 0, () => {
      const codec = new CrossDeviceProtocolCodec();
      const payload = new QueryPayload();
      payload.knowledgeDomain = '';
      const envelope = new CrossDeviceEnvelope(
        'QUERY_REQUEST', 'message', 'request', 'task-1', 'peer',
        100, 200, 0, payload
      );
      expect(throws((): void => { codec.encode(envelope); })).assertFalse();
    });
  });
}
