import { describe, expect, it } from '@ohos/hypium';
import { A2ATaskState } from '../main/ets/agent/a2a/A2AModels';
import { AgentTaskRegistry } from '../main/ets/agent/a2a/AgentTaskRegistry';
import { FakeScheduler } from './support/FakeScheduler';

export default function agentTaskCleanupTest(): void {
  describe('AgentTaskCleanup', () => {
    it('cleans pending-input timers, callbacks and terminal records idempotently', 0, () => {
      let now: number = 1000;
      let cancellations: number = 0;
      let executionTimeouts: number = 0;
      const scheduler: FakeScheduler = new FakeScheduler();
      const registry: AgentTaskRegistry =
        new AgentTaskRegistry((): number => now, 100, 8, 50, scheduler, 200);
      registry.create('connection-1', 'ctx-1', 'task-1', 'internal-1',
        (): void => { cancellations++; }, (): void => { executionTimeouts++; }, '原始问题');
      registry.transition('task-1', A2ATaskState.WORKING);
      registry.suspendForInput(
        'task-1', 'REMOTE_ONLY', 'LOCAL_ONLY', 'REMOTE_CHANNEL_UNAVAILABLE', 'LOCAL_FALLBACK');
      expect(scheduler.pendingCount()).assertEqual(1);
      expect(registry.find('task-1')?.timeoutCallback === undefined).assertTrue();
      now += 200;
      scheduler.advanceBy(200);
      registry.cleanup();
      registry.cleanup();
      expect(cancellations).assertEqual(1);
      expect(executionTimeouts).assertEqual(0);
      expect(scheduler.pendingCount()).assertEqual(0);
      expect(registry.find('task-1')?.state).assertEqual(A2ATaskState.FAILED);
      now += 100;
      registry.cleanup();
      registry.cleanup();
      expect(registry.find('task-1') === undefined).assertTrue();
    });
  });
}
