import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeProfile } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import { SemanticKnowledgeProvider } from '../main/ets/contracts/semantic/SemanticKnowledgeProvider';
import { AgentRuntimeHandle, RuntimeBootstrap, RuntimeFactory } from '../main/ets/runtime/RuntimeBootstrap';

class OwnershipProvider implements SemanticKnowledgeProvider {
  getProfile(): Promise<KnowledgeProfile> { return Promise.reject(new Error('unused')); }
  searchEvidence(_task: TaskRequest): Promise<EvidenceUnit[]> { return Promise.resolve([]); }
}

class ClosableHandle implements AgentRuntimeHandle {
  readonly knowledgeProvider: SemanticKnowledgeProvider = new OwnershipProvider();
  closes: number = 0;
  close(): void { this.closes++; }
}

class HandleFactory implements RuntimeFactory {
  creates: number = 0;
  readonly handle: ClosableHandle;
  constructor(handle: ClosableHandle) { this.handle = handle; }
  create(): Promise<AgentRuntimeHandle> { this.creates++; return Promise.resolve(this.handle); }
}

export default function agentRuntimeOwnershipTest(): void {
  describe('AgentRuntimeOwnership', () => {
    it('shares one initialization and closes once across repeated shutdown', 0, async () => {
      const bootstrap: RuntimeBootstrap = new RuntimeBootstrap();
      const handle: ClosableHandle = new ClosableHandle();
      const factory: HandleFactory = new HandleFactory(handle);
      const runtimes: AgentRuntimeHandle[] = await Promise.all([
        bootstrap.ensureWithFactory(factory), bootstrap.ensureWithFactory(factory)
      ]);
      expect(runtimes[0] === runtimes[1]).assertTrue();
      expect(factory.creates).assertEqual(1);
      bootstrap.shutdown();
      bootstrap.shutdown();
      expect(handle.closes).assertEqual(1);
      await bootstrap.ensureWithFactory(factory);
      expect(factory.creates).assertEqual(2);
    });
  });
}
