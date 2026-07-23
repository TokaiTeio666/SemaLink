import { describe, expect, it } from '@ohos/hypium';
import { A2AMetadata, A2ATaskState, normalizeA2ATaskState } from '../main/ets/agent/a2a/A2AModels';
import { A2AResponseFactory } from '../main/ets/agent/a2a/A2AResponseFactory';

export default function a2aCancelSpellingTest(): void {
  describe('A2ACancelSpelling', () => {
    it('outputs canonical CANCELLED and normalizes legacy input only at boundary', 0, () => {
      const envelope: Record<string, Object> = JSON.parse(
        new A2AResponseFactory().cancelled(
          'req-1', 'ctx-1', 'task-1', new A2AMetadata('trace-1', 'agent-1'))) as Record<string, Object>;
      const result: Record<string, Object> = envelope['result'] as Record<string, Object>;
      const status: Record<string, Object> = result['status'] as Record<string, Object>;
      expect(status['state'] as string).assertEqual('TASK_STATE_CANCELLED');
      expect(normalizeA2ATaskState('TASK_STATE_CANCELLED')).assertEqual(A2ATaskState.CANCELLED);
      expect(normalizeA2ATaskState('TASK_STATE_CANCELED')).assertEqual(A2ATaskState.CANCELLED);
    });

    it('rejects unknown cancellation spelling', 0, () => {
      let rejected: boolean = false;
      try {
        normalizeA2ATaskState('TASK_STATE_CANCELD');
      } catch (_error) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });
  });
}
