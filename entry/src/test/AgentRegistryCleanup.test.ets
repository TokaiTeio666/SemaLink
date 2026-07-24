import { describe, expect, it } from '@ohos/hypium';
import { AppError } from '../main/ets/common/AppError';
import { A2ATaskState } from '../main/ets/agent/a2a/A2AModels';
import { AgentTaskRegistry } from '../main/ets/agent/a2a/AgentTaskRegistry';

export default function agentRegistryCleanupTest(): void {
  describe('AgentRegistryCleanup', () => {
    it('enforces capacity and expires terminal records by injected clock', 0, () => {
      let now: number = 1000;
      const registry: AgentTaskRegistry = new AgentTaskRegistry((): number => now, 100, 1, 1000);
      registry.create('connection-1', 'ctx-1', 'task-1', 'internal-1', (): void => {});
      let capacityCode: string = '';
      try {
        registry.create('connection-1', 'ctx-1', 'task-2', 'internal-2', (): void => {});
      } catch (error) {
        capacityCode = (error as AppError).code;
      }
      expect(capacityCode).assertEqual('E_A2A_TASK_CAPACITY');
      registry.transition('task-1', A2ATaskState.WORKING);
      registry.transition('task-1', A2ATaskState.COMPLETED);
      now += 100;
      registry.cleanup();
      registry.cleanup();
      expect(registry.find('task-1') === undefined).assertTrue();
      registry.create('connection-1', 'ctx-1', 'task-2', 'internal-2', (): void => {});
      expect(registry.find('task-2') !== undefined).assertTrue();
    });

    it('evicts the oldest terminal record before rejecting healthy traffic', 0, () => {
      let now: number = 1000;
      const registry: AgentTaskRegistry = new AgentTaskRegistry((): number => now, 60000, 1, 1000);
      registry.create('connection-1', 'ctx-1', 'task-1', 'internal-1', (): void => {});
      registry.transition('task-1', A2ATaskState.WORKING);
      registry.transition('task-1', A2ATaskState.COMPLETED);
      now += 1;
      registry.create('connection-1', 'ctx-2', 'task-2', 'internal-2', (): void => {});
      expect(registry.find('task-1') === undefined).assertTrue();
      expect(registry.find('task-2') !== undefined).assertTrue();
    });
  });
}
