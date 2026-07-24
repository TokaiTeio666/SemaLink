import { describe, expect, it } from '@ohos/hypium';
import { A2AMetadata, A2ATaskState } from '../main/ets/agent/a2a/A2AModels';
import { A2AResponseFactory } from '../main/ets/agent/a2a/A2AResponseFactory';

export default function a2aNonStreamingContractTest(): void {
  describe('A2AAuxiliaryCompleteTaskResponse', () => {
    it('encodes an unconnected complete Task helper without claiming message/send support', 0, () => {
      const json: string = new A2AResponseFactory().completed(
        'req-1', 'ctx-1', 'task-1', 'artifact-1', '回答', new A2AMetadata('trace-1', 'agent-1'));
      const envelope: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
      const result: Record<string, Object> = envelope['result'] as Record<string, Object>;
      const task: Record<string, Object> = result['task'] as Record<string, Object>;
      const status: Record<string, Object> = task['status'] as Record<string, Object>;
      const artifacts: Object[] = task['artifacts'] as Object[];
      expect(task['id'] as string).assertEqual('task-1');
      expect(task['contextId'] as string).assertEqual('ctx-1');
      expect(status['state'] as string).assertEqual(A2ATaskState.COMPLETED);
      expect(artifacts.length).assertEqual(1);
    });
  });
}
