import { describe, expect, it } from '@ohos/hypium';
import { SequenceIdGenerator } from '../main/ets/common/IdGenerator';
import { A2ACommandCodec } from '../main/ets/agent/a2a/A2ACommandCodec';
import { A2AResponseFactory } from '../main/ets/agent/a2a/A2AResponseFactory';
import { AgentSessionRegistry } from '../main/ets/agent/a2a/AgentSessionRegistry';
import { AgentTaskRegistry } from '../main/ets/agent/a2a/AgentTaskRegistry';
import { AgentDataSender, SemaLinkAgentAbilityOrchestrator }
  from '../main/ets/agent/SemaLinkAgentAbilityOrchestrator';
import { SemaLinkAgentExecutor } from '../main/ets/agent/SemaLinkAgentExecutor';
import { AgentQueryScope } from '../main/ets/agent/query/AgentQueryModels';
import {
  SemaLinkAgentRequest,
  SemaLinkAgentResponse,
  SemaLinkAgentResponseKind
} from '../main/ets/agent/SemaLinkAgentModels';

const ORIGINAL_QUERY: string = '查询其他可信设备上的数据库事务隔离级别';
const FIRST_REQUEST: string =
  '{"jsonrpc":"2.0","id":"request-1","method":"message/stream","params":{"message":{' +
  '"messageId":"message-1","role":"ROLE_USER","parts":[{"text":"' + ORIGINAL_QUERY + '"}]},' +
  '"metadata":{"traceId":"trace-1","agentId":"semalink_knowledge_agent"}}}';

class ResumeSender implements AgentDataSender {
  readonly frames: string[] = [];

  send(data: string): void {
    this.frames.push(data);
  }
}

class CapturingContinuationExecutor implements SemaLinkAgentExecutor {
  readonly requests: SemaLinkAgentRequest[] = [];

  execute(request: SemaLinkAgentRequest): Promise<SemaLinkAgentResponse> {
    this.requests.push(request);
    if (this.requests.length === 1) {
      return Promise.resolve(SemaLinkAgentResponse.inputRequired(
        '跨设备通道当前不可用，是否改为本机查询？',
        AgentQueryScope.REMOTE_ONLY,
        AgentQueryScope.LOCAL_ONLY,
        'REMOTE_CHANNEL_UNAVAILABLE',
        'LOCAL_FALLBACK'
      ));
    }
    return Promise.resolve(new SemaLinkAgentResponse('来自本机 Evidence 的数据库事务隔离级别回答'));
  }

  cancel(_taskId: string): void {
  }
}

function taskIdentity(frame: string): string[] {
  const envelope: Record<string, Object> = JSON.parse(frame) as Record<string, Object>;
  const result: Record<string, Object> = envelope['result'] as Record<string, Object>;
  const task: Record<string, Object> = result['task'] as Record<string, Object>;
  return [task['id'] as string, task['contextId'] as string];
}

function requestId(frame: string): string | number {
  return (JSON.parse(frame) as Record<string, Object>)['id'] as string | number;
}

export default function a2aInputRequiredOriginalQueryResumeTest(): void {
  describe('A2AInputRequiredOriginalQueryResume', () => {
    it('resumes the same task with the original query and forced LOCAL_ONLY scope', 0, async () => {
      const ids: SequenceIdGenerator = new SequenceIdGenerator((): number => 4100);
      const executor: CapturingContinuationExecutor = new CapturingContinuationExecutor();
      const orchestrator: SemaLinkAgentAbilityOrchestrator = new SemaLinkAgentAbilityOrchestrator(
        new A2ACommandCodec(), new A2AResponseFactory(),
        new AgentSessionRegistry(ids, (): number => 4100, 60000, 8),
        new AgentTaskRegistry((): number => 4100, 60000), ids, executor);
      const sender: ResumeSender = new ResumeSender();

      await orchestrator.handleData('connection-1', sender, FIRST_REQUEST);
      const identity: string[] = taskIdentity(sender.frames[0]);
      const followUp: string =
        '{"jsonrpc":"2.0","id":"request-2","method":"message/stream","params":{"message":{' +
        '"messageId":"message-2","taskId":"' + identity[0] + '","contextId":"' + identity[1] + '",' +
        '"role":"ROLE_USER","parts":[{"text":"改为本机查询"}]},' +
        '"metadata":{"traceId":"trace-2","agentId":"semalink_knowledge_agent"}}}';
      await orchestrator.handleData('connection-1', sender, followUp);

      expect(executor.requests.length).assertEqual(2);
      expect(executor.requests[0].queryText).assertEqual(ORIGINAL_QUERY);
      expect(executor.requests[1].queryText).assertEqual(ORIGINAL_QUERY);
      expect(executor.requests[1].queryText === '改为本机查询').assertFalse();
      expect(executor.requests[1].requestedScope).assertEqual(AgentQueryScope.LOCAL_ONLY);
      expect(requestId(sender.frames[sender.frames.length - 1])).assertEqual('request-2');
      expect(sender.frames[sender.frames.length - 1].includes(identity[0])).assertTrue();
      expect(sender.frames[sender.frames.length - 1].includes(identity[1])).assertTrue();
    });
  });
}
