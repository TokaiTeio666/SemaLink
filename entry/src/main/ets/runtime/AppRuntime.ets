import { common } from '@kit.AbilityKit';
import { AppStateStore } from '../state/AppStateStore';
import { QueryCoordinator, ResolverFactory } from '../application/QueryCoordinator';
import { CollaborationTransport } from '../communication/CollaborationTransport';
import { SessionManager } from '../communication/SessionManager';
import { Transport } from '../communication/Transport';
import { DistributedDeviceProvider, TrustedDeviceResolver } from '../communication/TrustedDeviceResolver';
import { Logger } from '../common/Logger';
import { SequenceIdGenerator } from '../common/IdGenerator';
import { ProtocolCodec } from '../protocol/ProtocolCodec';
import { SystemScheduler } from '../common/Scheduler';
import { SemanticKnowledgeProvider } from '../contracts/semantic/SemanticKnowledgeProvider';
import { LocalKnowledgeGateway } from '../contracts/knowledge/LocalKnowledgeGateway';
import { KnowledgeApplicationService } from '../application/KnowledgeApplicationService';
import { publishKnowledgeResult } from '../application/KnowledgeResultMapper';
import { KnowledgeError } from '../contracts/knowledge/KnowledgeError';
import {
  ImportReport,
  KnowledgePayloadLevel,
  KnowledgeProfile,
  LocalKnowledgeQuery,
  LocalKnowledgeResult
} from '../contracts/knowledge/KnowledgeModels';

export interface RuntimeDependencies {
  transport?: Transport;
  resolverFactory?: ResolverFactory;
  knowledgeProvider?: SemanticKnowledgeProvider;
}

export class AppRuntime {
  private static active: AppRuntime | null = null;
  private destroyed: boolean = false;

  readonly store: AppStateStore;
  readonly coordinator: QueryCoordinator;
  readonly knowledgeProvider: SemanticKnowledgeProvider;
  readonly knowledgeGateway?: LocalKnowledgeGateway;
  readonly knowledge: KnowledgeApplicationService;
  private readonly ownedKnowledgeService: KnowledgeApplicationService;
  private readonly context: common.UIAbilityContext;
  private knowledgeInitialization?: Promise<void>;

  constructor(context: common.UIAbilityContext, dependencies: RuntimeDependencies = {}) {
    this.context = context;
    const bundleName: string = context.applicationInfo.name;
    const transport: Transport = dependencies.transport ??
      new CollaborationTransport(context, bundleName, new Logger());
    const codec: ProtocolCodec = new ProtocolCodec();
    const session: SessionManager = new SessionManager(
      transport, codec, new SequenceIdGenerator(), new SystemScheduler(), 3000, 10000
    );
    this.store = new AppStateStore();
    this.knowledge = new KnowledgeApplicationService();
    this.ownedKnowledgeService = this.knowledge;
    const resolverFactory: ResolverFactory = dependencies.resolverFactory ??
      (() => new TrustedDeviceResolver(new DistributedDeviceProvider(bundleName)));
    this.coordinator = new QueryCoordinator(
      session, this.store, this.knowledge, resolverFactory
    );
    if (dependencies.knowledgeProvider !== undefined) {
      this.knowledgeProvider = dependencies.knowledgeProvider;
      this.knowledgeGateway = undefined;
    } else {
      this.knowledgeProvider = this.knowledge;
      this.knowledgeGateway = this.knowledge;
    }
  }

  initializeKnowledge(): Promise<void>;
  initializeKnowledge(context: common.UIAbilityContext): Promise<void>;
  async initializeKnowledge(context?: common.UIAbilityContext): Promise<void> {
    if (context !== undefined) {
      if (this.knowledgeInitialization === undefined) {
        this.knowledgeInitialization = this.prepareKnowledge(context);
      }
      await this.knowledgeInitialization;
      return;
    }
    if (this.knowledgeGateway === undefined) {
      return;
    }
    await this.ownedKnowledgeService.initialize(this.context, 'local-device');
  }

  async importBuiltInKnowledge(): Promise<void> {
    this.store.update({ knowledgeBusy: true, knowledgeMessage: '正在导入内置文档', knowledgeError: '' });
    try {
      const report: ImportReport = await this.knowledge.importBuiltInDocuments();
      await this.refreshKnowledgeProfile('内置文档导入完成：新增 ' + report.importedDocuments.toString() +
        '，跳过 ' + report.skippedDocuments.toString());
    } catch (error) {
      this.publishKnowledgeError(error as Object);
      throw new Error('Built-in knowledge import failed');
    }
  }

  async importUserKnowledge(): Promise<void> {
    this.store.update({ knowledgeBusy: true, knowledgeMessage: '正在导入所选文档', knowledgeError: '' });
    try {
      const report: ImportReport = await this.knowledge.selectAndImportTextDocuments();
      await this.refreshKnowledgeProfile('用户文档导入完成：新增 ' + report.importedDocuments.toString());
    } catch (error) {
      this.publishKnowledgeError(error as Object);
      throw new Error('User knowledge import failed');
    }
  }

  async clearKnowledge(): Promise<void> {
    this.store.update({ knowledgeBusy: true, knowledgeMessage: '正在清空知识库', knowledgeError: '' });
    try {
      await this.knowledge.clearKnowledgeBase();
      await this.refreshKnowledgeProfile('知识库已清空');
      this.store.update({
        knowledgeItems: [], knowledgeQueryStatus: 'IDLE', knowledgeRetrievalMs: 0,
        knowledgeTruncated: false, summary: ''
      });
    } catch (error) {
      this.publishKnowledgeError(error as Object);
      throw new Error('Clearing knowledge failed');
    }
  }

  async queryLocalKnowledge(question: string, level: KnowledgePayloadLevel): Promise<void> {
    this.store.update({
      knowledgeBusy: true,
      knowledgeMessage: '正在检索本机知识库',
      knowledgeQueryStatus: 'QUERYING',
      knowledgeLevel: level,
      knowledgeItems: [],
      knowledgeRetrievalMs: 0,
      knowledgeTruncated: false,
      knowledgeError: ''
    });
    const request: LocalKnowledgeQuery = {
      contractVersion: '1.0',
      requestId: 'local-' + Date.now().toString(),
      queryText: question.trim(),
      topK: 5,
      requestedLevel: level,
      maxPayloadBytes: 8192
    };
    try {
      const result: LocalKnowledgeResult = await this.knowledge.query(request);
      publishKnowledgeResult(this.store, result);
    } catch (error) {
      this.publishKnowledgeError(error as Object, true);
      throw new Error('Local knowledge query failed');
    }
  }

  static initialize(context: common.UIAbilityContext): AppRuntime {
    if (AppRuntime.active === null) {
      AppRuntime.active = new AppRuntime(context);
    }
    return AppRuntime.active;
  }

  static current(): AppRuntime {
    if (AppRuntime.active === null) {
      throw new Error('AppRuntime has not been initialized');
    }
    return AppRuntime.active;
  }

  static reset(): void {
    if (AppRuntime.active === null) {
      return;
    }
    AppRuntime.active.destroy();
    AppRuntime.active = null;
  }

  destroy(): void {
    if (this.destroyed) {
      return;
    }
    this.destroyed = true;
    this.coordinator.destroy();
    this.ownedKnowledgeService.destroy();
  }

  private async prepareKnowledge(context: common.UIAbilityContext): Promise<void> {
    this.store.update({ knowledgeBusy: true, knowledgeMessage: '正在初始化知识库', knowledgeError: '' });
    try {
      await this.knowledge.initialize(context);
      const profile: KnowledgeProfile = await this.knowledge.getKnowledgeProfile();
      if (profile.indexState === 'EMPTY') {
        await this.knowledge.importBuiltInDocuments();
      }
      await this.refreshKnowledgeProfile('知识库已就绪');
    } catch (error) {
      this.publishKnowledgeError(error as Object);
      throw new Error('Knowledge initialization failed');
    }
  }

  private async refreshKnowledgeProfile(message: string): Promise<void> {
    const profile: KnowledgeProfile = await this.knowledge.getKnowledgeProfile();
    this.store.update({
      knowledgeInitialized: true,
      knowledgeBusy: false,
      knowledgeIndexState: profile.indexState,
      knowledgeDocumentCount: profile.documentCount,
      knowledgeChunkCount: profile.chunkCount,
      knowledgeMessage: message,
      knowledgeError: ''
    });
  }

  private publishKnowledgeError(error: Object, queryFailure: boolean = false): void {
    let code: string = 'E_RETRIEVAL_FAILED';
    let message: string = '知识库操作失败';
    if (error instanceof KnowledgeError) {
      code = error.code;
      message = error.message;
    } else if (error instanceof Error) {
      message = error.message;
    }
    this.store.update({
      knowledgeBusy: false,
      knowledgeMessage: '知识库操作失败',
      knowledgeQueryStatus: queryFailure ? 'ERROR' : this.store.snapshot().knowledgeQueryStatus,
      knowledgeItems: queryFailure ? [] : this.store.snapshot().knowledgeItems,
      knowledgeError: code + ': ' + message
    });
  }
}
