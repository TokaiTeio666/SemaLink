import { describe, expect, it } from '@ohos/hypium';
import { DataEnvelope, DataMessageType, DataPayload, EvidenceBatchPayload, TaskAckDataPayload, PeerContext } from '../main/ets/protocol/MultiDeviceProtocolModels';
import { EvidenceUnit } from '../main/ets/contracts/semantic/SemanticModels';
import { EvidenceDigest, MultiDeviceCodecOptions, MultiDeviceProtocolCodec } from '../main/ets/protocol/MultiDeviceProtocolCodec';

function envelope(type: DataMessageType, payload: DataPayload, version: string = '2.0', sequence: number = 1, peerTaskId: string = 'task-1@peer-a'): DataEnvelope {
  const peer: PeerContext = { taskId: 'task-1', peerTaskId, sessionEpoch: 'epoch-1', sequence };
  return { version: version as '2.0', type, messageId: 'message-1', sentAtMs: 1, peer, payload };
}
function ackPayload(): TaskAckDataPayload { return { taskId: 'task-1', peerTaskId: 'task-1@peer-a', round: 1, acceptedAtMs: 1 }; }
class FakeDigest implements EvidenceDigest {
  async digestEvidence(_unit: EvidenceUnit): Promise<string> { return 'expected'; }
}

export default function multiDeviceProtocolCodecTest(): void {
  describe('MultiDeviceProtocolCodec', () => {
    it('round trips a task ack envelope', 0, () => {
      const codec = new MultiDeviceProtocolCodec();
      const decoded = codec.decode(codec.encode(envelope('TASK_ACK', ackPayload())), 'epoch-1', 'peer-a');
      expect(decoded.type).assertEqual('TASK_ACK');
      expect(decoded.peer.peerTaskId).assertEqual('task-1@peer-a');
    });
    it('rejects unsupported version, sequence, and peer ownership', 0, () => {
      const codec = new MultiDeviceProtocolCodec();
      let version = ''; try { codec.encode(envelope('TASK_ACK', ackPayload(), '1.0')); } catch (e) { version = (e as Error).message; }
      let sequence = ''; try { codec.encode(envelope('TASK_ACK', ackPayload(), '2.0', 0)); } catch (e) { sequence = (e as Error).message; }
      let owner = ''; try { codec.encode(envelope('TASK_ACK', ackPayload(), '2.0', 1, 'other@peer-b')); } catch (e) { owner = (e as Error).message; }
      expect(version).assertEqual('E_DATA_PROTOCOL_INVALID');
      expect(sequence).assertEqual('E_DATA_PROTOCOL_INVALID');
      expect(owner).assertEqual('E_DATA_PROTOCOL_INVALID');
    });
    it('rejects a batch whose digest does not match evidence', 0, async () => {
      const digest: EvidenceDigest = new FakeDigest();
      const options: MultiDeviceCodecOptions = { digest };
      const codec = new MultiDeviceProtocolCodec(options);
      const payload: EvidenceBatchPayload = { taskId: 'task-1', peerTaskId: 'task-1@peer-a', round: 1, evidence: [], batchDigest: 'wrong', encodedBytes: 0 };
      let code = ''; try { await codec.validate(envelope('EVIDENCE_BATCH', payload), 'epoch-1', 'peer-a'); } catch (e) { code = (e as Error).message; }
      expect(code).assertEqual('E_DATA_PROTOCOL_INVALID');
    });
  });
}
