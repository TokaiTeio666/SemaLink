import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeProfile } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { SemanticKnowledgeProvider } from '../main/ets/contracts/semantic/SemanticKnowledgeProvider';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import { SequenceIdGenerator } from '../main/ets/common/IdGenerator';
import { A2ACommandCodec } from '../main/ets/agent/a2a/A2ACommandCodec';
import { A2AResponseFactory } from '../main/ets/agent/a2a/A2AResponseFactory';
import { AgentSessionRegistry } from '../main/ets/agent/a2a/AgentSessionRegistry';
import { AgentTaskRegistry } from '../main/ets/agent/a2a/AgentTaskRegistry';
import { RealSemaLinkAgentExecutor } from '../main/ets/agent/RealSemaLinkAgentExecutor';
import { AgentDataSender, SemaLinkAgentAbilityOrchestrator } from '../main/ets/agent/SemaLinkAgentAbilityOrchestrator';
import { AgentKnowledgeQueryPort } from '../main/ets/agent/query/AgentKnowledgeQueryPort';
import { AgentQueryRequest, AgentQueryResult } from '../main/ets/agent/query/AgentQueryModels';
import { KnowledgeAnswerFormatter } from '../main/ets/agent/query/KnowledgeAnswerFormatter';
import { LocalFirstAgentKnowledgeQueryService } from '../main/ets/agent/query/LocalFirstAgentKnowledgeQueryService';
import { FakeCrossDeviceKnowledgePort } from './support/FakeCrossDeviceKnowledgePort';

const UNIQUE: string = 'SEMALINK_REMOTE_EVIDENCE_UNIQUE_20260722';
const REQUEST: string = '{"jsonrpc":"2.0","id":"e2e-1","method":"message/stream","params":{"message":{"messageId":"message-e2e","role":"ROLE_USER","parts":[{"text":"查询其他设备 database","mediaType":"text/plain"}]},"metadata":{"traceId":"trace-e2e","agentId":"semalink_knowledge_agent"}}}';

function evidence(id: string, source: string, summary: string, hash: string): EvidenceUnit {
  return {
    semanticContractVersion: '1.0', evidenceId: id, evidenceGroupId: 'group-' + id,
    sourceDeviceId: source, sourceDocId: 'doc-' + id, level: 'L2', title: 'Database notes',
    summary: summary, snippet: summary, relevance: 0.95, coveredConcepts: ['database'],
    estimatedCoverageGain: 1, byteCost: 128, privacyLevel: 'PRIVATE_GROUP', privacyCost: 0.1,
    energyCost: 0.1, hash: hash, canEscalateTo: []
  };
}

class LocalProvider implements SemanticKnowledgeProvider {
  readonly evidence: EvidenceUnit[];

  constructor(evidenceUnits: EvidenceUnit[]) {
    this.evidence = evidenceUnits;
  }

  getProfile(): Promise<KnowledgeProfile> {
    return Promise.reject(new Error('not used'));
  }

  searchEvidence(_task: TaskRequest): Promise<EvidenceUnit[]> {
    return Promise.resolve(this.evidence);
  }
}

class CapturingQueryPort implements AgentKnowledgeQueryPort {
  private readonly delegate: AgentKnowledgeQueryPort;
  lastResult?: AgentQueryResult;

  constructor(delegate: AgentKnowledgeQueryPort) {
    this.delegate = delegate;
  }

  async query(request: AgentQueryRequest): Promise<AgentQueryResult> {
    const result = await this.delegate.query(request);
    this.lastResult = result;
    return result;
  }

  cancel(internalTaskId: string): void {
    this.delegate.cancel(internalTaskId);
  }
}

class CapturingSender implements AgentDataSender {
  readonly frames: string[] = [];
  send(data: string): void {
    this.frames.push(data);
  }
}

function terminalState(frame: string): string {
  const envelope = JSON.parse(frame) as Record<string, Object>;
  const result = envelope['result'] as Record<string, Object>;
  const taskValue: Object | undefined = result['task'];
  if (taskValue !== undefined) {
    const task: Record<string, Object> = taskValue as Record<string, Object>;
    return (task['status'] as Record<string, Object>)['state'] as string;
  }
  const update: Record<string, Object> = result['statusUpdate'] as Record<string, Object>;
  const status = update['status'] as Record<string, Object>;
  return status['state'] as string;
}

export default function mockDualDeviceAgentEndToEndTest(): void {
  describe('MockDualDeviceAgentEndToEnd', () => {
    it('consumes fake device B evidence through the complete A2A orchestration chain', 0, async () => {
      const local = new LocalProvider([evidence('local-1', 'local-device', 'local database note', 'local-hash')]);
      const remote = new FakeCrossDeviceKnowledgePort();
      remote.evidence = [evidence('remote-1', 'MOCK_DEVICE_ID_MUST_NOT_LEAK', UNIQUE, 'remote-hash')];
      const query = new CapturingQueryPort(new LocalFirstAgentKnowledgeQueryService(local, remote));
      const ids = new SequenceIdGenerator((): number => 20260722);
      const orchestrator = new SemaLinkAgentAbilityOrchestrator(
        new A2ACommandCodec(), new A2AResponseFactory(),
        new AgentSessionRegistry(ids, (): number => 20260722, 60000, 8),
        new AgentTaskRegistry((): number => 20260722, 60000), ids,
        new RealSemaLinkAgentExecutor(query, new KnowledgeAnswerFormatter()));
      const sender = new CapturingSender();

      await orchestrator.handleData('device-a-connection', sender, REQUEST);

      expect(sender.frames.length).assertEqual(4);
      expect(query.lastResult?.queriedRemote).assertTrue();
      const artifact = sender.frames[2];
      const completed = sender.frames[3];
      expect(terminalState(completed)).assertEqual('TASK_STATE_COMPLETED');
      expect(artifact.includes(UNIQUE)).assertTrue();
      expect(artifact.includes('MOCK_DEVICE_ID_MUST_NOT_LEAK')).assertFalse();
      expect(artifact.includes('artifactId')).assertTrue();
      expect(artifact.includes('"lastChunk":true')).assertTrue();
      expect(artifact.includes('text/plain')).assertTrue();
      expect(artifact.includes('Stub')).assertFalse();
    });
  });
}
