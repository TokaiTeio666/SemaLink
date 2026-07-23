import { describe, expect, it } from '@ohos/hypium';
import { SequenceIdGenerator } from '../main/ets/common/IdGenerator';
import { KnowledgeProfile } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import { SemanticKnowledgeProvider } from '../main/ets/contracts/semantic/SemanticKnowledgeProvider';
import { A2ACommandCodec } from '../main/ets/agent/a2a/A2ACommandCodec';
import { A2AResponseFactory } from '../main/ets/agent/a2a/A2AResponseFactory';
import { AgentSessionRegistry } from '../main/ets/agent/a2a/AgentSessionRegistry';
import { AgentTaskRegistry } from '../main/ets/agent/a2a/AgentTaskRegistry';
import { AgentDataSender, SemaLinkAgentAbilityOrchestrator }
  from '../main/ets/agent/SemaLinkAgentAbilityOrchestrator';
import { RealSemaLinkAgentExecutor } from '../main/ets/agent/RealSemaLinkAgentExecutor';
import { KnowledgeAnswerFormatter } from '../main/ets/agent/query/KnowledgeAnswerFormatter';
import { LocalFirstAgentKnowledgeQueryService }
  from '../main/ets/agent/query/LocalFirstAgentKnowledgeQueryService';
import { UnavailableCrossDeviceKnowledgePort }
  from '../main/ets/agent/query/UnavailableCrossDeviceKnowledgePort';

const ORIGINAL: string = '查询另一台可信设备上的数据库事务隔离级别';

function evidence(): EvidenceUnit {
  return {
    semanticContractVersion: '1.0',
    evidenceId: 'local-evidence-1',
    evidenceGroupId: 'local-group-1',
    sourceDeviceId: 'local-device',
    sourceDocId: 'local-doc-1',
    level: 'L2',
    title: '数据库事务资料',
    summary: '数据库事务隔离级别包括读未提交、读已提交、可重复读和串行化。',
    relevance: 0.98,
    coveredConcepts: ['数据库事务隔离级别'],
    estimatedCoverageGain: 0.98,
    byteCost: 160,
    privacyLevel: 'LOCAL_ONLY',
    privacyCost: 0,
    energyCost: 0.1,
    hash: 'local-isolation-levels',
    canEscalateTo: []
  };
}

class EndToEndLocalProvider implements SemanticKnowledgeProvider {
  readonly requests: TaskRequest[] = [];

  getProfile(): Promise<KnowledgeProfile> {
    return Promise.reject(new Error('Profile is not used by this test'));
  }

  searchEvidence(task: TaskRequest): Promise<EvidenceUnit[]> {
    this.requests.push(task);
    return Promise.resolve([evidence()]);
  }
}

class EndToEndSender implements AgentDataSender {
  readonly frames: string[] = [];
  send(data: string): void { this.frames.push(data); }
}

class EndToEndFixture {
  readonly provider: EndToEndLocalProvider = new EndToEndLocalProvider();
  readonly sender: EndToEndSender = new EndToEndSender();
  readonly orchestrator: SemaLinkAgentAbilityOrchestrator;

  constructor() {
    const ids: SequenceIdGenerator = new SequenceIdGenerator((): number => 4300);
    const query = new LocalFirstAgentKnowledgeQueryService(
      this.provider, new UnavailableCrossDeviceKnowledgePort(), (): number => 4300);
    const executor: RealSemaLinkAgentExecutor =
      new RealSemaLinkAgentExecutor(query, new KnowledgeAnswerFormatter());
    this.orchestrator = new SemaLinkAgentAbilityOrchestrator(
      new A2ACommandCodec(), new A2AResponseFactory(),
      new AgentSessionRegistry(ids, (): number => 4300, 60000, 8),
      new AgentTaskRegistry((): number => 4300, 60000), ids, executor);
  }

  async start(): Promise<string[]> {
    const first: string =
      '{"jsonrpc":"2.0","id":"request-1","method":"message/stream","params":{"message":{' +
      '"messageId":"message-1","role":"ROLE_USER","parts":[{"text":"' + ORIGINAL + '"}]},' +
      '"metadata":{"traceId":"trace-1","agentId":"untrusted-request-agent"}}}';
    await this.orchestrator.handleData('connection-1', this.sender, first);
    const envelope: Record<string, Object> = JSON.parse(this.sender.frames[0]) as Record<string, Object>;
    const result: Record<string, Object> = envelope['result'] as Record<string, Object>;
    const task: Record<string, Object> = result['task'] as Record<string, Object>;
    return [task['id'] as string, task['contextId'] as string];
  }

  async continueWith(task: string[], text: string, requestId: string): Promise<void> {
    const followUp: string =
      '{"jsonrpc":"2.0","id":"' + requestId + '","method":"message/stream","params":{"message":{' +
      '"messageId":"message-' + requestId + '","taskId":"' + task[0] + '","contextId":"' + task[1] + '",' +
      '"role":"ROLE_USER","parts":[{"text":"' + text + '"}]},' +
      '"metadata":{"traceId":"trace-' + requestId + '","agentId":"untrusted-request-agent"}}}';
    await this.orchestrator.handleData('connection-1', this.sender, followUp);
  }
}

function lastState(sender: EndToEndSender): string {
  const envelope: Record<string, Object> =
    JSON.parse(sender.frames[sender.frames.length - 1]) as Record<string, Object>;
  const result: Record<string, Object> = envelope['result'] as Record<string, Object>;
  const directStatus: Object | undefined = result['status'];
  if (directStatus !== undefined) {
    return (directStatus as Record<string, Object>)['state'] as string;
  }
  const task: Object | undefined = result['task'];
  if (task !== undefined) {
    const taskRecord: Record<string, Object> = task as Record<string, Object>;
    return (taskRecord['status'] as Record<string, Object>)['state'] as string;
  }
  const statusUpdate: Record<string, Object> = result['statusUpdate'] as Record<string, Object>;
  return (statusUpdate['status'] as Record<string, Object>)['state'] as string;
}

export default function semaLinkAgentContinuationEndToEndTest(): void {
  describe('SemaLinkAgentContinuationEndToEnd', () => {
    it('runs REMOTE_ONLY unavailable through the original local query to Evidence and COMPLETED', 0, async () => {
      const fixture: EndToEndFixture = new EndToEndFixture();
      const task: string[] = await fixture.start();
      expect(lastState(fixture.sender)).assertEqual('TASK_STATE_INPUT_REQUIRED');
      expect(fixture.provider.requests.length).assertEqual(0);
      await fixture.continueWith(task, '改为本机查询', 'request-2');

      expect(fixture.provider.requests.length).assertEqual(1);
      expect(fixture.provider.requests[0].queryText).assertEqual(ORIGINAL);
      expect(fixture.provider.requests[0].queryText === '改为本机查询').assertFalse();
      expect(fixture.provider.requests[0].privacyLevel).assertEqual('LOCAL_ONLY');
      expect(fixture.sender.frames[fixture.sender.frames.length - 2].includes('数据库事务隔离级别包括')).assertTrue();
      expect(fixture.sender.frames[fixture.sender.frames.length - 2].includes('Stub')).assertFalse();
      expect(lastState(fixture.sender)).assertEqual('TASK_STATE_COMPLETED');
      expect(fixture.sender.frames[fixture.sender.frames.length - 1].includes(task[0])).assertTrue();
      expect(fixture.sender.frames[fixture.sender.frames.length - 1].includes(task[1])).assertTrue();
      const terminal: Record<string, Object> =
        JSON.parse(fixture.sender.frames[fixture.sender.frames.length - 1]) as Record<string, Object>;
      expect(terminal['id'] as string).assertEqual('request-2');
      const metadata: Record<string, Object> =
        (terminal['result'] as Record<string, Object>)['metadata'] as Record<string, Object>;
      expect(metadata['agentId'] as string).assertEqual('semalink_knowledge_agent');
    });

    it('keeps unrelated input pending and never sends it to the provider', 0, async () => {
      const fixture: EndToEndFixture = new EndToEndFixture();
      const task: string[] = await fixture.start();
      await fixture.continueWith(task, '顺便解释一下 MVCC', 'request-unrelated');
      expect(fixture.provider.requests.length).assertEqual(0);
      expect(lastState(fixture.sender)).assertEqual('TASK_STATE_INPUT_REQUIRED');
      await fixture.continueWith(task, '同意', 'request-accept');
      expect(fixture.provider.requests.length).assertEqual(1);
      expect(fixture.provider.requests[0].queryText).assertEqual(ORIGINAL);
    });

    it('cancels on rejection or cancellation and rejects terminal continuation', 0, async () => {
      const rejected: EndToEndFixture = new EndToEndFixture();
      const rejectedTask: string[] = await rejected.start();
      await rejected.continueWith(rejectedTask, '不同意', 'request-reject');
      expect(lastState(rejected.sender)).assertEqual('TASK_STATE_CANCELLED');
      expect(rejected.provider.requests.length).assertEqual(0);
      const beforeTerminal: number = rejected.sender.frames.length;
      await rejected.continueWith(rejectedTask, '同意', 'request-after-terminal');
      expect(rejected.sender.frames.length).assertEqual(beforeTerminal + 1);
      expect(rejected.provider.requests.length).assertEqual(0);
      expect(rejected.sender.frames[rejected.sender.frames.length - 1].includes('error')).assertTrue();

      const cancelled: EndToEndFixture = new EndToEndFixture();
      const cancelledTask: string[] = await cancelled.start();
      await cancelled.continueWith(cancelledTask, '取消', 'request-cancel');
      expect(lastState(cancelled.sender)).assertEqual('TASK_STATE_CANCELLED');
      expect(cancelled.provider.requests.length).assertEqual(0);
    });
  });
}
