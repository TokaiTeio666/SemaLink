import { describe, expect, it } from '@ohos/hypium';
import { A2AMetadata, A2ATaskState } from '../main/ets/agent/a2a/A2AModels';
import { A2AResponseFactory } from '../main/ets/agent/a2a/A2AResponseFactory';

function raw(value: string): Record<string, Object> {
  return JSON.parse(value) as Record<string, Object>;
}

export default function a2aResponseFactoryTest(): void {
  describe('A2AResponseFactory', () => {
    const factory: A2AResponseFactory = new A2AResponseFactory();
    const metadata: A2AMetadata = new A2AMetadata('trace-001', 'semalink_knowledge_agent');

    it('creates submitted first frame with context and task', 0, () => {
      const envelope: Record<string, Object> = raw(factory.submitted('req-1', 'ctx-1', 'task-1', metadata));
      const result: Record<string, Object> = envelope['result'] as Record<string, Object>;
      const task: Record<string, Object> = result['task'] as Record<string, Object>;
      const status: Record<string, Object> = task['status'] as Record<string, Object>;
      expect(envelope['jsonrpc'] as string).assertEqual('2.0');
      expect(task['contextId'] as string).assertEqual('ctx-1');
      expect(task['id'] as string).assertEqual('task-1');
      expect(status['state'] as string).assertEqual(A2ATaskState.SUBMITTED);
    });

    it('creates working status update', 0, () => {
      const envelope: Record<string, Object> = raw(factory.working('req-1', 'ctx-1', 'task-1', metadata));
      const result: Record<string, Object> = envelope['result'] as Record<string, Object>;
      const update: Record<string, Object> = result['statusUpdate'] as Record<string, Object>;
      const status: Record<string, Object> = update['status'] as Record<string, Object>;
      expect(status['state'] as string).assertEqual(A2ATaskState.WORKING);
    });

    it('creates completed task with artifact text part', 0, () => {
      const envelope: Record<string, Object> = raw(factory.completed(
        'req-1', 'ctx-1', 'task-1', 'artifact-1', '真实 Evidence 回答', metadata));
      const result: Record<string, Object> = envelope['result'] as Record<string, Object>;
      const task: Record<string, Object> = result['task'] as Record<string, Object>;
      const artifacts: Object[] = task['artifacts'] as Object[];
      const artifact: Record<string, Object> = artifacts[0] as Record<string, Object>;
      const parts: Object[] = artifact['parts'] as Object[];
      const part: Record<string, Object> = parts[0] as Record<string, Object>;
      expect(part['text'] as string).assertEqual('真实 Evidence 回答');
      expect(part['mediaType'] as string).assertEqual('text/plain');
    });

    it('uses canonical CANCELLED spelling in cancellation response', 0, () => {
      const envelope: Record<string, Object> = raw(factory.cancelled('req-1', 'ctx-1', 'task-1', metadata));
      const result: Record<string, Object> = envelope['result'] as Record<string, Object>;
      const status: Record<string, Object> = result['status'] as Record<string, Object>;
      expect(status['state'] as string).assertEqual('TASK_STATE_CANCELLED');
      const responseMetadata: Record<string, Object> = result['metadata'] as Record<string, Object>;
      expect(responseMetadata['traceId'] as string).assertEqual('trace-001');
    });

    it('creates JSON-RPC context invalid error', 0, () => {
      const envelope: Record<string, Object> = raw(factory.error('req-1', 99911222, 'Context invalid'));
      const error: Record<string, Object> = envelope['error'] as Record<string, Object>;
      expect(error['code'] as number).assertEqual(99911222);
    });
  });
}
