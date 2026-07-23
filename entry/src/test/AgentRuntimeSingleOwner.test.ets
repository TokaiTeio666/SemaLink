import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeApplicationService } from '../main/ets/application/KnowledgeApplicationService';
import { RuntimeBootstrap } from '../main/ets/runtime/RuntimeBootstrap';

export default function agentRuntimeSingleOwnerTest(): void {
  describe('AgentRuntimeSingleOwner', () => {
    it('constructs exactly one process-owned KnowledgeApplicationService until explicit shutdown', 0, () => {
      const bootstrap: RuntimeBootstrap = new RuntimeBootstrap();
      const first: KnowledgeApplicationService = bootstrap.knowledgeService();
      const second: KnowledgeApplicationService = bootstrap.knowledgeService();
      expect(first === second).assertTrue();
      bootstrap.shutdown();
      const afterReset: KnowledgeApplicationService = bootstrap.knowledgeService();
      expect(afterReset === first).assertFalse();
      bootstrap.shutdown();
    });
  });
}
