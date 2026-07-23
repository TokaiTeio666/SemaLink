import { AgentQueryScope } from './query/AgentQueryModels';

export class SemaLinkAgentRequest {
  contextId: string;
  taskId: string;
  queryText: string;
  requestedScope?: AgentQueryScope;

  constructor(contextId: string, taskId: string, queryText: string, requestedScope?: AgentQueryScope) {
    this.contextId = contextId;
    this.taskId = taskId;
    this.queryText = queryText;
    this.requestedScope = requestedScope;
  }
}

export enum SemaLinkAgentResponseKind {
  COMPLETED = 'COMPLETED',
  INPUT_REQUIRED = 'INPUT_REQUIRED'
}

export class SemaLinkAgentResponse {
  text: string;
  kind: SemaLinkAgentResponseKind;
  originalScope?: AgentQueryScope;
  requestedScope?: AgentQueryScope;
  pendingInputReason?: string;
  continuationAction?: string;

  constructor(text: string, kind: SemaLinkAgentResponseKind = SemaLinkAgentResponseKind.COMPLETED) {
    this.text = text;
    this.kind = kind;
  }

  static inputRequired(text: string, originalScope: AgentQueryScope, requestedScope: AgentQueryScope,
    pendingInputReason: string, continuationAction: string): SemaLinkAgentResponse {
    const response: SemaLinkAgentResponse =
      new SemaLinkAgentResponse(text, SemaLinkAgentResponseKind.INPUT_REQUIRED);
    response.originalScope = originalScope;
    response.requestedScope = requestedScope;
    response.pendingInputReason = pendingInputReason;
    response.continuationAction = continuationAction;
    return response;
  }
}
