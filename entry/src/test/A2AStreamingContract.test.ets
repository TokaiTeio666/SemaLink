import { describe, expect, it } from '@ohos/hypium';
import { A2AMetadata, A2ATaskState } from '../main/ets/agent/a2a/A2AModels';
import { A2AResponseFactory } from '../main/ets/agent/a2a/A2AResponseFactory';

function record(json: string): Record<string, Object> {
  return JSON.parse(json) as Record<string, Object>;
}

export default function a2aStreamingContractTest(): void {
  describe('A2AStreamingContract', () => {
    const metadata: A2AMetadata = new A2AMetadata('trace-1', 'agent-1');
    const factory: A2AResponseFactory = new A2AResponseFactory();

    it('emits lastChunk artifact then a standalone completed status frame with stable ids', 0, () => {
      const artifactEnvelope: Record<string, Object> = record(
        factory.artifactUpdate(7, 'ctx-1', 'task-1', 'artifact-1', '回答', false, true, metadata));
      const artifactResult: Record<string, Object> = artifactEnvelope['result'] as Record<string, Object>;
      const update: Record<string, Object> = artifactResult['artifactUpdate'] as Record<string, Object>;
      const artifact: Record<string, Object> = update['artifact'] as Record<string, Object>;
      expect(artifactEnvelope['id'] as number).assertEqual(7);
      expect(update['taskId'] as string).assertEqual('task-1');
      expect(update['contextId'] as string).assertEqual('ctx-1');
      expect(update['append'] as boolean).assertFalse();
      expect(update['lastChunk'] as boolean).assertTrue();
      expect(artifact['artifactId'] as string).assertEqual('artifact-1');

      const finalEnvelope: Record<string, Object> = record(
        factory.completedStatus(7, 'ctx-1', 'task-1', metadata));
      const finalResult: Record<string, Object> = finalEnvelope['result'] as Record<string, Object>;
      const finalUpdate: Record<string, Object> = finalResult['statusUpdate'] as Record<string, Object>;
      const finalStatus: Record<string, Object> = finalUpdate['status'] as Record<string, Object>;
      expect(finalStatus['state'] as string).assertEqual(A2ATaskState.COMPLETED);
      expect(typeof finalUpdate['final']).assertEqual('undefined');
    });
  });
}
