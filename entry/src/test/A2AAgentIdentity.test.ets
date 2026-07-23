import { describe, expect, it } from '@ohos/hypium';
import { SEMA_LINK_AGENT_ID } from '../main/ets/agent/AgentIdentity';
import { A2AMetadata } from '../main/ets/agent/a2a/A2AModels';
import { A2AResponseFactory } from '../main/ets/agent/a2a/A2AResponseFactory';

function responseAgentId(frame: string): string {
  const envelope: Record<string, Object> = JSON.parse(frame) as Record<string, Object>;
  const result: Record<string, Object> = envelope['result'] as Record<string, Object>;
  return (result['metadata'] as Record<string, Object>)['agentId'] as string;
}

export default function a2aAgentIdentityTest(): void {
  describe('A2AAgentIdentity', () => {
    it('always emits the local Agent identity instead of reflected request metadata', 0, () => {
      const factory: A2AResponseFactory = new A2AResponseFactory();
      const malicious: A2AMetadata = new A2AMetadata('trace-1', 'attacker-controlled-agent');
      expect(SEMA_LINK_AGENT_ID).assertEqual('semalink_knowledge_agent');
      expect(responseAgentId(factory.submitted('req-1', 'ctx-1', 'task-1', malicious)))
        .assertEqual(SEMA_LINK_AGENT_ID);
      expect(responseAgentId(factory.completedStatus('req-1', 'ctx-1', 'task-1', malicious)))
        .assertEqual(SEMA_LINK_AGENT_ID);
      expect(responseAgentId(factory.cancelled('req-1', 'ctx-1', 'task-1', malicious)))
        .assertEqual(SEMA_LINK_AGENT_ID);
    });
  });
}
