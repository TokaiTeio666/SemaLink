import { AgentQueryRequest, AgentQueryResult } from './AgentQueryModels';

export interface AgentKnowledgeQueryPort {
  query(request: AgentQueryRequest): Promise<AgentQueryResult>;
  cancel(internalTaskId: string): void;
}
