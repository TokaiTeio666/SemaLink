import { describe, expect, it } from '@ohos/hypium';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import { SemanticKnowledgeProvider } from '../main/ets/contracts/semantic/SemanticKnowledgeProvider';
import { KnowledgeProfile } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { PeerTaskResponder, PeerTaskResponderOptions, ResponderMessage } from '../main/ets/communication/PeerTaskResponder';
import { EvidenceDigest } from '../main/ets/protocol/MultiDeviceProtocolCodec';
import { CancelDataPayload, DataEnvelope, DataMessageType, DataPayload, EvidenceCompletePayload, PeerContext, TaskDataPayload, TsfDataPayload } from '../main/ets/protocol/MultiDeviceProtocolModels';

const task: TaskRequest = { semanticContractVersion: '1.0', taskId: 'task-1', queryText: 'query', requiredConcepts: ['concept'], requiredConfidence: 0.8, coverageThreshold: 0.8, latencyBudgetMs: 1000, byteBudget: 1000, privacyLevel: 'PRIVATE_GROUP', acceptableLevels: ['L1', 'L2'] };
const evidence: EvidenceUnit = { semanticContractVersion: '1.0', evidenceId: 'e1', evidenceGroupId: 'g1', sourceDeviceId: 'peer-a', sourceDocId: 'doc-1', level: 'L1', title: 'title', summary: 'summary', relevance: 0.9, coveredConcepts: ['concept'], estimatedCoverageGain: 0.9, byteCost: 100, privacyLevel: 'PRIVATE_GROUP', privacyCost: 0, energyCost: 0, hash: 'hash', canEscalateTo: ['L1', 'L2'] };
const evidenceL2: EvidenceUnit = { semanticContractVersion: '1.0', evidenceId: 'e2', evidenceGroupId: 'g2', sourceDeviceId: 'peer-a', sourceDocId: 'doc-1', level: 'L2', title: 'detail', summary: 'detail', relevance: 0.8, coveredConcepts: ['concept'], estimatedCoverageGain: 0.8, byteCost: 100, privacyLevel: 'PRIVATE_GROUP', privacyCost: 0, energyCost: 0, hash: 'hash-2', canEscalateTo: ['L2'] };
class FakeProvider implements SemanticKnowledgeProvider {
  searches: number = 0;
  async getProfile(): Promise<KnowledgeProfile> { throw new Error('not used'); }
  async searchEvidence(_task: TaskRequest): Promise<EvidenceUnit[]> { this.searches += 1; return [evidence, evidenceL2]; }
}
class OversizedProvider implements SemanticKnowledgeProvider {
  private readonly oversized: EvidenceUnit;
  constructor(unit: EvidenceUnit) { this.oversized = unit; }
  async getProfile(): Promise<KnowledgeProfile> { throw new Error('not used'); }
  async searchEvidence(_task: TaskRequest): Promise<EvidenceUnit[]> { return [this.oversized]; }
}
class FakeDigest implements EvidenceDigest {
  async digestEvidence(_unit: EvidenceUnit): Promise<string> { return 'hash'; }
}
function envelope(type: DataMessageType, payload: DataPayload, sequence: number = 1, sessionEpoch: string = 'epoch-1'): DataEnvelope {
  const peer: PeerContext = { taskId: 'task-1', peerTaskId: 'task-1@peer-a', sessionEpoch: 'epoch-1', sequence };
  peer.sessionEpoch = sessionEpoch;
  return { version: '2.0', type, messageId: type + '-' + sequence.toString(), sentAtMs: 1, peer, payload };
}
function taskPayload(): TaskDataPayload { return { task }; }

export default function peerTaskResponderTest(): void {
  describe('PeerTaskResponder', () => {
    it('acks once, sends L1 batch and complete, then only sends L2 after need more', 0, async () => {
      const sent: ResponderMessage[] = []; const provider = new FakeProvider(); const digest: EvidenceDigest = new FakeDigest();
      const send = async (_deviceId: string, message: ResponderMessage): Promise<void> => { sent.push(message); };
      const options: PeerTaskResponderOptions = { send, provider, digest, sessionEpoch: 'epoch-1' };
      const responder = new PeerTaskResponder(options);
      await responder.onEnvelope('peer-a', envelope('TASK', taskPayload()));
      await responder.onEnvelope('peer-a', envelope('TASK', taskPayload(), 2));
      expect(provider.searches).assertEqual(1); expect(sent.length).assertEqual(4);
      expect(sent[0].envelope.type).assertEqual('TASK_ACK'); expect(sent[1].envelope.type).assertEqual('EVIDENCE_BATCH'); expect(sent[2].envelope.type).assertEqual('EVIDENCE_COMPLETE');
      const tsf: TsfDataPayload = { taskId: 'task-1', peerTaskId: 'task-1@peer-a', round: 1, feedback: 'NEED_MORE' };
      await responder.onEnvelope('peer-a', envelope('TSF', tsf, 3));
      expect(sent.length).assertEqual(6); expect(sent[4].envelope.type).assertEqual('EVIDENCE_BATCH'); expect(sent[5].envelope.type).assertEqual('EVIDENCE_COMPLETE');
    });
    it('replays the cached task ack for a duplicate task without querying again', 0, async () => {
      const sent: ResponderMessage[] = []; const provider = new FakeProvider(); const digest: EvidenceDigest = new FakeDigest();
      const send = async (_deviceId: string, message: ResponderMessage): Promise<void> => { sent.push(message); };
      const responder = new PeerTaskResponder({ send, provider, digest, sessionEpoch: 'epoch-1' });
      await responder.onEnvelope('peer-a', envelope('TASK', taskPayload(), 1));
      const firstAck = sent[0].envelope.messageId;
      await responder.onEnvelope('peer-a', envelope('TASK', taskPayload(), 9));
      expect(provider.searches).assertEqual(1);
      expect(sent.length).assertEqual(4);
      expect(sent[3].envelope.type).assertEqual('TASK_ACK');
      expect(sent[3].envelope.messageId).assertEqual(firstAck);
    });
    it('truncates an oversized evidence batch below the protocol limit', 0, async () => {
      const sent: ResponderMessage[] = [];
      const oversized: EvidenceUnit = { semanticContractVersion: evidence.semanticContractVersion, evidenceId: evidence.evidenceId,
        evidenceGroupId: evidence.evidenceGroupId, sourceDeviceId: evidence.sourceDeviceId, sourceDocId: evidence.sourceDocId,
        level: evidence.level, title: evidence.title, summary: 'x'.repeat(70000), relevance: evidence.relevance,
        coveredConcepts: evidence.coveredConcepts, estimatedCoverageGain: evidence.estimatedCoverageGain, byteCost: 70000,
        privacyLevel: evidence.privacyLevel, privacyCost: evidence.privacyCost, energyCost: evidence.energyCost,
        hash: evidence.hash, canEscalateTo: evidence.canEscalateTo };
      const oversizedTask: TaskRequest = { semanticContractVersion: task.semanticContractVersion, taskId: task.taskId,
        queryText: task.queryText, requiredConcepts: task.requiredConcepts, requiredConfidence: task.requiredConfidence,
        coverageThreshold: task.coverageThreshold, latencyBudgetMs: task.latencyBudgetMs, byteBudget: 100000,
        privacyLevel: task.privacyLevel, acceptableLevels: task.acceptableLevels };
      const provider: SemanticKnowledgeProvider = new OversizedProvider(oversized);
      const send = async (_deviceId: string, message: ResponderMessage): Promise<void> => { sent.push(message); };
      const responder = new PeerTaskResponder({ send, provider, digest: new FakeDigest(), sessionEpoch: 'epoch-1' });
      await responder.onEnvelope('peer-a', envelope('TASK', { task: oversizedTask }));
      expect(sent.length).assertEqual(2);
      expect(sent[sent.length - 1].envelope.type).assertEqual('EVIDENCE_COMPLETE');
      expect((sent[sent.length - 1].envelope.payload as EvidenceCompletePayload).truncatedByBudget).assertEqual(true);
    });
    it('ignores a canceled task', 0, async () => {
      const sent: ResponderMessage[] = []; const provider = new FakeProvider(); const digest: EvidenceDigest = new FakeDigest();
      const send = async (_deviceId: string, message: ResponderMessage): Promise<void> => { sent.push(message); };
      const options: PeerTaskResponderOptions = { send, provider, digest, sessionEpoch: 'epoch-1' };
      const responder = new PeerTaskResponder(options);
      const cancel: CancelDataPayload = { taskId: 'task-1', peerTaskId: 'task-1@peer-a', code: 'USER_CANCEL', reason: 'cancel' };
      await responder.onEnvelope('peer-a', envelope('CANCEL', cancel));
      await responder.onEnvelope('peer-a', envelope('TASK', taskPayload()));
      expect(sent.length).assertEqual(0);
    });
    it('ignores a task from a different session epoch', 0, async () => {
      const sent: ResponderMessage[] = []; const provider = new FakeProvider(); const digest: EvidenceDigest = new FakeDigest();
      const send = async (_deviceId: string, message: ResponderMessage): Promise<void> => { sent.push(message); };
      const options: PeerTaskResponderOptions = { send, provider, digest, sessionEpoch: 'epoch-1' };
      const responder = new PeerTaskResponder(options);
      await responder.onEnvelope('peer-a', envelope('TASK', taskPayload(), 1, 'stale-epoch'));
      expect(sent.length).assertEqual(0);
      expect(provider.searches).assertEqual(0);
    });
  });
}
