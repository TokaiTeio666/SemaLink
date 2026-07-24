export enum A2ACommandKind {
  MESSAGE_STREAM = 'message/stream',
  TASK_CANCEL = 'tasks/cancel'
}

export enum A2ATaskState {
  SUBMITTED = 'TASK_STATE_SUBMITTED',
  WORKING = 'TASK_STATE_WORKING',
  INPUT_REQUIRED = 'TASK_STATE_INPUT_REQUIRED',
  COMPLETED = 'TASK_STATE_COMPLETED',
  CANCELLED = 'TASK_STATE_CANCELLED',
  FAILED = 'TASK_STATE_FAILED'
}

export type A2ARequestId = string | number;
export type A2AResponseId = A2ARequestId | null;

export function normalizeA2ATaskState(value: string): A2ATaskState {
  if (value === 'TASK_STATE_CANCELED' || value === A2ATaskState.CANCELLED) {
    return A2ATaskState.CANCELLED;
  }
  if (value === A2ATaskState.SUBMITTED) {
    return A2ATaskState.SUBMITTED;
  }
  if (value === A2ATaskState.WORKING) {
    return A2ATaskState.WORKING;
  }
  if (value === A2ATaskState.INPUT_REQUIRED) {
    return A2ATaskState.INPUT_REQUIRED;
  }
  if (value === A2ATaskState.COMPLETED) {
    return A2ATaskState.COMPLETED;
  }
  if (value === A2ATaskState.FAILED) {
    return A2ATaskState.FAILED;
  }
  throw new Error('Unsupported A2A task state');
}

export class A2AMetadata {
  readonly traceId: string;
  readonly agentId: string;

  constructor(traceId: string, agentId: string) {
    this.traceId = traceId;
    this.agentId = agentId;
  }
}

export interface A2ACommand {
  readonly kind: A2ACommandKind;
  readonly requestId: A2ARequestId;
  readonly metadata: A2AMetadata;
}

export class A2AConversationCommand implements A2ACommand {
  readonly kind: A2ACommandKind = A2ACommandKind.MESSAGE_STREAM;
  readonly requestId: A2ARequestId;
  readonly messageId: string;
  readonly contextId?: string;
  readonly taskId?: string;
  readonly queryText: string;
  readonly metadata: A2AMetadata;

  constructor(requestId: A2ARequestId, messageId: string, queryText: string, metadata: A2AMetadata,
    contextId?: string, taskId?: string) {
    this.requestId = requestId;
    this.messageId = messageId;
    this.queryText = queryText;
    this.metadata = metadata;
    this.contextId = contextId;
    this.taskId = taskId;
  }
}

export class A2ACancelCommand implements A2ACommand {
  readonly kind: A2ACommandKind = A2ACommandKind.TASK_CANCEL;
  readonly requestId: A2ARequestId;
  readonly taskId: string;
  readonly metadata: A2AMetadata;

  constructor(requestId: A2ARequestId, taskId: string, metadata: A2AMetadata) {
    this.requestId = requestId;
    this.taskId = taskId;
    this.metadata = metadata;
  }
}
