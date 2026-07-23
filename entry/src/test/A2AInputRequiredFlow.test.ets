import { describe, expect, it } from '@ohos/hypium';
import { SequenceIdGenerator } from '../main/ets/common/IdGenerator';
import { A2ACommandCodec } from '../main/ets/agent/a2a/A2ACommandCodec';
import { A2AResponseFactory } from '../main/ets/agent/a2a/A2AResponseFactory';
import { AgentSessionRegistry } from '../main/ets/agent/a2a/AgentSessionRegistry';
import { AgentTaskRegistry } from '../main/ets/agent/a2a/AgentTaskRegistry';
import { AgentDataSender, SemaLinkAgentAbilityOrchestrator } from '../main/ets/agent/SemaLinkAgentAbilityOrchestrator';
import { SemaLinkAgentExecutor } from '../main/ets/agent/SemaLinkAgentExecutor';
import {
  SemaLinkAgentRequest,
  SemaLinkAgentResponse
} from '../main/ets/agent/SemaLinkAgentModels';
import { AgentQueryScope } from '../main/ets/agent/query/AgentQueryModels';

const FIRST: string = '{"jsonrpc":"2.0","id":"req-1","method":"message/stream","params":{"message":{"messageId":"msg-1","role":"ROLE_USER","parts":[{"text":"只查询其他设备知识"}]},"metadata":{"traceId":"trace-1","agentId":"agent-1"}}}';

class FlowSender implements AgentDataSender {
  readonly frames: string[] = [];
  send(data: string): void { this.frames.push(data); }
}

class InputThenCompleteExecutor implements SemaLinkAgentExecutor {
  calls: number = 0;
  execute(_request: SemaLinkAgentRequest): Promise<SemaLinkAgentResponse> {
    this.calls++;
    if (this.calls === 1) {
      return Promise.resolve(SemaLinkAgentResponse.inputRequired(
        '跨设备通道当前不可用，是否改为本机查询？',
        AgentQueryScope.REMOTE_ONLY,
        AgentQueryScope.LOCAL_ONLY,
        'REMOTE_CHANNEL_UNAVAILABLE',
        'LOCAL_FALLBACK'
      ));
    }
    return Promise.resolve(new SemaLinkAgentResponse('本机结果'));
  }
  cancel(_taskId: string): void {}
}

function state(frame: string): string {
  const envelope: Record<string, Object> = JSON.parse(frame) as Record<string, Object>;
  const result: Record<string, Object> = envelope['result'] as Record<string, Object>;
  const task: Record<string, Object> | undefined = result['task'] as Record<string, Object> | undefined;
  if (task !== undefined) return (task['status'] as Record<string, Object>)['state'] as string;
  return ((result['statusUpdate'] as Record<string, Object>)['status'] as Record<string, Object>)['state'] as string;
}

export default function a2aInputRequiredFlowTest(): void {
  describe('A2AInputRequiredFlow', () => {
    it('resumes only the same task and context through working to completed', 0, async () => {
      const ids: SequenceIdGenerator = new SequenceIdGenerator((): number => 2000);
      const orchestrator: SemaLinkAgentAbilityOrchestrator = new SemaLinkAgentAbilityOrchestrator(
        new A2ACommandCodec(), new A2AResponseFactory(),
        new AgentSessionRegistry(ids, (): number => 2000, 60000, 8),
        new AgentTaskRegistry((): number => 2000, 60000), ids, new InputThenCompleteExecutor());
      const sender: FlowSender = new FlowSender();
      await orchestrator.handleData('connection-1', sender, FIRST);
      expect(state(sender.frames[2])).assertEqual('TASK_STATE_INPUT_REQUIRED');
      const firstEnvelope: Record<string, Object> = JSON.parse(sender.frames[0]) as Record<string, Object>;
      const task: Record<string, Object> =
        ((firstEnvelope['result'] as Record<string, Object>)['task']) as Record<string, Object>;
      const taskId: string = task['id'] as string;
      const contextId: string = task['contextId'] as string;
      const followUp: string = '{"jsonrpc":"2.0","id":2,"method":"message/stream","params":{"message":{' +
        '"messageId":"msg-2","taskId":"' + taskId + '","contextId":"' + contextId + '",' +
        '"role":"ROLE_USER","parts":[{"text":"改为本机查询"}]},' +
        '"metadata":{"traceId":"trace-2","agentId":"agent-1"}}}';
      await orchestrator.handleData('connection-1', sender, followUp);
      expect(state(sender.frames[3])).assertEqual('TASK_STATE_WORKING');
      expect(sender.frames[4].includes('"lastChunk":true')).assertTrue();
      expect(state(sender.frames[5])).assertEqual('TASK_STATE_COMPLETED');
      expect(sender.frames[3].includes(taskId)).assertTrue();
      expect(sender.frames[5].includes(contextId)).assertTrue();
    });
  });
}
