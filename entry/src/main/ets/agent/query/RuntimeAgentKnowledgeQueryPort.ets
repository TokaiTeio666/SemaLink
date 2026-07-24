import { common } from '@kit.AbilityKit';
import { AgentRuntimeHandle, RuntimeBootstrap } from '../../runtime/RuntimeBootstrap';
import { AgentKnowledgeQueryPort } from './AgentKnowledgeQueryPort';
import { AgentQueryRequest, AgentQueryResult } from './AgentQueryModels';
import { CrossDeviceKnowledgePort } from './CrossDeviceKnowledgePort';
import { LocalFirstAgentKnowledgeQueryService } from './LocalFirstAgentKnowledgeQueryService';

export class RuntimeAgentKnowledgeQueryPort implements AgentKnowledgeQueryPort {
  private readonly context: common.Context;
  private readonly bootstrap: RuntimeBootstrap;
  private readonly remote: CrossDeviceKnowledgePort;
  private service?: LocalFirstAgentKnowledgeQueryService;
  private runtime?: AgentRuntimeHandle;
  private readonly cancelled: Set<string> = new Set<string>();
  private readonly active: Set<string> = new Set<string>();

  constructor(context: common.Context, bootstrap: RuntimeBootstrap, remote: CrossDeviceKnowledgePort) {
    this.context = context;
    this.bootstrap = bootstrap;
    this.remote = remote;
  }

  async query(request: AgentQueryRequest): Promise<AgentQueryResult> {
    this.active.add(request.internalTaskId);
    try {
      this.ensureNotCancelled(request.internalTaskId);
      const runtime: AgentRuntimeHandle = await this.bootstrap.ensureInitialized(this.context);
      this.ensureNotCancelled(request.internalTaskId);
      if (this.service === undefined || this.runtime !== runtime) {
        this.service = new LocalFirstAgentKnowledgeQueryService(runtime.knowledgeProvider, this.remote);
        this.runtime = runtime;
      }
      return await this.service.query(request);
    } finally {
      this.active.delete(request.internalTaskId);
      this.cancelled.delete(request.internalTaskId);
    }
  }

  cancel(internalTaskId: string): void {
    if (this.active.has(internalTaskId)) {
      this.cancelled.add(internalTaskId);
    }
    if (this.service !== undefined) {
      this.service.cancel(internalTaskId);
    } else {
      this.remote.cancel(internalTaskId);
    }
  }

  private ensureNotCancelled(internalTaskId: string): void {
    if (this.cancelled.has(internalTaskId)) {
      throw new Error('E_AGENT_TASK_CANCELLED');
    }
  }
}
