import { describe, expect, it } from '@ohos/hypium';
import { maskAgentId } from '../main/ets/agent/AgentSafeLog';

export default function agentSafeLogTest(): void {
  describe('AgentSafeLog', () => {
    it('masks identifiers deterministically without retaining their text', 0, () => {
      const raw: string = 'agent-task-private-12345';
      const first: string = maskAgentId(raw);
      expect(first).assertEqual(maskAgentId(raw));
      expect(first === maskAgentId(raw + '-other')).assertFalse();
      expect(first.includes(raw)).assertFalse();
      expect(first.startsWith('id-')).assertTrue();
    });
  });
}
