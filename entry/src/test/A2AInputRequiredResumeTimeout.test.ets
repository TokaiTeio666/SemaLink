import { describe, expect, it } from '@ohos/hypium';
import { Scheduler } from '../main/ets/common/Scheduler';
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
  SemaLinkAgentResponse
} from '../main/ets/agent/SemaLinkAgentModels';

class TimeoutTimer {
  readonly id: number;
  readonly callback: () => void;
  cancelled: boolean = false;

  constructor(id: number, callback: () => void) {
    this.id = id;
    this.callback = callback;
  }
}

class TimeoutScheduler implements Scheduler {
  readonly timers: TimeoutTimer[] = [];
  private nextId: number = 1;

  schedule(_delayMs: number, callback: () => void): number {
    const timer: TimeoutTimer = new TimeoutTimer(this.nextId, callback);
    this.nextId += 1;
    this.timers.push(timer);
    return timer.id;
  }

  cancel(timerId: number): void {
    const timer: TimeoutTimer | undefined =
      this.timers.find((value: TimeoutTimer): boolean => value.id === timerId);
    if (timer !== undefined) timer.cancelled = true;
  }

  fire(timerId: number): void {
    this.timers.find((value: TimeoutTimer): boolean => value.id === timerId)?.callback();
  }
}

class TimeoutSender implements AgentDataSender {
  readonly frames: string[] = [];
  send(data: string): void { this.frames.push(data); }
}

class InputThenPendingExecutor implements SemaLinkAgentExecutor {
  calls: number = 0;

  execute(_request: SemaLinkAgentRequest): Promise<SemaLinkAgentResponse> {
    this.calls += 1;
    if (this.calls === 1) {
      return Promise.resolve(SemaLinkAgentResponse.inputRequired(
        '是否改为本机查询？',
        AgentQueryScope.REMOTE_ONLY,
        AgentQueryScope.LOCAL_ONLY,
        'REMOTE_CHANNEL_UNAVAILABLE',
        'LOCAL_FALLBACK'
      ));
    }
    return new Promise<SemaLinkAgentResponse>(
      (_resolve: (response: SemaLinkAgentResponse) => void): void => {});
  }

  cancel(_taskId: string): void {
  }
}

function identity(frame: string): string[] {
  const result: Record<string, Object> =
    (JSON.parse(frame) as Record<string, Object>)['result'] as Record<string, Object>;
  const task: Record<string, Object> = result['task'] as Record<string, Object>;
  return [task['id'] as string, task['contextId'] as string];
}

export default function a2aInputRequiredResumeTimeoutTest(): void {
  describe('A2AInputRequiredResumeTimeout', () => {
    it('uses the second request id and ignores the stale first timeout callback', 0, async () => {
      const scheduler: TimeoutScheduler = new TimeoutScheduler();
      const ids: SequenceIdGenerator = new SequenceIdGenerator((): number => 4200);
      const registry: AgentTaskRegistry =
        new AgentTaskRegistry((): number => 4200, 60000, 8, 50, scheduler, 500);
      const orchestrator: SemaLinkAgentAbilityOrchestrator = new SemaLinkAgentAbilityOrchestrator(
        new A2ACommandCodec(), new A2AResponseFactory(),
        new AgentSessionRegistry(ids, (): number => 4200, 60000, 8),
        registry, ids, new InputThenPendingExecutor());
      const sender: TimeoutSender = new TimeoutSender();
      const first: string =
        '{"jsonrpc":"2.0","id":"request-1","method":"message/stream","params":{"message":{' +
        '"messageId":"message-1","role":"ROLE_USER","parts":[{"text":"只查其他设备"}]},' +
        '"metadata":{"traceId":"trace-1","agentId":"semalink_knowledge_agent"}}}';
      await orchestrator.handleData('connection-1', sender, first);
      const task: string[] = identity(sender.frames[0]);
      const followUp: string =
        '{"jsonrpc":"2.0","id":"request-2","method":"message/stream","params":{"message":{' +
        '"messageId":"message-2","taskId":"' + task[0] + '","contextId":"' + task[1] + '",' +
        '"role":"ROLE_USER","parts":[{"text":"同意"}]},' +
        '"metadata":{"traceId":"trace-2","agentId":"semalink_knowledge_agent"}}}';
      orchestrator.handleData('connection-1', sender, followUp);
      await Promise.resolve();
      const beforeStale: number = sender.frames.length;
      scheduler.fire(1);
      expect(sender.frames.length).assertEqual(beforeStale);
      scheduler.fire(3);
      const terminal: Record<string, Object> =
        JSON.parse(sender.frames[sender.frames.length - 1]) as Record<string, Object>;
      expect(terminal['id'] as string).assertEqual('request-2');
      expect(sender.frames[sender.frames.length - 1].includes('TASK_STATE_FAILED')).assertTrue();
    });
  });
}
