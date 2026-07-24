import { AppError, ErrorStage } from '../../common/AppError';
import { A2ATaskState } from './A2AModels';
import { A2ATaskStateMachine } from './A2ATaskStateMachine';
import { Scheduler, SystemScheduler } from '../../common/Scheduler';

export class AgentTaskRecord {
  readonly connectionId: string;
  readonly contextId: string;
  readonly taskId: string;
  readonly internalTaskId: string;
  state: A2ATaskState;
  readonly createdAt: number;
  updatedAt: number;
  cancelCallback?: () => void;
  timeoutCallback?: () => void;
  timeoutId?: number;
  originalQueryText: string;
  originalScope: string = '';
  requestedScope: string = '';
  pendingInputReason: string = '';
  continuationAction: string = '';
  executionGeneration: number = 1;
  executionDeadlineMs: number;
  pendingInputDeadlineMs: number = 0;

  constructor(connectionId: string, contextId: string, taskId: string, internalTaskId: string,
    now: number, cancelCallback: () => void, timeoutCallback?: () => void, originalQueryText: string = '',
    executionTimeoutMs: number = 0) {
    this.connectionId = connectionId;
    this.contextId = contextId;
    this.taskId = taskId;
    this.internalTaskId = internalTaskId;
    this.state = A2ATaskState.SUBMITTED;
    this.createdAt = now;
    this.updatedAt = now;
    this.cancelCallback = cancelCallback;
    this.timeoutCallback = timeoutCallback;
    this.originalQueryText = originalQueryText;
    this.executionDeadlineMs = now + executionTimeoutMs;
  }
}

export class AgentTaskRegistry {
  private readonly tasks: Map<string, AgentTaskRecord> = new Map<string, AgentTaskRecord>();
  private readonly clock: () => number;
  private readonly ttlMs: number;
  private readonly maxTasks: number;
  private readonly activeTimeoutMs: number;
  private readonly pendingInputTimeoutMs: number;
  private readonly stateMachine: A2ATaskStateMachine = new A2ATaskStateMachine();
  private readonly scheduler: Scheduler;

  constructor(clock: () => number = (): number => Date.now(), ttlMs: number = 30 * 60 * 1000,
    maxTasks: number = 128, activeTimeoutMs: number = 5 * 60 * 1000,
    scheduler: Scheduler = new SystemScheduler(), pendingInputTimeoutMs: number = 30 * 60 * 1000) {
    this.clock = clock;
    this.ttlMs = ttlMs;
    this.maxTasks = maxTasks;
    this.activeTimeoutMs = activeTimeoutMs;
    this.scheduler = scheduler;
    this.pendingInputTimeoutMs = pendingInputTimeoutMs;
  }

  create(connectionId: string, contextId: string, taskId: string, internalTaskId: string,
    cancelCallback: () => void, timeoutCallback?: () => void, originalQueryText: string = ''): AgentTaskRecord {
    this.cleanup();
    if (this.tasks.has(taskId)) {
      throw new AppError('E_A2A_TASK_DUPLICATE', 'Task already exists', ErrorStage.LIFECYCLE, false);
    }
    if (this.tasks.size >= this.maxTasks) {
      this.evictOldestTerminal();
    }
    if (this.tasks.size >= this.maxTasks) {
      throw new AppError('E_A2A_TASK_CAPACITY', 'Task registry capacity reached', ErrorStage.LIFECYCLE, true);
    }
    const record: AgentTaskRecord = new AgentTaskRecord(
      connectionId, contextId, taskId, internalTaskId, this.clock(), cancelCallback, timeoutCallback,
      originalQueryText, this.activeTimeoutMs);
    this.tasks.set(taskId, record);
    const generation: number = record.executionGeneration;
    record.timeoutId = this.scheduler.schedule(
      this.activeTimeoutMs, (): void => this.expireExecution(taskId, generation));
    return record;
  }

  find(taskId: string): AgentTaskRecord | undefined {
    this.cleanup();
    return this.tasks.get(taskId);
  }

  transition(taskId: string, next: A2ATaskState): boolean {
    const record: AgentTaskRecord | undefined = this.find(taskId);
    if (record === undefined || !this.stateMachine.canTransition(record.state, next)) {
      return false;
    }
    record.state = next;
    record.updatedAt = this.clock();
    if (next === A2ATaskState.INPUT_REQUIRED) {
      this.releaseTimer(record);
      record.timeoutCallback = undefined;
      record.executionDeadlineMs = 0;
      record.pendingInputDeadlineMs = record.updatedAt + this.pendingInputTimeoutMs;
      const generation: number = record.executionGeneration;
      record.timeoutId = this.scheduler.schedule(
        this.pendingInputTimeoutMs, (): void => this.expirePendingInput(taskId, generation));
    }
    if (this.stateMachine.isTerminal(next)) {
      record.cancelCallback = undefined;
      record.timeoutCallback = undefined;
      this.releaseTimer(record);
    }
    return true;
  }

  suspendForInput(taskId: string, originalScope: string, requestedScope: string,
    pendingInputReason: string, continuationAction: string): boolean {
    const record: AgentTaskRecord | undefined = this.find(taskId);
    if (record === undefined || record.state !== A2ATaskState.WORKING) {
      return false;
    }
    record.originalScope = originalScope;
    record.requestedScope = requestedScope;
    record.pendingInputReason = pendingInputReason;
    record.continuationAction = continuationAction;
    return this.transition(taskId, A2ATaskState.INPUT_REQUIRED);
  }

  resume(taskId: string, timeoutCallback: () => void): number {
    const record: AgentTaskRecord | undefined = this.find(taskId);
    if (record === undefined || record.state !== A2ATaskState.INPUT_REQUIRED) {
      return 0;
    }
    this.releaseTimer(record);
    record.executionGeneration += 1;
    record.timeoutCallback = timeoutCallback;
    record.state = A2ATaskState.WORKING;
    record.updatedAt = this.clock();
    record.pendingInputDeadlineMs = 0;
    record.executionDeadlineMs = record.updatedAt + this.activeTimeoutMs;
    const generation: number = record.executionGeneration;
    record.timeoutId = this.scheduler.schedule(
      this.activeTimeoutMs, (): void => this.expireExecution(taskId, generation));
    return generation;
  }

  transitionIfCurrent(taskId: string, generation: number, next: A2ATaskState): boolean {
    const record: AgentTaskRecord | undefined = this.find(taskId);
    if (record === undefined || record.executionGeneration !== generation) {
      return false;
    }
    return this.transition(taskId, next);
  }

  isCurrentGeneration(taskId: string, generation: number): boolean {
    const record: AgentTaskRecord | undefined = this.find(taskId);
    return record !== undefined && record.executionGeneration === generation;
  }

  cancel(taskId: string): boolean {
    const record: AgentTaskRecord | undefined = this.find(taskId);
    if (record === undefined || !this.stateMachine.canTransition(record.state, A2ATaskState.CANCELLED)) {
      return false;
    }
    const callback: (() => void) | undefined = record.cancelCallback;
    record.cancelCallback = undefined;
    record.timeoutCallback = undefined;
    this.releaseTimer(record);
    record.executionDeadlineMs = 0;
    record.pendingInputDeadlineMs = 0;
    record.state = A2ATaskState.CANCELLED;
    record.updatedAt = this.clock();
    if (callback !== undefined) {
      try {
        callback();
      } catch (_error) {
      }
    }
    return true;
  }

  cancelConnection(connectionId: string): void {
    const taskIds: string[] = Array.from(this.tasks.keys());
    for (const taskId of taskIds) {
      const record: AgentTaskRecord | undefined = this.tasks.get(taskId);
      if (record !== undefined && record.connectionId === connectionId && !this.stateMachine.isTerminal(record.state)) {
        this.cancel(taskId);
      }
    }
  }

  activeContextIds(): string[] {
    const result: string[] = [];
    for (const record of this.tasks.values()) {
      if (!this.stateMachine.isTerminal(record.state) && result.indexOf(record.contextId) < 0) {
        result.push(record.contextId);
      }
    }
    return result;
  }

  cleanup(): void {
    const now: number = this.clock();
    const taskIds: string[] = Array.from(this.tasks.keys());
    for (const taskId of taskIds) {
      const record: AgentTaskRecord | undefined = this.tasks.get(taskId);
      if (record !== undefined && record.state === A2ATaskState.INPUT_REQUIRED &&
        record.pendingInputDeadlineMs > 0 && now >= record.pendingInputDeadlineMs) {
        this.expirePendingInput(taskId, record.executionGeneration);
      } else if (record !== undefined && !this.stateMachine.isTerminal(record.state) &&
        record.executionDeadlineMs > 0 && now >= record.executionDeadlineMs) {
        this.expireExecution(taskId, record.executionGeneration);
      }
      if (record !== undefined && this.stateMachine.isTerminal(record.state) && now - record.updatedAt >= this.ttlMs) {
        this.tasks.delete(taskId);
      }
    }
  }

  private expireExecution(taskId: string, generation: number): void {
    const record: AgentTaskRecord | undefined = this.tasks.get(taskId);
    if (record === undefined || record.executionGeneration !== generation ||
      record.state === A2ATaskState.INPUT_REQUIRED || this.stateMachine.isTerminal(record.state)) {
      return;
    }
    const callback: (() => void) | undefined = record.cancelCallback;
    const timeoutCallback: (() => void) | undefined = record.timeoutCallback;
    record.cancelCallback = undefined;
    record.timeoutCallback = undefined;
    record.timeoutId = undefined;
    record.executionDeadlineMs = 0;
    record.pendingInputDeadlineMs = 0;
    record.state = A2ATaskState.FAILED;
    record.updatedAt = this.clock();
    if (callback !== undefined) {
      try {
        callback();
      } catch (_error) {
      }
    }
    if (timeoutCallback !== undefined) {
      try {
        timeoutCallback();
      } catch (_error) {
      }
    }
  }

  private expirePendingInput(taskId: string, generation: number): void {
    const record: AgentTaskRecord | undefined = this.tasks.get(taskId);
    if (record === undefined || record.executionGeneration !== generation ||
      record.state !== A2ATaskState.INPUT_REQUIRED) {
      return;
    }
    const callback: (() => void) | undefined = record.cancelCallback;
    record.cancelCallback = undefined;
    record.timeoutCallback = undefined;
    record.timeoutId = undefined;
    record.pendingInputDeadlineMs = 0;
    record.executionDeadlineMs = 0;
    record.state = A2ATaskState.FAILED;
    record.updatedAt = this.clock();
    if (callback !== undefined) {
      try {
        callback();
      } catch (_error) {
      }
    }
  }

  private releaseTimer(record: AgentTaskRecord): void {
    const timeoutId: number | undefined = record.timeoutId;
    if (timeoutId !== undefined) {
      this.scheduler.cancel(timeoutId);
      record.timeoutId = undefined;
    }
  }

  private evictOldestTerminal(): void {
    let oldestId: string = '';
    let oldestAt: number = Number.MAX_SAFE_INTEGER;
    for (const record of this.tasks.values()) {
      if (this.stateMachine.isTerminal(record.state) && record.updatedAt < oldestAt) {
        oldestId = record.taskId;
        oldestAt = record.updatedAt;
      }
    }
    if (oldestId.length > 0) {
      this.tasks.delete(oldestId);
    }
  }
}
