export class SemaLinkAgentRequest {
  contextId: string;
  taskId: string;
  queryText: string;

  constructor(contextId: string, taskId: string, queryText: string) {
    this.contextId = contextId;
    this.taskId = taskId;
    this.queryText = queryText;
  }
}

export class SemaLinkAgentResponse {
  text: string;

  constructor(text: string) {
    this.text = text;
  }
}
