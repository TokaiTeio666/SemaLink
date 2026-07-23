import { common } from '@kit.AbilityKit';
import { KnowledgeApplicationService } from '../application/KnowledgeApplicationService';
import { KnowledgeProfile } from '../contracts/knowledge/KnowledgeModels';
import { SemanticKnowledgeProvider } from '../contracts/semantic/SemanticKnowledgeProvider';
import { AgentSafeLog } from '../agent/AgentSafeLog';

export interface AgentRuntimeHandle {
  readonly knowledgeProvider: SemanticKnowledgeProvider;
  close?(): void;
}

export interface RuntimeFactory {
  create(): Promise<AgentRuntimeHandle>;
}

class DefaultAgentRuntimeHandle implements AgentRuntimeHandle {
  readonly knowledgeProvider: SemanticKnowledgeProvider;

  constructor(knowledgeProvider: SemanticKnowledgeProvider) {
    this.knowledgeProvider = knowledgeProvider;
  }

  close(): void {
    (this.knowledgeProvider as KnowledgeApplicationService).destroy();
  }
}

class DefaultAgentRuntimeFactory implements RuntimeFactory {
  private readonly context: common.Context;
  private readonly knowledge: KnowledgeApplicationService;

  constructor(context: common.Context, knowledge: KnowledgeApplicationService) {
    this.context = context;
    this.knowledge = knowledge;
  }

  async create(): Promise<AgentRuntimeHandle> {
    await this.knowledge.initialize(this.context, 'local-device');
    const profile: KnowledgeProfile = await this.knowledge.getKnowledgeProfile();
    if (profile.indexState === 'EMPTY') {
      await this.knowledge.importBuiltInDocuments();
    }
    return new DefaultAgentRuntimeHandle(this.knowledge);
  }
}

export class RuntimeBootstrap {
  private runtime?: AgentRuntimeHandle;
  private initialization?: Promise<AgentRuntimeHandle>;
  private knowledge?: KnowledgeApplicationService;
  private generation: number = 0;

  ensureInitialized(context: common.Context): Promise<AgentRuntimeHandle> {
    return this.ensureWithFactory(new DefaultAgentRuntimeFactory(context, this.knowledgeService()));
  }

  knowledgeService(): KnowledgeApplicationService {
    if (this.knowledge === undefined) {
      this.knowledge = new KnowledgeApplicationService();
    }
    return this.knowledge;
  }

  ensureWithFactory(factory: RuntimeFactory): Promise<AgentRuntimeHandle> {
    if (this.runtime !== undefined) {
      return Promise.resolve(this.runtime);
    }
    if (this.initialization === undefined) {
      this.initialization = this.initialize(factory, this.generation);
    }
    return this.initialization;
  }

  current(): AgentRuntimeHandle | undefined {
    return this.runtime;
  }

  shutdown(): void {
    const hadRuntime: boolean = this.runtime !== undefined || this.initialization !== undefined || this.knowledge !== undefined;
    this.generation += 1;
    const current: AgentRuntimeHandle | undefined = this.runtime;
    this.runtime = undefined;
    this.initialization = undefined;
    if (current !== undefined && current.close !== undefined) {
      current.close();
    } else if (this.knowledge !== undefined) {
      this.knowledge.destroy();
    }
    this.knowledge = undefined;
    if (hadRuntime) {
      AgentSafeLog.runtime('SHUTDOWN');
    }
  }

  private async initialize(factory: RuntimeFactory, generation: number): Promise<AgentRuntimeHandle> {
    try {
      const created: AgentRuntimeHandle = await factory.create();
      if (generation !== this.generation) {
        created.close?.();
        throw new Error('Runtime initialization superseded');
      }
      this.runtime = created;
      AgentSafeLog.runtime('INITIALIZED');
      return created;
    } catch (_error) {
      if (generation === this.generation) {
        this.initialization = undefined;
      }
      AgentSafeLog.runtime('FAILED_RETRY_ALLOWED');
      throw new Error('Agent runtime initialization failed');
    }
  }
}

export const PROCESS_RUNTIME_BOOTSTRAP: RuntimeBootstrap = new RuntimeBootstrap();
