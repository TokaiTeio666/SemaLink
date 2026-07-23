import { AppError } from '../common/AppError';
import { SequenceIdGenerator } from '../common/IdGenerator';
import { A2ACommandCodec } from './a2a/A2ACommandCodec';
import {
  A2ACancelCommand,
  A2ACommand,
  A2ACommandKind,
  A2AConversationCommand,
  A2AResponseId,
  A2ATaskState
} from './a2a/A2AModels';
import { A2AResponseFactory } from './a2a/A2AResponseFactory';
import { AgentSessionRegistry } from './a2a/AgentSessionRegistry';
import { AgentTaskRecord, AgentTaskRegistry } from './a2a/AgentTaskRegistry';
import {
  AgentContinuationDecision,
  AgentContinuationDecisionParser
} from './a2a/AgentContinuationDecision';
import { SemaLinkAgentExecutor } from './SemaLinkAgentExecutor';
import {
  SemaLinkAgentRequest,
  SemaLinkAgentResponse,
  SemaLinkAgentResponseKind
} from './SemaLinkAgentModels';
import { AgentSafeLog } from './AgentSafeLog';
import { AgentQueryScope } from './query/AgentQueryModels';

export interface AgentDataSender {
  send(data: string): void;
}

export class SemaLinkAgentAbilityOrchestrator {
  private readonly codec: A2ACommandCodec;
  private readonly responses: A2AResponseFactory;
  private readonly sessions: AgentSessionRegistry;
  private readonly tasks: AgentTaskRegistry;
  private readonly ids: SequenceIdGenerator;
  private readonly executor: SemaLinkAgentExecutor;
  private readonly continuation: AgentContinuationDecisionParser = new AgentContinuationDecisionParser();

  constructor(codec: A2ACommandCodec, responses: A2AResponseFactory,
    sessions: AgentSessionRegistry, tasks: AgentTaskRegistry,
    ids: SequenceIdGenerator, executor: SemaLinkAgentExecutor) {
    this.codec = codec;
    this.responses = responses;
    this.sessions = sessions;
    this.tasks = tasks;
    this.ids = ids;
    this.executor = executor;
  }

  async handleData(connectionId: string, sender: AgentDataSender, data: string): Promise<void> {
    let command: A2ACommand;
    try {
      command = this.codec.decode(data);
    } catch (error) {
      AgentSafeLog.error(this.safeProtocolMessage(error));
      this.send(sender, this.responses.error(
        this.requestIdForError(data), this.rpcCode(error), this.safeProtocolMessage(error)));
      return;
    }
    AgentSafeLog.command(command.kind);
    if (command.kind === A2ACommandKind.TASK_CANCEL) {
      this.handleCancel(connectionId, sender, command as A2ACancelCommand);
      return;
    }
    await this.handleConversation(connectionId, sender, command as A2AConversationCommand);
  }

  disconnect(connectionId: string): void {
    this.tasks.cancelConnection(connectionId);
    this.sessions.invalidateConnection(connectionId);
  }

  private async handleConversation(connectionId: string, sender: AgentDataSender,
    command: A2AConversationCommand): Promise<void> {
    let existing: AgentTaskRecord | undefined;
    if (command.taskId !== undefined) {
      existing = this.tasks.find(command.taskId);
      if (existing === undefined || existing.connectionId !== connectionId) {
        this.send(sender, this.responses.error(command.requestId, -32001, 'Task not found'));
        return;
      }
    }
    let contextId: string;
    try {
      contextId = this.sessions.resolve(connectionId, command.contextId, this.tasks.activeContextIds());
    } catch (_error) {
      this.send(sender, this.responses.error(command.requestId, 99911222, 'Context invalid'));
      return;
    }

    if (command.taskId !== undefined) {
      const owned: AgentTaskRecord = existing as AgentTaskRecord;
      if (owned.contextId !== contextId) {
        this.send(sender, this.responses.error(command.requestId, -32004, 'Task cannot accept input'));
        return;
      }
      await this.handleContinuation(sender, command, owned);
      return;
    }

    const taskId: string = this.ids.next('agent-task');
    const internalTaskId: string = this.ids.next('agent-internal-task');
    let record: AgentTaskRecord;
    try {
      record = this.tasks.create(connectionId, contextId, taskId, internalTaskId,
        (): void => this.executor.cancel(internalTaskId),
        this.timeoutCallback(sender, command, contextId, taskId), command.queryText);
    } catch (_error) {
      this.send(sender, this.responses.error(command.requestId, -32003, 'Task capacity reached'));
      return;
    }
    this.send(sender, this.responses.submitted(command.requestId, contextId, taskId, command.metadata));
    AgentSafeLog.transition(contextId, taskId, A2ATaskState.SUBMITTED);
    this.tasks.transition(taskId, A2ATaskState.WORKING);
    this.send(sender, this.responses.working(command.requestId, contextId, taskId, command.metadata));
    AgentSafeLog.transition(contextId, taskId, A2ATaskState.WORKING);
    await this.executeTask(sender, command, record, record.executionGeneration, command.queryText);
  }

  private async handleContinuation(sender: AgentDataSender, command: A2AConversationCommand,
    record: AgentTaskRecord): Promise<void> {
    if (record.state !== A2ATaskState.INPUT_REQUIRED) {
      this.send(sender, this.responses.error(command.requestId, -32004, 'Task cannot accept input'));
      return;
    }
    const decision: AgentContinuationDecision = this.continuation.parse(command.queryText);
    if (decision === AgentContinuationDecision.UNRELATED) {
      this.send(sender, this.responses.inputRequired(
        command.requestId, record.contextId, record.taskId,
        '请明确回复是否改为本机查询；也可以回复取消。', command.metadata));
      return;
    }
    if (decision === AgentContinuationDecision.REJECT || decision === AgentContinuationDecision.CANCEL) {
      if (!this.tasks.cancel(record.taskId)) {
        this.send(sender, this.responses.error(command.requestId, -32004, 'Task cannot accept input'));
        return;
      }
      this.send(sender, this.responses.cancelled(
        command.requestId, record.contextId, record.taskId, command.metadata));
      AgentSafeLog.transition(record.contextId, record.taskId, A2ATaskState.CANCELLED);
      return;
    }
    if (record.continuationAction !== 'LOCAL_FALLBACK' ||
      record.requestedScope !== AgentQueryScope.LOCAL_ONLY) {
      this.send(sender, this.responses.error(command.requestId, -32004, 'Task cannot accept input'));
      return;
    }
    const generation: number = this.tasks.resume(
      record.taskId, this.timeoutCallback(sender, command, record.contextId, record.taskId));
    if (generation === 0) {
      this.send(sender, this.responses.error(command.requestId, -32004, 'Task cannot accept input'));
      return;
    }
    this.send(sender, this.responses.working(
      command.requestId, record.contextId, record.taskId, command.metadata));
    AgentSafeLog.transition(record.contextId, record.taskId, A2ATaskState.WORKING);
    await this.executeTask(
      sender, command, record, generation, record.originalQueryText, AgentQueryScope.LOCAL_ONLY);
  }

  private async executeTask(sender: AgentDataSender, command: A2AConversationCommand,
    record: AgentTaskRecord, generation: number, queryText: string,
    requestedScope?: AgentQueryScope): Promise<void> {
    try {
      const response: SemaLinkAgentResponse = await this.executor.execute(
        new SemaLinkAgentRequest(record.contextId, record.internalTaskId, queryText, requestedScope));
      if (response.kind === SemaLinkAgentResponseKind.INPUT_REQUIRED) {
        if (this.tasks.isCurrentGeneration(record.taskId, generation) &&
          this.tasks.suspendForInput(
            record.taskId,
            response.originalScope ?? '',
            response.requestedScope ?? '',
            response.pendingInputReason ?? '',
            response.continuationAction ?? '')) {
          this.send(sender, this.responses.inputRequired(
            command.requestId, record.contextId, record.taskId, response.text, command.metadata));
          AgentSafeLog.transition(record.contextId, record.taskId, A2ATaskState.INPUT_REQUIRED);
        }
        return;
      }
      if (this.tasks.transitionIfCurrent(record.taskId, generation, A2ATaskState.COMPLETED)) {
        this.send(sender, this.responses.artifactUpdate(
          command.requestId, record.contextId, record.taskId, this.ids.next('agent-artifact'), response.text,
          false, true, command.metadata));
        this.send(sender, this.responses.completedStatus(
          command.requestId, record.contextId, record.taskId, command.metadata));
        AgentSafeLog.transition(record.contextId, record.taskId, A2ATaskState.COMPLETED);
      }
    } catch (_error) {
      if (this.tasks.transitionIfCurrent(record.taskId, generation, A2ATaskState.FAILED)) {
        this.send(sender, this.responses.failed(
          command.requestId, record.contextId, record.taskId, '-32603', 'SemaLink 暂时无法处理此请求，请稍后重试。',
          command.metadata));
        AgentSafeLog.transition(record.contextId, record.taskId, A2ATaskState.FAILED);
      }
    }
  }

  private timeoutCallback(sender: AgentDataSender, command: A2AConversationCommand,
    contextId: string, taskId: string): () => void {
    return (): void => {
      this.send(sender, this.responses.failed(
        command.requestId, contextId, taskId, 'E_A2A_TASK_TIMEOUT',
        'SemaLink 处理超时，请重试。', command.metadata));
      AgentSafeLog.transition(contextId, taskId, A2ATaskState.FAILED);
    };
  }

  private handleCancel(connectionId: string, sender: AgentDataSender, command: A2ACancelCommand): void {
    const record: AgentTaskRecord | undefined = this.tasks.find(command.taskId);
    if (record === undefined || record.connectionId !== connectionId || !this.sessions.isValid(record.contextId)) {
      this.send(sender, this.responses.error(command.requestId, -32001, 'Task not found'));
      return;
    }
    if (!this.tasks.cancel(command.taskId)) {
      this.send(sender, this.responses.error(command.requestId, -32002, 'Task cannot be canceled'));
      return;
    }
    this.send(sender, this.responses.cancelled(
      command.requestId, record.contextId, record.taskId, command.metadata));
    AgentSafeLog.transition(record.contextId, record.taskId, A2ATaskState.CANCELLED);
  }

  private send(sender: AgentDataSender, data: string): void {
    try {
      sender.send(data);
    } catch (_error) {
    }
  }

  private rpcCode(error: Object): number {
    if (error instanceof AppError) {
      if (error.code === 'E_A2A_PARSE') return -32700;
      if (error.code === 'E_A2A_REQUEST') return -32600;
      if (error.code === 'E_A2A_PARAMS') return -32602;
      if (error.code === 'E_A2A_UNSUPPORTED') return -32004;
    }
    return -32603;
  }

  private safeProtocolMessage(error: Object): string {
    if (error instanceof AppError) {
      if (error.code === 'E_A2A_PARSE') return 'Parse error';
      if (error.code === 'E_A2A_REQUEST') return 'Invalid request';
      if (error.code === 'E_A2A_PARAMS') return 'Invalid params';
      if (error.code === 'E_A2A_UNSUPPORTED') return 'Unsupported operation';
    }
    return 'Internal error';
  }

  private requestIdForError(data: string): A2AResponseId {
    try {
      const parsed: Object = JSON.parse(data) as Object;
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        return null;
      }
      const value: Object | undefined = (parsed as Record<string, Object>)['id'];
      if (typeof value === 'string' && value.length > 0) {
        return value;
      }
      if (typeof value === 'number' && Number.isFinite(value)) {
        return value;
      }
    } catch (_error) {
    }
    return null;
  }
}
