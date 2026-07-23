import { describe, expect, it } from '@ohos/hypium';
import { Scheduler } from '../main/ets/common/Scheduler';
import { A2ATaskState } from '../main/ets/agent/a2a/A2AModels';
import { AgentTaskRegistry } from '../main/ets/agent/a2a/AgentTaskRegistry';

class RetainedTimer {
  readonly id: number;
  readonly callback: () => void;
  cancelled: boolean = false;

  constructor(id: number, callback: () => void) {
    this.id = id;
    this.callback = callback;
  }
}

class RetainedScheduler implements Scheduler {
  private nextId: number = 1;
  readonly timers: RetainedTimer[] = [];

  schedule(_delayMs: number, callback: () => void): number {
    const timer: RetainedTimer = new RetainedTimer(this.nextId, callback);
    this.nextId += 1;
    this.timers.push(timer);
    return timer.id;
  }

  cancel(timerId: number): void {
    const timer: RetainedTimer | undefined = this.timer(timerId);
    if (timer !== undefined) {
      timer.cancelled = true;
    }
  }

  fireEvenIfCancelled(timerId: number): void {
    this.timer(timerId)?.callback();
  }

  private timer(timerId: number): RetainedTimer | undefined {
    return this.timers.find((timer: RetainedTimer): boolean => timer.id === timerId);
  }
}

export default function a2aTaskExecutionGenerationTest(): void {
  describe('A2ATaskExecutionGeneration', () => {
    it('invalidates the first execution callback and arms a full resumed generation', 0, () => {
      let now: number = 1000;
      let firstTimeouts: number = 0;
      let secondTimeouts: number = 0;
      const scheduler: RetainedScheduler = new RetainedScheduler();
      const registry: AgentTaskRegistry =
        new AgentTaskRegistry((): number => now, 1000, 8, 50, scheduler, 500);
      registry.create('connection-1', 'ctx-1', 'task-1', 'internal-1',
        (): void => {}, (): void => { firstTimeouts++; }, '原始问题');
      registry.transition('task-1', A2ATaskState.WORKING);
      registry.suspendForInput(
        'task-1', 'REMOTE_ONLY', 'LOCAL_ONLY', 'REMOTE_CHANNEL_UNAVAILABLE', 'LOCAL_FALLBACK');
      expect(scheduler.timers[0].cancelled).assertTrue();
      now += 200;
      const generation: number = registry.resume('task-1', (): void => { secondTimeouts++; });
      expect(generation).assertEqual(2);
      expect(registry.find('task-1')?.executionDeadlineMs).assertEqual(1250);

      scheduler.fireEvenIfCancelled(1);
      expect(firstTimeouts).assertEqual(0);
      expect(registry.find('task-1')?.state).assertEqual(A2ATaskState.WORKING);
      scheduler.fireEvenIfCancelled(3);
      expect(secondTimeouts).assertEqual(1);
      expect(registry.find('task-1')?.state).assertEqual(A2ATaskState.FAILED);
    });
  });
}
