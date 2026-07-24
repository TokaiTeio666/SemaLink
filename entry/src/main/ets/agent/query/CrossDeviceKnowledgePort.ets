import { EvidenceUnit, TaskRequest } from '../../contracts/semantic/SemanticModels';

export class CrossDeviceAvailability {
  readonly available: boolean;
  readonly reason: string;

  constructor(available: boolean, reason: string) {
    this.available = available;
    this.reason = reason;
  }
}

export class CrossDeviceQueryResult {
  readonly executed: boolean;
  readonly evidence: EvidenceUnit[];
  readonly failedSources: number;
  readonly timedOut: boolean;
  readonly cancelled: boolean;
  readonly reason: string;

  constructor(executed: boolean, evidence: EvidenceUnit[], failedSources: number,
    timedOut: boolean, cancelled: boolean, reason: string) {
    this.executed = executed;
    this.evidence = evidence;
    this.failedSources = failedSources;
    this.timedOut = timedOut;
    this.cancelled = cancelled;
    this.reason = reason;
  }

  static success(evidence: EvidenceUnit[]): CrossDeviceQueryResult {
    return new CrossDeviceQueryResult(true, evidence, 0, false, false, 'REMOTE_OK');
  }

  static failed(reason: string): CrossDeviceQueryResult {
    return new CrossDeviceQueryResult(true, [], 1, false, false, reason);
  }

  static timeout(): CrossDeviceQueryResult {
    return new CrossDeviceQueryResult(true, [], 1, true, false, 'REMOTE_TIMEOUT');
  }

  static cancelledResult(): CrossDeviceQueryResult {
    return new CrossDeviceQueryResult(true, [], 0, false, true, 'REMOTE_CANCELLED');
  }
}

export interface CrossDeviceKnowledgePort {
  availability(): CrossDeviceAvailability;
  search(request: TaskRequest): Promise<CrossDeviceQueryResult>;
  cancel(internalTaskId: string): void;
}
