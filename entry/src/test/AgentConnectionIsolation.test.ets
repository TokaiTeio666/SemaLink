import { describe, expect, it } from '@ohos/hypium';
import { SequenceIdGenerator } from '../main/ets/common/IdGenerator';
import { A2ACommandCodec } from '../main/ets/agent/a2a/A2ACommandCodec';
import { A2AResponseFactory } from '../main/ets/agent/a2a/A2AResponseFactory';
import { AgentSessionRegistry } from '../main/ets/agent/a2a/AgentSessionRegistry';
import { AgentTaskRegistry } from '../main/ets/agent/a2a/AgentTaskRegistry';
import { AgentDataSender, SemaLinkAgentAbilityOrchestrator } from '../main/ets/agent/SemaLinkAgentAbilityOrchestrator';
import { SemaLinkAgentExecutor } from '../main/ets/agent/SemaLinkAgentExecutor';
import { SemaLinkAgentRequest, SemaLinkAgentResponse }
  from '../main/ets/agent/SemaLinkAgentModels';
import { AgentQueryScope } from '../main/ets/agent/query/AgentQueryModels';

const REQUEST_A: string = '{"jsonrpc":"2.0","id":"req-a","method":"message/stream","params":{"message":{"messageId":"msg-a","role":"ROLE_USER","parts":[{"text":"其他设备知识"}]},"metadata":{"traceId":"trace-a","agentId":"agent-1"}}}';

class IsolationSender implements AgentDataSender {
  readonly frames: string[] = [];
  send(data: string): void { this.frames.push(data); }
}

class WaitingForInputExecutor implements SemaLinkAgentExecutor {
  cancellations: number = 0;
  execute(_request: SemaLinkAgentRequest): Promise<SemaLinkAgentResponse> {
    return Promise.resolve(SemaLinkAgentResponse.inputRequired(
      '是否改为本机查询？',
      AgentQueryScope.REMOTE_ONLY,
      AgentQueryScope.LOCAL_ONLY,
      'REMOTE_CHANNEL_UNAVAILABLE',
      'LOCAL_FALLBACK'
    ));
  }
  cancel(_taskId: string): void { this.cancellations++; }
}

export default function agentConnectionIsolationTest(): void {
  describe('AgentConnectionIsolation', () => {
    it('rejects cross-connection follow-up and cancellation while allowing the owner', 0, async () => {
      const ids: SequenceIdGenerator = new SequenceIdGenerator((): number => 3000);
      const executor: WaitingForInputExecutor = new WaitingForInputExecutor();
      const orchestrator: SemaLinkAgentAbilityOrchestrator = new SemaLinkAgentAbilityOrchestrator(
        new A2ACommandCodec(), new A2AResponseFactory(),
        new AgentSessionRegistry(ids, (): number => 3000, 60000, 8),
        new AgentTaskRegistry((): number => 3000, 60000), ids, executor);
      const owner: IsolationSender = new IsolationSender();
      await orchestrator.handleData('connection-a', owner, REQUEST_A);
      const submitted: Record<string, Object> = JSON.parse(owner.frames[0]) as Record<string, Object>;
      const task: Record<string, Object> =
        ((submitted['result'] as Record<string, Object>)['task']) as Record<string, Object>;
      const taskId: string = task['id'] as string;
      const contextId: string = task['contextId'] as string;
      const followUp: string = '{"jsonrpc":"2.0","id":"follow","method":"message/stream","params":{"message":{' +
        '"messageId":"msg-b","taskId":"' + taskId + '","contextId":"' + contextId + '",' +
        '"role":"ROLE_USER","parts":[{"text":"改为本机查询"}]},' +
        '"metadata":{"traceId":"trace-b","agentId":"agent-1"}}}';
      const intruder: IsolationSender = new IsolationSender();
      const contextOnly: string = '{"jsonrpc":"2.0","id":"context-only","method":"message/stream",' +
        '"params":{"message":{"messageId":"msg-context","contextId":"' + contextId + '",' +
        '"role":"ROLE_USER","parts":[{"text":"新问题"}]},' +
        '"metadata":{"traceId":"trace-context","agentId":"agent-1"}}}';
      await orchestrator.handleData('connection-b', intruder, contextOnly);
      const contextErrorEnvelope: Record<string, Object> = JSON.parse(intruder.frames[0]) as Record<string, Object>;
      expect(((contextErrorEnvelope['error'] as Record<string, Object>)['code']) as number).assertEqual(99911222);
      await orchestrator.handleData('connection-b', intruder, followUp);
      const followErrorEnvelope: Record<string, Object> = JSON.parse(intruder.frames[1]) as Record<string, Object>;
      const followError: Record<string, Object> = followErrorEnvelope['error'] as Record<string, Object>;
      expect(followError['code'] as number).assertEqual(-32001);
      const cancel: string = '{"jsonrpc":"2.0","id":"cancel","method":"tasks/cancel","params":{"id":"' +
        taskId + '","metadata":{"traceId":"trace-c","agentId":"agent-1"}}}';
      await orchestrator.handleData('connection-b', intruder, cancel);
      expect(executor.cancellations).assertEqual(0);
      await orchestrator.handleData('connection-a', owner, cancel);
      expect(executor.cancellations).assertEqual(1);
      expect(owner.frames[owner.frames.length - 1].includes('TASK_STATE_CANCELLED')).assertTrue();
    });
  });
}
