import { describe, expect, it } from '@ohos/hypium';
import { A2ATaskState } from '../main/ets/agent/a2a/A2AModels';
import { AgentTaskRegistry } from '../main/ets/agent/a2a/AgentTaskRegistry';
import { FakeScheduler } from './support/FakeScheduler';

export default function agentLongRunningTaskTimeoutTest(): void {
  describe('AgentLongRunningTaskTimeout', () => {
    it('cancels and fails an active task at the hard deadline exactly once', 0, () => {
      let now: number = 1000;
      let cancellations: number = 0;
      let terminalNotifications: number = 0;
      const scheduler: FakeScheduler = new FakeScheduler();
      const registry: AgentTaskRegistry = new AgentTaskRegistry((): number => now, 1000, 8, 50, scheduler);
      registry.create('connection-1', 'ctx-1', 'task-1', 'internal-1',
        (): void => { cancellations++; }, (): void => { terminalNotifications++; });
      registry.transition('task-1', A2ATaskState.WORKING);
      now += 50;
      scheduler.advanceBy(50);
      registry.cleanup();
      expect(cancellations).assertEqual(1);
      expect(terminalNotifications).assertEqual(1);
      expect(scheduler.pendingCount()).assertEqual(0);
      expect(registry.find('task-1')?.state).assertEqual(A2ATaskState.FAILED);
      expect(registry.transition('task-1', A2ATaskState.COMPLETED)).assertFalse();
    });
  });
}
