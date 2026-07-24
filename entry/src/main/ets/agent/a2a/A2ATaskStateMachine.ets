import { A2ATaskState } from './A2AModels';

export class A2ATaskStateMachine {
  canTransition(from: A2ATaskState, to: A2ATaskState): boolean {
    if (from === A2ATaskState.SUBMITTED) {
      return to === A2ATaskState.WORKING || to === A2ATaskState.CANCELLED || to === A2ATaskState.FAILED;
    }
    if (from === A2ATaskState.WORKING) {
      return to === A2ATaskState.INPUT_REQUIRED || to === A2ATaskState.COMPLETED ||
        to === A2ATaskState.CANCELLED || to === A2ATaskState.FAILED;
    }
    if (from === A2ATaskState.INPUT_REQUIRED) {
      return to === A2ATaskState.WORKING || to === A2ATaskState.CANCELLED || to === A2ATaskState.FAILED;
    }
    return false;
  }

  isTerminal(state: A2ATaskState): boolean {
    return state === A2ATaskState.COMPLETED || state === A2ATaskState.CANCELLED || state === A2ATaskState.FAILED;
  }
}
