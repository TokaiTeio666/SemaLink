import { describe, expect, it } from '@ohos/hypium';
import { AgentRuntimeHandle, RuntimeBootstrap, RuntimeFactory } from '../main/ets/runtime/RuntimeBootstrap';
import { SemanticKnowledgeProvider } from '../main/ets/contracts/semantic/SemanticKnowledgeProvider';
import { KnowledgeProfile } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';

class FakeSemanticProvider implements SemanticKnowledgeProvider {
  getProfile(): Promise<KnowledgeProfile> {
    return Promise.reject(new Error('Profile is not used by bootstrap tests'));
  }

  searchEvidence(_task: TaskRequest): Promise<EvidenceUnit[]> {
    return Promise.resolve([]);
  }
}

class FakeRuntimeHandle implements AgentRuntimeHandle {
  readonly knowledgeProvider: SemanticKnowledgeProvider;

  constructor(provider: SemanticKnowledgeProvider) {
    this.knowledgeProvider = provider;
  }
}

class CountingRuntimeFactory implements RuntimeFactory {
  count: number = 0;
  failFirst: boolean = false;
  readonly handle: AgentRuntimeHandle;

  constructor(handle: AgentRuntimeHandle) {
    this.handle = handle;
  }

  create(): Promise<AgentRuntimeHandle> {
    this.count += 1;
    if (this.failFirst && this.count === 1) {
      return Promise.reject(new Error('controlled init failure'));
    }
    return Promise.resolve(this.handle);
  }
}

export default function runtimeBootstrapTest(): void {
  describe('RuntimeBootstrap', () => {
    it('coalesces concurrent initialization and reuses runtime', 0, async () => {
      const provider: SemanticKnowledgeProvider = new FakeSemanticProvider();
      const handle: AgentRuntimeHandle = new FakeRuntimeHandle(provider);
      const factory: CountingRuntimeFactory = new CountingRuntimeFactory(handle);
      const bootstrap: RuntimeBootstrap = new RuntimeBootstrap();
      const results: AgentRuntimeHandle[] = await Promise.all([
        bootstrap.ensureWithFactory(factory), bootstrap.ensureWithFactory(factory)
      ]);
      expect(factory.count).assertEqual(1);
      expect(results[0] === results[1]).assertTrue();
      expect((await bootstrap.ensureWithFactory(factory)) === handle).assertTrue();
    });

    it('allows safe retry after initialization failure', 0, async () => {
      const provider: SemanticKnowledgeProvider = new FakeSemanticProvider();
      const handle: AgentRuntimeHandle = new FakeRuntimeHandle(provider);
      const factory: CountingRuntimeFactory = new CountingRuntimeFactory(handle);
      factory.failFirst = true;
      const bootstrap: RuntimeBootstrap = new RuntimeBootstrap();
      let failed: boolean = false;
      try {
        await bootstrap.ensureWithFactory(factory);
      } catch (_error) {
        failed = true;
      }
      const retried: AgentRuntimeHandle = await bootstrap.ensureWithFactory(factory);
      expect(failed).assertTrue();
      expect(factory.count).assertEqual(2);
      expect(retried === handle).assertTrue();
    });
  });
}
