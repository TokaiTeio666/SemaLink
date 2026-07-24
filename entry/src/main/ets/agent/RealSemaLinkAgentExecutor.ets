import { SemaLinkAgentExecutor } from './SemaLinkAgentExecutor';
import {
  SemaLinkAgentRequest,
  SemaLinkAgentResponse
} from './SemaLinkAgentModels';
import { AgentKnowledgeQueryPort } from './query/AgentKnowledgeQueryPort';
import { AgentQueryRequest, AgentQueryResult, AgentQueryScope } from './query/AgentQueryModels';
import { KnowledgeAnswerFormatter } from './query/KnowledgeAnswerFormatter';
import { AgentQueryScopeResolver } from './query/AgentQueryScopeResolver';

export class RealSemaLinkAgentExecutor implements SemaLinkAgentExecutor {
  private readonly queryPort: AgentKnowledgeQueryPort;
  private readonly formatter: KnowledgeAnswerFormatter;
  private readonly scopeResolver: AgentQueryScopeResolver;

  constructor(queryPort: AgentKnowledgeQueryPort, formatter: KnowledgeAnswerFormatter,
    scopeResolver: AgentQueryScopeResolver = new AgentQueryScopeResolver()) {
    this.queryPort = queryPort;
    this.formatter = formatter;
    this.scopeResolver = scopeResolver;
  }

  async execute(request: SemaLinkAgentRequest): Promise<SemaLinkAgentResponse> {
    const scope: AgentQueryScope = request.requestedScope ?? this.scopeResolver.resolve(request.queryText);
    const query: AgentQueryRequest = new AgentQueryRequest(request.taskId, request.queryText, scope);
    const result: AgentQueryResult = await this.queryPort.query(query);
    if (scope === AgentQueryScope.REMOTE_ONLY && !result.remoteAvailable) {
      return SemaLinkAgentResponse.inputRequired(
        '跨设备通道当前不可用，是否改为本机查询？',
        AgentQueryScope.REMOTE_ONLY,
        AgentQueryScope.LOCAL_ONLY,
        'REMOTE_CHANNEL_UNAVAILABLE',
        'LOCAL_FALLBACK'
      );
    }
    return new SemaLinkAgentResponse(this.formatter.format(result));
  }

  cancel(taskId: string): void {
    this.queryPort.cancel(taskId);
  }
}
