import { AppError, ErrorStage } from '../common/AppError';
import { SemaLinkAgentRequest } from './SemaLinkAgentModels';

export const MAX_AGENT_QUERY_CHARS: number = 1000;

export class SemaLinkAgentRequestValidator {
  validate(contextId: string, taskId: string, query: Object): SemaLinkAgentRequest {
    if (typeof query !== 'string') {
      throw this.invalidQuery();
    }
    const normalized: string = (query as string).trim();
    if (normalized.length === 0 || normalized.length > MAX_AGENT_QUERY_CHARS) {
      throw this.invalidQuery();
    }
    return new SemaLinkAgentRequest(contextId, taskId, normalized);
  }

  private invalidQuery(): AppError {
    return new AppError(
      'E_AGENT_QUERY_INVALID',
      'Agent query is invalid',
      ErrorStage.QUERY,
      true
    );
  }
}
