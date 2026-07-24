import { describe, expect, it } from '@ohos/hypium';
import { Scheduler } from '../main/ets/common/Scheduler';
import { A2ATaskState } from '../main/ets/agent/a2a/A2AModels';
import { AgentTaskRegistry } from '../main/ets/agent/a2a/AgentTaskRegistry';

class RaceScheduler implements Scheduler {
  callback?: () => void;
  schedule(_delayMs: number, callback: () => void): number {
    this.callback = callback;
    return 1;
  }
  cancel(_timerId: number): void {
  }
  fire(): void {
    this.callback?.();
  }
}

export default function a2aTerminalRaceTest(): void {
  describe('A2ATerminalRace', () => {
    it('allows completion to win once over timeout and cancellation', 0, () => {
      let cancels: number = 0;
      let timeouts: number = 0;
      const scheduler: RaceScheduler = new RaceScheduler();
      const registry: AgentTaskRegistry =
        new AgentTaskRegistry((): number => 1000, 60000, 8, 50, scheduler);
      const record = registry.create('connection-1', 'ctx-1', 'task-1', 'internal-1',
        (): void => { cancels++; }, (): void => { timeouts++; });
      registry.transition('task-1', A2ATaskState.WORKING);
      expect(registry.transitionIfCurrent(
        'task-1', record.executionGeneration, A2ATaskState.COMPLETED)).assertTrue();
      scheduler.fire();
      expect(registry.cancel('task-1')).assertFalse();
      expect(cancels).assertEqual(0);
      expect(timeouts).assertEqual(0);
      expect(registry.find('task-1')?.state).assertEqual(A2ATaskState.COMPLETED);
    });

    it('allows cancellation to win once over late completion', 0, () => {
      let cancels: number = 0;
      const registry: AgentTaskRegistry = new AgentTaskRegistry((): number => 1000, 60000);
      const record = registry.create('connection-1', 'ctx-1', 'task-1', 'internal-1',
        (): void => { cancels++; });
      registry.transition('task-1', A2ATaskState.WORKING);
      expect(registry.cancel('task-1')).assertTrue();
      expect(registry.transitionIfCurrent(
        'task-1', record.executionGeneration, A2ATaskState.COMPLETED)).assertFalse();
      expect(registry.cancel('task-1')).assertFalse();
      expect(cancels).assertEqual(1);
    });

    it('claims the CANCELLED terminal state before invoking a re-entrant cancel callback', 0, () => {
      let timeouts: number = 0;
      const scheduler: RaceScheduler = new RaceScheduler();
      const registry: AgentTaskRegistry =
        new AgentTaskRegistry((): number => 1000, 60000, 8, 50, scheduler);
      registry.create('connection-1', 'ctx-1', 'task-1', 'internal-1',
        (): void => { scheduler.fire(); }, (): void => { timeouts++; });
      registry.transition('task-1', A2ATaskState.WORKING);
      expect(registry.cancel('task-1')).assertTrue();
      expect(registry.find('task-1')?.state).assertEqual(A2ATaskState.CANCELLED);
      expect(timeouts).assertEqual(0);
    });

    it('claims the FAILED terminal state before invoking a re-entrant timeout cancel callback', 0, () => {
      let reentrantCancelWon: boolean = false;
      let timeouts: number = 0;
      const scheduler: RaceScheduler = new RaceScheduler();
      const registry: AgentTaskRegistry =
        new AgentTaskRegistry((): number => 1000, 60000, 8, 50, scheduler);
      registry.create('connection-1', 'ctx-1', 'task-1', 'internal-1',
        (): void => { reentrantCancelWon = registry.cancel('task-1'); },
        (): void => { timeouts++; });
      registry.transition('task-1', A2ATaskState.WORKING);
      scheduler.fire();
      expect(reentrantCancelWon).assertFalse();
      expect(registry.find('task-1')?.state).assertEqual(A2ATaskState.FAILED);
      expect(timeouts).assertEqual(1);
    });
  });
}
