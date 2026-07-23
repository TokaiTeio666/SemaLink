import { EvidenceUnit, TaskRequest } from '../../main/ets/contracts/semantic/SemanticModels';
import {
  CrossDeviceAvailability,
  CrossDeviceKnowledgePort,
  CrossDeviceQueryResult
} from '../../main/ets/agent/query/CrossDeviceKnowledgePort';
import { Scheduler, SystemScheduler } from '../../main/ets/common/Scheduler';

export class FakeCrossDeviceKnowledgePort implements CrossDeviceKnowledgePort {
  available: boolean = true;
  evidence: EvidenceUnit[] = [];
  fail: boolean = false;
  throwControlledError: boolean = false;
  timedOut: boolean = false;
  partialFailures: number = 0;
  delayMs: number = 0;
  cancelledTaskIds: string[] = [];
  searchCount: number = 0;
  private readonly cancelled: Set<string> = new Set<string>();
  private readonly scheduler: Scheduler;

  constructor(scheduler: Scheduler = new SystemScheduler()) {
    this.scheduler = scheduler;
  }

  availability(): CrossDeviceAvailability {
    return new CrossDeviceAvailability(this.available, this.available ? 'AVAILABLE' : 'UNAVAILABLE');
  }

  async search(request: TaskRequest): Promise<CrossDeviceQueryResult> {
    this.searchCount += 1;
    if (this.delayMs > 0) {
      await new Promise<void>((resolve: () => void): void => {
        this.scheduler.schedule(this.delayMs, resolve);
      });
    }
    if (this.cancelled.has(request.taskId)) {
      return CrossDeviceQueryResult.cancelledResult();
    }
    if (this.throwControlledError) {
      throw new Error('CONTROLLED_FAKE_REMOTE_ERROR');
    }
    if (this.timedOut) {
      return CrossDeviceQueryResult.timeout();
    }
    if (this.fail) {
      return CrossDeviceQueryResult.failed('REMOTE_ERROR');
    }
    if (this.partialFailures > 0) {
      return new CrossDeviceQueryResult(true, this.evidence, this.partialFailures, false, false,
        'REMOTE_PARTIAL_FAILURE');
    }
    return CrossDeviceQueryResult.success(this.evidence);
  }

  cancel(internalTaskId: string): void {
    this.cancelledTaskIds.push(internalTaskId);
    this.cancelled.add(internalTaskId);
  }
}
