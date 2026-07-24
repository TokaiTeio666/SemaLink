import { AppError, ErrorStage } from '../../common/AppError';
import { SequenceIdGenerator } from '../../common/IdGenerator';

class AgentSessionRecord {
  readonly connectionId: string;
  readonly contextId: string;
  readonly createdAt: number;
  updatedAt: number;
  valid: boolean = true;

  constructor(connectionId: string, contextId: string, now: number) {
    this.connectionId = connectionId;
    this.contextId = contextId;
    this.createdAt = now;
    this.updatedAt = now;
  }
}

export class AgentSessionRegistry {
  private readonly sessions: Map<string, AgentSessionRecord> = new Map<string, AgentSessionRecord>();
  private readonly ids: SequenceIdGenerator;
  private readonly clock: () => number;
  private readonly ttlMs: number;
  private readonly maxSessions: number;

  constructor(ids: SequenceIdGenerator, clock: () => number = (): number => Date.now(),
    ttlMs: number = 30 * 60 * 1000, maxSessions: number = 64) {
    this.ids = ids;
    this.clock = clock;
    this.ttlMs = ttlMs;
    this.maxSessions = maxSessions;
  }

  resolve(connectionId: string, contextId: string | undefined, protectedContexts: string[] = []): string {
    this.cleanup();
    if (contextId === undefined) {
      return this.create(connectionId, protectedContexts);
    }
    const record: AgentSessionRecord | undefined = this.sessions.get(contextId);
    if (record === undefined || !record.valid || record.connectionId !== connectionId) {
      throw new AppError('E_A2A_CONTEXT_INVALID', 'Context is invalid', ErrorStage.LIFECYCLE, true);
    }
    record.updatedAt = this.clock();
    return record.contextId;
  }

  isValid(contextId: string): boolean {
    this.cleanup();
    const record: AgentSessionRecord | undefined = this.sessions.get(contextId);
    return record !== undefined && record.valid;
  }

  invalidate(contextId: string): void {
    const record: AgentSessionRecord | undefined = this.sessions.get(contextId);
    if (record !== undefined) {
      record.valid = false;
    }
  }

  invalidateConnection(connectionId: string): void {
    for (const record of this.sessions.values()) {
      if (record.connectionId === connectionId) {
        record.valid = false;
      }
    }
    this.cleanup();
  }

  cleanup(): void {
    const now: number = this.clock();
    const ids: string[] = Array.from(this.sessions.keys());
    for (const id of ids) {
      const record: AgentSessionRecord | undefined = this.sessions.get(id);
      if (record !== undefined && (!record.valid || now - record.updatedAt >= this.ttlMs)) {
        this.sessions.delete(id);
      }
    }
  }

  private create(connectionId: string, protectedContexts: string[]): string {
    if (this.sessions.size >= this.maxSessions) {
      let oldestId: string = '';
      let oldestAt: number = Number.MAX_SAFE_INTEGER;
      for (const record of this.sessions.values()) {
        if (protectedContexts.indexOf(record.contextId) < 0 && record.updatedAt < oldestAt) {
          oldestId = record.contextId;
          oldestAt = record.updatedAt;
        }
      }
      if (oldestId.length === 0) {
        throw new AppError('E_A2A_SESSION_CAPACITY', 'Session registry capacity reached', ErrorStage.LIFECYCLE, true);
      }
      this.sessions.delete(oldestId);
    }
    const contextId: string = this.ids.next('agent-context');
    this.sessions.set(contextId, new AgentSessionRecord(connectionId, contextId, this.clock()));
    return contextId;
  }
}
