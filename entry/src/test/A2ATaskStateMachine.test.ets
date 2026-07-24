import { describe, expect, it } from '@ohos/hypium';
import { A2ATaskState } from '../main/ets/agent/a2a/A2AModels';
import { A2ATaskStateMachine } from '../main/ets/agent/a2a/A2ATaskStateMachine';

export default function a2aTaskStateMachineTest(): void {
  describe('A2ATaskStateMachine', () => {
    it('accepts required active transitions', 0, () => {
      const machine: A2ATaskStateMachine = new A2ATaskStateMachine();
      expect(machine.canTransition(A2ATaskState.SUBMITTED, A2ATaskState.WORKING)).assertTrue();
      expect(machine.canTransition(A2ATaskState.WORKING, A2ATaskState.INPUT_REQUIRED)).assertTrue();
      expect(machine.canTransition(A2ATaskState.INPUT_REQUIRED, A2ATaskState.WORKING)).assertTrue();
      expect(machine.canTransition(A2ATaskState.WORKING, A2ATaskState.COMPLETED)).assertTrue();
      expect(machine.canTransition(A2ATaskState.WORKING, A2ATaskState.FAILED)).assertTrue();
      expect(machine.canTransition(A2ATaskState.WORKING, A2ATaskState.CANCELLED)).assertTrue();
    });

    it('rejects illegal jumps and terminal revival', 0, () => {
      const machine: A2ATaskStateMachine = new A2ATaskStateMachine();
      expect(machine.canTransition(A2ATaskState.SUBMITTED, A2ATaskState.COMPLETED)).assertFalse();
      expect(machine.canTransition(A2ATaskState.COMPLETED, A2ATaskState.WORKING)).assertFalse();
      expect(machine.canTransition(A2ATaskState.CANCELLED, A2ATaskState.WORKING)).assertFalse();
      expect(machine.canTransition(A2ATaskState.FAILED, A2ATaskState.WORKING)).assertFalse();
    });
  });
}
