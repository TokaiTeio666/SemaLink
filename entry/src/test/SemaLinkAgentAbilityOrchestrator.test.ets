import { describe, expect, it } from '@ohos/hypium';
import { SequenceIdGenerator } from '../main/ets/common/IdGenerator';
import { A2ACommandCodec } from '../main/ets/agent/a2a/A2ACommandCodec';
import { A2AResponseFactory } from '../main/ets/agent/a2a/A2AResponseFactory';
import { AgentSessionRegistry } from '../main/ets/agent/a2a/AgentSessionRegistry';
import { AgentTaskRegistry } from '../main/ets/agent/a2a/AgentTaskRegistry';
import { SemaLinkAgentExecutor } from '../main/ets/agent/SemaLinkAgentExecutor';
import { SemaLinkAgentRequest, SemaLinkAgentResponse } from '../main/ets/agent/SemaLinkAgentModels';
import {
  AgentDataSender,
  SemaLinkAgentAbilityOrchestrator
} from '../main/ets/agent/SemaLinkAgentAbilityOrchestrator';

const REQUEST: string = '{"jsonrpc":"2.0","id":"req-1","method":"message/stream","params":{"message":{"messageId":"msg-1","role":"ROLE_USER","parts":[{"text":"数据库","mediaType":"text/plain"}]},"metadata":{"traceId":"trace-1","agentId":"semalink_knowledge_agent"}}}';

class CapturingSender implements AgentDataSender {
  readonly frames: string[] = [];

  send(data: string): void {
    this.frames.push(data);
  }
}

class ImmediateExecutor implements SemaLinkAgentExecutor {
  cancelled: string[] = [];

  execute(_request: SemaLinkAgentRequest): Promise<SemaLinkAgentResponse> {
    return Promise.resolve(new SemaLinkAgentResponse('来自真实 Evidence 的回答'));
  }

  cancel(taskId: string): void {
    this.cancelled.push(taskId);
  }
}

class PendingExecutor implements SemaLinkAgentExecutor {
  cancelled: string[] = [];
  private resolvePending?: (value: SemaLinkAgentResponse) => void;

  execute(_request: SemaLinkAgentRequest): Promise<SemaLinkAgentResponse> {
    return new Promise<SemaLinkAgentResponse>((resolve: (value: SemaLinkAgentResponse) => void): void => {
      this.resolvePending = resolve;
    });
  }

  cancel(taskId: string): void {
    this.cancelled.push(taskId);
  }

  finish(): void {
    const resolve: ((value: SemaLinkAgentResponse) => void) | undefined = this.resolvePending;
    if (resolve !== undefined) {
      resolve(new SemaLinkAgentResponse('不应在取消后发送'));
    }
  }
}

class ThrowingExecutor implements SemaLinkAgentExecutor {
  execute(_request: SemaLinkAgentRequest): Promise<SemaLinkAgentResponse> {
    return Promise.reject(new Error('private executor detail'));
  }

  cancel(_taskId: string): void {
  }
}

class ThrowingSender implements AgentDataSender {
  send(_data: string): void {
    throw new Error('transport unavailable');
  }
}

function stateOf(frame: string): string {
  const envelope: Record<string, Object> = JSON.parse(frame) as Record<string, Object>;
  const result: Record<string, Object> = envelope['result'] as Record<string, Object>;
  const taskValue: Object | undefined = result['task'];
  if (taskValue !== undefined) {
    const task: Record<string, Object> = taskValue as Record<string, Object>;
    const status: Record<string, Object> = task['status'] as Record<string, Object>;
    return status['state'] as string;
  }
  const directStatus: Object | undefined = result['status'];
  if (directStatus !== undefined) {
    return (directStatus as Record<string, Object>)['state'] as string;
  }
  const update: Record<string, Object> = result['statusUpdate'] as Record<string, Object>;
  const status: Record<string, Object> = update['status'] as Record<string, Object>;
  return status['state'] as string;
}

function createOrchestrator(executor: SemaLinkAgentExecutor): SemaLinkAgentAbilityOrchestrator {
  const ids: SequenceIdGenerator = new SequenceIdGenerator((): number => 1000);
  return new SemaLinkAgentAbilityOrchestrator(
    new A2ACommandCodec(), new A2AResponseFactory(),
    new AgentSessionRegistry(ids, (): number => 1000, 60000, 8),
    new AgentTaskRegistry((): number => 1000, 60000), ids, executor);
}

export default function semaLinkAgentAbilityOrchestratorTest(): void {
  describe('SemaLinkAgentAbilityOrchestrator', () => {
    it('sends submitted, working, then completed artifact frames', 0, async () => {
      const sender: CapturingSender = new CapturingSender();
      await createOrchestrator(new ImmediateExecutor()).handleData('connection-1', sender, REQUEST);
      expect(sender.frames.length).assertEqual(4);
      expect(stateOf(sender.frames[0])).assertEqual('TASK_STATE_SUBMITTED');
      expect(stateOf(sender.frames[1])).assertEqual('TASK_STATE_WORKING');
      const artifactEnvelope: Record<string, Object> = JSON.parse(sender.frames[2]) as Record<string, Object>;
      const artifactResult: Record<string, Object> = artifactEnvelope['result'] as Record<string, Object>;
      const artifactUpdate: Record<string, Object> = artifactResult['artifactUpdate'] as Record<string, Object>;
      expect(artifactUpdate['lastChunk'] as boolean).assertTrue();
      expect(sender.frames[2].indexOf('来自真实 Evidence 的回答') >= 0).assertTrue();
      expect(stateOf(sender.frames[3])).assertEqual('TASK_STATE_COMPLETED');
      for (const frame of sender.frames) {
        expect((JSON.parse(frame) as Record<string, Object>)['jsonrpc'] as string).assertEqual('2.0');
      }
    });

    it('cancels the active executor task and does not revive it', 0, async () => {
      const executor: PendingExecutor = new PendingExecutor();
      const orchestrator: SemaLinkAgentAbilityOrchestrator = createOrchestrator(executor);
      const sender: CapturingSender = new CapturingSender();
      const running: Promise<void> = orchestrator.handleData('connection-1', sender, REQUEST);
      await Promise.resolve();
      const submitted: Record<string, Object> = JSON.parse(sender.frames[0]) as Record<string, Object>;
      const result: Record<string, Object> = submitted['result'] as Record<string, Object>;
      const task: Record<string, Object> = result['task'] as Record<string, Object>;
      const taskId: string = task['id'] as string;
      const cancel: string = '{"jsonrpc":"2.0","id":"cancel-1","method":"tasks/cancel","params":{"id":"' +
        taskId + '","metadata":{"traceId":"trace-cancel","agentId":"semalink_knowledge_agent"}}}';
      await orchestrator.handleData('connection-1', sender, cancel);
      expect(executor.cancelled.length).assertEqual(1);
      expect(stateOf(sender.frames[sender.frames.length - 1])).assertEqual('TASK_STATE_CANCELLED');
      executor.finish();
      await running;
      expect(stateOf(sender.frames[sender.frames.length - 1])).assertEqual('TASK_STATE_CANCELLED');
    });

    it('disconnect cancels only tasks for that connection', 0, async () => {
      const executor: PendingExecutor = new PendingExecutor();
      const orchestrator: SemaLinkAgentAbilityOrchestrator = createOrchestrator(executor);
      const sender: CapturingSender = new CapturingSender();
      const running: Promise<void> = orchestrator.handleData('connection-1', sender, REQUEST);
      await Promise.resolve();
      orchestrator.disconnect('connection-1');
      expect(executor.cancelled.length).assertEqual(1);
      executor.finish();
      await running;
    });

    it('returns a structured failed terminal frame without exposing executor details', 0, async () => {
      const sender: CapturingSender = new CapturingSender();
      await createOrchestrator(new ThrowingExecutor()).handleData('connection-1', sender, REQUEST);
      expect(stateOf(sender.frames[sender.frames.length - 1])).assertEqual('TASK_STATE_FAILED');
      expect(sender.frames[sender.frames.length - 1].includes('private executor detail')).assertFalse();
    });

    it('contains sender failures and malformed protocol input', 0, async () => {
      const orchestrator = createOrchestrator(new ImmediateExecutor());
      await orchestrator.handleData('connection-1', new ThrowingSender(), REQUEST);
      const sender = new CapturingSender();
      await orchestrator.handleData('connection-1', sender, '{bad-json');
      const envelope = JSON.parse(sender.frames[0]) as Record<string, Object>;
      const error = envelope['error'] as Record<string, Object>;
      expect(error['code'] as number).assertEqual(-32700);
      expect(envelope['id'] === null).assertTrue();
    });

    it('echoes a usable request id on protocol errors', 0, async () => {
      const sender: CapturingSender = new CapturingSender();
      const invalidMethod: string = REQUEST.replace('"id":"req-1"', '"id":7')
        .replace('message/stream', 'message/unknown');
      await createOrchestrator(new ImmediateExecutor()).handleData('connection-1', sender, invalidMethod);
      const envelope: Record<string, Object> = JSON.parse(sender.frames[0]) as Record<string, Object>;
      expect(envelope['id'] as number).assertEqual(7);
      expect((envelope['error'] as Record<string, Object>)['code'] as number).assertEqual(-32004);
    });
  });
}
