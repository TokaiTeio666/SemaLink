import { describe, expect, it } from '@ohos/hypium';
import { TaskSufficiencyResult } from '../main/ets/contracts/semantic/SemanticModels';
import { AgentKnowledgeQueryPort } from '../main/ets/agent/query/AgentKnowledgeQueryPort';
import { AgentQueryRequest, AgentQueryResult } from '../main/ets/agent/query/AgentQueryModels';
import { KnowledgeAnswerFormatter } from '../main/ets/agent/query/KnowledgeAnswerFormatter';
import { RealSemaLinkAgentExecutor } from '../main/ets/agent/RealSemaLinkAgentExecutor';
import { SemaLinkAgentRequest, SemaLinkAgentResponse } from '../main/ets/agent/SemaLinkAgentModels';

class CapturingQueryPort implements AgentKnowledgeQueryPort {
  captured?: AgentQueryRequest;
  cancelled: string[] = [];

  query(request: AgentQueryRequest): Promise<AgentQueryResult> {
    this.captured = request;
    const sufficiency: TaskSufficiencyResult = {
      feedback: 'ABORT', coverage: 0, confidence: 0, diversity: 0,
      coveredConcepts: [], missingConcepts: [], acceptedEvidenceIds: []
    };
    return Promise.resolve(new AgentQueryResult(
      request.internalTaskId, [], sufficiency, true, false, false, [], 1, []));
  }

  cancel(internalTaskId: string): void {
    this.cancelled.push(internalTaskId);
  }
}

export default function realSemaLinkAgentExecutorTest(): void {
  describe('RealSemaLinkAgentExecutor', () => {
    it('uses query port and formatter instead of stub text', 0, async () => {
      const port: CapturingQueryPort = new CapturingQueryPort();
      const executor: RealSemaLinkAgentExecutor =
        new RealSemaLinkAgentExecutor(port, new KnowledgeAnswerFormatter());
      const response: SemaLinkAgentResponse = await executor.execute(
        new SemaLinkAgentRequest('ctx-1', 'internal-1', '数据库'));
      expect(port.captured?.queryText).assertEqual('数据库');
      expect(response.text.indexOf('未找到相关资料') >= 0).assertTrue();
      expect(response.text.indexOf('正在准备中') < 0).assertTrue();
    });

    it('propagates cancellation to query port', 0, () => {
      const port: CapturingQueryPort = new CapturingQueryPort();
      const executor: RealSemaLinkAgentExecutor =
        new RealSemaLinkAgentExecutor(port, new KnowledgeAnswerFormatter());
      executor.cancel('internal-2');
      expect(port.cancelled[0]).assertEqual('internal-2');
    });
  });
}
