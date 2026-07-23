import { describe, expect, it } from '@ohos/hypium';
import { A2ATaskState } from '../main/ets/agent/a2a/A2AModels';
import { AgentTaskRecord, AgentTaskRegistry } from '../main/ets/agent/a2a/AgentTaskRegistry';

export default function agentTaskRegistryTest(): void {
  describe('AgentTaskRegistry', () => {
    it('keeps concurrent tasks isolated and releases terminal cancellation', 0, () => {
      let cancelledOne: boolean = false;
      let cancelledTwo: boolean = false;
      const registry: AgentTaskRegistry = new AgentTaskRegistry((): number => 1000, 60000);
      registry.create('connection-1', 'ctx-1', 'task-1', 'internal-1', (): void => { cancelledOne = true; });
      registry.create('connection-2', 'ctx-2', 'task-2', 'internal-2', (): void => { cancelledTwo = true; });
      registry.transition('task-1', A2ATaskState.WORKING);
      registry.cancel('task-1');
      const first: AgentTaskRecord | undefined = registry.find('task-1');
      const second: AgentTaskRecord | undefined = registry.find('task-2');
      expect(cancelledOne).assertTrue();
      expect(cancelledTwo).assertFalse();
      expect(first?.state).assertEqual(A2ATaskState.CANCELLED);
      expect(second?.state).assertEqual(A2ATaskState.SUBMITTED);
    });

    it('cancels only active tasks owned by a disconnected connection', 0, () => {
      let cancelled: number = 0;
      const registry: AgentTaskRegistry = new AgentTaskRegistry((): number => 1000, 60000);
      registry.create('connection-1', 'ctx-1', 'task-1', 'internal-1', (): void => { cancelled++; });
      registry.create('connection-2', 'ctx-2', 'task-2', 'internal-2', (): void => { cancelled++; });
      registry.cancelConnection('connection-1');
      expect(cancelled).assertEqual(1);
      expect(registry.find('task-1')?.state).assertEqual(A2ATaskState.CANCELLED);
      expect(registry.find('task-2')?.state).assertEqual(A2ATaskState.SUBMITTED);
    });

    it('rejects duplicate task ids and terminal revival', 0, () => {
      const registry: AgentTaskRegistry = new AgentTaskRegistry((): number => 1000, 60000);
      registry.create('connection-1', 'ctx-1', 'task-1', 'internal-1', (): void => {});
      let duplicateRejected: boolean = false;
      try {
        registry.create('connection-1', 'ctx-1', 'task-1', 'internal-2', (): void => {});
      } catch (_error) {
        duplicateRejected = true;
      }
      registry.transition('task-1', A2ATaskState.WORKING);
      registry.transition('task-1', A2ATaskState.COMPLETED);
      expect(duplicateRejected).assertTrue();
      expect(registry.transition('task-1', A2ATaskState.WORKING)).assertFalse();
    });
  });
}
