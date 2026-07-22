import {
  SemaLinkAgentRequest,
  SemaLinkAgentResponse
} from './SemaLinkAgentModels';

export interface SemaLinkAgentExecutor {
  execute(request: SemaLinkAgentRequest): Promise<SemaLinkAgentResponse>;
  cancel(taskId: string): void;
}
