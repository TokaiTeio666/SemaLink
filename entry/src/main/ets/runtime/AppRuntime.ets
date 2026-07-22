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
import { ConnectionState, PeerDevice } from '../model/AppModels';
import { DeviceDirectory } from '../communication/DeviceDirectory';
import { DeviceSemanticRouter } from '../communication/DeviceSemanticRouter';
import { MultiDeviceTaskCoordinator, CoordinatorTransport, CoordinatorCandidate } from '../communication/MultiDeviceTaskCoordinator';
import { PeerTaskResponder, ResponderMessage } from '../communication/PeerTaskResponder';
import { EvidenceAggregator } from '../communication/EvidenceAggregator';
import { DskControlHub } from '../communication/control/DskControlHub';
import { PeerConnectionPool } from '../communication/PeerConnectionPool';
import { EvidenceUtilityScheduler } from '../communication/EvidenceUtilityScheduler';
import { TaskSufficiencyEvaluator } from '../communication/TaskSufficiencyEvaluator';
import { ProgressiveQueryCoordinator } from '../communication/ProgressiveQueryCoordinator';
import { Task3TlsCoordinator } from '../communication/tls/Task3TlsCoordinator';
import {
  ImportReport,
  KnowledgePayloadLevel,
  KnowledgeProfile,
  LocalKnowledgeQuery,
  LocalKnowledgeResult
} from '../contracts/knowledge/KnowledgeModels';
import { EvidenceUnit, TaskRequest } from '../contracts/semantic/SemanticModels';
import { TaskSufficiencyResult } from '../contracts/semantic/SemanticModels';
import { buildAutomaticTask } from '../application/AutomaticQueryPolicy';
import { AutomaticQueryProgress } from '../application/AutomaticQueryPolicy';
import { ErrorStage, AppError } from '../common/AppError';
import {
  CollaborationRecord,
  CollaborationRecordStatus,
  createSendingRecord,
  sortCollaborationRecords,
  updateCollaborationRecord
} from '../collaboration/CollaborationModels';

interface RuntimeDataMessage { type?: string; payload?: Object; }
interface RuntimeEnvelopeWrapper { envelope?: Object; }
interface RuntimeEvidencePayload { taskId: string; round: number; evidence?: EvidenceUnit[]; }

class RuntimeCoordinatorTransport implements CoordinatorTransport {
  private readonly pool: PeerConnectionPool | undefined;
  private readonly provider: SemanticKnowledgeProvider;
  private readonly completed = new Map<string, EvidenceUnit[]>();
  private readonly waiters = new Map<string, (evidence: EvidenceUnit[]) => void>();

  constructor(pool: PeerConnectionPool | undefined, provider: SemanticKnowledgeProvider) {
    this.pool = pool;
    this.provider = provider;
  }

  async send(deviceId: string, envelope: Object): Promise<void> {
    if (this.pool !== undefined) {
      await this.pool.send(deviceId, JSON.stringify(envelope));
    }
  }

  async search(deviceId: string, task: TaskRequest, _round: 1 | 2): Promise<EvidenceUnit[]> {
    if (deviceId === 'local') {
      return await this.provider.searchEvidence(task);
    }
    const key = task.taskId + '@' + deviceId + '@' + _round.toString();
    const cached = this.completed.get(key);
    if (cached !== undefined) { this.completed.delete(key); return cached; }
    return await new Promise<EvidenceUnit[]>((resolve) => {
      this.waiters.set(key, resolve);
      setTimeout((): void => {
        const pending = this.waiters.get(key);
        if (pending !== undefined) { this.waiters.delete(key); pending([]); }
      }, task.latencyBudgetMs);
    });
  }

  onEnvelope(deviceId: string, envelope: Object): void {
    const value = envelope as RuntimeDataMessage;
    if (value.type !== 'EVIDENCE_BATCH' && value.type !== 'EVIDENCE_PAGE' && value.type !== 'EVIDENCE_COMPLETE') return;
    const payload = value.payload as RuntimeEvidencePayload;
    const key = payload.taskId + '@' + deviceId + '@' + payload.round.toString();
    if (value.type === 'EVIDENCE_BATCH' || value.type === 'EVIDENCE_PAGE') {
      const current = this.completed.get(key) ?? [];
      this.completed.set(key, current.concat(payload.evidence ?? []));
      return;
    }
    const evidence = this.completed.get(key) ?? [];
    const waiter = this.waiters.get(key);
    if (waiter !== undefined) {
      this.waiters.delete(key);
      this.completed.delete(key);
      waiter(evidence);
    }
  }

  destroy(): void {
    for (const waiter of this.waiters.values()) waiter([]);
    this.waiters.clear();
    this.completed.clear();
  }
}

export interface RuntimeDependencies {
  transport?: Transport;
  resolverFactory?: ResolverFactory;
  knowledgeProvider?: SemanticKnowledgeProvider;
}

export class AppRuntime {
  private static active: AppRuntime | null = null;
  private destroyed: boolean = false;
  private tlsProbeRunning: boolean = false;

  readonly store: AppStateStore;
  readonly coordinator: QueryCoordinator;
  readonly knowledgeProvider: SemanticKnowledgeProvider;
  readonly knowledgeGateway?: LocalKnowledgeGateway;
  readonly knowledge: KnowledgeApplicationService;
  readonly semanticCoordinator: ProgressiveQueryCoordinator;
  readonly deviceDirectory: DeviceDirectory;
  readonly semanticDeviceDirectory: DeviceDirectory;
  readonly multiDeviceCoordinator: MultiDeviceTaskCoordinator;
  readonly semanticTaskCoordinator: MultiDeviceTaskCoordinator;
  readonly evidenceAggregator: EvidenceAggregator;
  readonly peerTaskResponder: PeerTaskResponder;
  readonly tls: Task3TlsCoordinator | undefined;
  readonly controlHub: DskControlHub | undefined;
  readonly connectionPool: PeerConnectionPool | undefined;
  private readonly ownedKnowledgeService: KnowledgeApplicationService;
  private readonly context: common.UIAbilityContext;
  private readonly runtimeTransport: RuntimeCoordinatorTransport;
  private readonly resolverFactory: ResolverFactory;
  private readonly automaticIdGenerator: SequenceIdGenerator;
  private automaticTaskId: string = '';
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
    this.resolverFactory = resolverFactory;
    this.automaticIdGenerator = new SequenceIdGenerator();
    if (dependencies.knowledgeProvider !== undefined) {
      this.knowledgeProvider = dependencies.knowledgeProvider;
      this.knowledgeGateway = undefined;
    } else {
      this.knowledgeProvider = this.knowledge;
      this.knowledgeGateway = this.knowledge;
    }
    this.deviceDirectory = new DeviceDirectory();
    this.semanticDeviceDirectory = this.deviceDirectory;
    this.semanticCoordinator = new ProgressiveQueryCoordinator(
      session, this.store, this.knowledgeProvider, this.deviceDirectory, new DeviceSemanticRouter(),
      new EvidenceUtilityScheduler(), new TaskSufficiencyEvaluator()
    );
    this.coordinator = new QueryCoordinator(
      session, this.store, this.knowledgeGateway ?? this.knowledge, resolverFactory,
      () => Date.now(), this.semanticCoordinator
    );
    this.tls = this.createTlsCoordinator(context, bundleName);
    this.controlHub = this.tls?.dsk;
    this.connectionPool = this.tls?.pool;
    this.evidenceAggregator = new EvidenceAggregator();
    this.runtimeTransport = new RuntimeCoordinatorTransport(this.connectionPool, this.knowledgeProvider);
    const taskTransport: CoordinatorTransport = this.runtimeTransport;
    this.multiDeviceCoordinator = new MultiDeviceTaskCoordinator(taskTransport, (): CoordinatorCandidate[] => {
      const candidates: CoordinatorCandidate[] = [{ deviceId: 'local', isLocal: true, routeScore: 1, ready: true }];
      const readyIds: string[] = this.connectionPool?.readyDeviceIds() ?? [];
      for (const deviceId of readyIds) candidates.push({ deviceId, isLocal: false, routeScore: 1, ready: true });
      return candidates;
    });
    this.semanticTaskCoordinator = this.multiDeviceCoordinator;
    this.coordinator.setMultiDeviceCoordinator(this.multiDeviceCoordinator);
    this.peerTaskResponder = new PeerTaskResponder({
      provider: this.knowledgeProvider,
      sessionEpoch: 'runtime',
      send: async (deviceId: string, message: ResponderMessage): Promise<void> => {
        if (this.connectionPool !== undefined) {
          await this.connectionPool.send(deviceId, JSON.stringify(message));
        }
      }
    });
    const ingress = (deviceId: string, text: string): void => {
      let message: Object;
      try { message = JSON.parse(text) as Object; } catch (_) { return; }
      const wrapper = message as RuntimeEnvelopeWrapper;
      const envelope: Object = wrapper.envelope ?? message;
      this.runtimeTransport.onEnvelope(deviceId, envelope);
      this.multiDeviceCoordinator.onEnvelope(deviceId, envelope as import('../protocol/MultiDeviceProtocolModels').DataEnvelope);
      this.peerTaskResponder.onEnvelope(deviceId, envelope as import('../protocol/MultiDeviceProtocolModels').DataEnvelope).catch((): void => {});
    };
    this.tls?.onDataMessage(ingress);
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

  async submitAutomaticQuery(question: string): Promise<void> {
    const queryText: string = question.trim();
    if (queryText.length === 0 || queryText.length > 1000) {
      const invalid = new KnowledgeError('E_QUERY_INVALID', 'Automatic query question is invalid', false);
      this.store.update({ automaticQueryProgress: 'FAILED' });
      throw invalid;
    }
    if (this.automaticTaskId.length > 0) {
      throw new AppError('E_BUSY', 'Another automatic query is active', ErrorStage.LIFECYCLE, true);
    }
    const taskId: string = this.automaticIdGenerator.next('automatic-query');
    this.automaticTaskId = taskId;
    const task: TaskRequest = buildAutomaticTask(taskId, queryText, 'PRIVATE_GROUP');
    this.store.update({
      taskId: taskId,
      taskPhase: 'ROUTING',
      taskRound: 0,
      taskFeedback: '',
      taskCoverage: 0,
      taskConfidence: 0,
      taskMissingConcepts: [],
      taskPrivacyLevel: task.privacyLevel,
      question: queryText,
      summary: '',
      automaticQueryProgress: 'ROUTING',
      automaticSourceNames: [],
      automaticExcludedSourceNames: [],
      evidenceSourceDeviceIds: [],
      finalSufficiency: '',
      clearError: true
    });
    let automaticRecordCreated: boolean = false;
    try {
      const peers: Array<PeerDevice> = await this.resolverFactory().resolveAll();
      if (this.connectionPool !== undefined) {
        await this.connectionPool.refreshPeers(peers);
      }
      const connected: PeerDevice[] = [];
      const excluded: string[] = [];
      await Promise.all(peers.map(async (peer: PeerDevice): Promise<void> => {
        try {
          if (this.tls === undefined) throw new Error('E_DSK_UNAVAILABLE');
          await this.tls.connect(peer);
          connected.push(peer);
        } catch (_) {
          excluded.push(peer.deviceName.length > 0 ? peer.deviceName : peer.deviceId);
        }
      }));
      this.store.update({
        automaticExcludedSourceNames: excluded.slice(),
        automaticSourceNames: ['local'].concat(connected.map((peer: PeerDevice): string =>
          peer.deviceName.length > 0 ? peer.deviceName : peer.deviceId)),
        automaticQueryProgress: 'SEARCHING',
        taskPhase: 'AWAITING_L1'
      });
      const sourceNames: string[] = ['local'].concat(connected.map((peer: PeerDevice): string =>
        peer.deviceName.length > 0 ? peer.deviceName : peer.deviceId));
      const automaticRecord: CollaborationRecord = createSendingRecord({
        id: taskId,
        question: queryText,
        sourceDeviceName: 'local',
        sourceDeviceNames: sourceNames,
        targetDeviceName: 'automatic',
        createdAt: Date.now()
      });
      const recordsWithAutomatic: Array<CollaborationRecord> = this.store.snapshot().collaborationRecords.slice();
      recordsWithAutomatic.push(automaticRecord);
      automaticRecordCreated = true;
      this.store.update({
        collaborationRecords: sortCollaborationRecords(recordsWithAutomatic),
        selectedCollaborationRecordId: taskId
      });
      const result: TaskSufficiencyResult = await this.multiDeviceCoordinator.submit(task);
      const progress: AutomaticQueryProgress = result.feedback === 'ENOUGH' ? 'ANSWER_READY' :
        (result.feedback === 'ABORT' ? 'INSUFFICIENT' : 'FAILED');
      const phase: 'SUFFICIENT' | 'ABORTED' | 'FAILED' = result.feedback === 'ENOUGH' ? 'SUFFICIENT' :
        (result.feedback === 'ABORT' ? 'ABORTED' : 'FAILED');
      this.store.update({
        automaticQueryProgress: progress,
        taskPhase: phase,
        taskRound: result.feedback === 'ENOUGH' ? 1 : 2,
        taskFeedback: result.feedback,
        taskCoverage: result.coverage,
        taskConfidence: result.confidence,
        taskMissingConcepts: result.missingConcepts,
        finalSufficiency: result.feedback,
        summary: result.feedback === 'ENOUGH' ?
          'Answer ready from ' + result.acceptedEvidenceIds.length.toString() + ' evidence items' :
          'No sufficient evidence found',
        evidenceSourceDeviceIds: connected.map((peer: PeerDevice): string => peer.deviceId).concat(['local'])
      });
      const completedRecords: Array<CollaborationRecord> = updateCollaborationRecord(taskId,
        this.store.snapshot().collaborationRecords, {
          status: result.feedback === 'ENOUGH' ? CollaborationRecordStatus.SYNCED : CollaborationRecordStatus.FAILED,
          summary: result.feedback === 'ENOUGH' ?
            'Answer ready from ' + result.acceptedEvidenceIds.length.toString() + ' evidence items' :
            'No sufficient evidence found',
          evidenceCount: result.acceptedEvidenceIds.length
        });
      this.store.update({ collaborationRecords: sortCollaborationRecords(completedRecords) });
    } catch (error) {
      const appError: AppError = error instanceof AppError ? error :
        new AppError('E_AUTOMATIC_QUERY_FAILED', 'Automatic query failed', ErrorStage.QUERY, true);
      this.store.update({ automaticQueryProgress: 'FAILED', taskPhase: 'FAILED', error: appError });
      if (automaticRecordCreated) {
        const failedRecords: Array<CollaborationRecord> = updateCollaborationRecord(taskId,
          this.store.snapshot().collaborationRecords, {
            status: CollaborationRecordStatus.FAILED,
            errorMessage: appError.message
          });
        this.store.update({ collaborationRecords: sortCollaborationRecords(failedRecords) });
      }
      throw error as Error;
    } finally {
      if (this.automaticTaskId === taskId) this.automaticTaskId = '';
    }
  }

  async cancelAutomaticQuery(): Promise<void> {
    const taskId: string = this.automaticTaskId;
    if (taskId.length === 0) return;
    await this.multiDeviceCoordinator.cancel(taskId);
    this.store.update({ automaticQueryProgress: 'INSUFFICIENT', taskPhase: 'ABORTED', taskFeedback: 'ABORT', finalSufficiency: 'ABORT' });
    const cancelledRecords: Array<CollaborationRecord> = updateCollaborationRecord(taskId,
      this.store.snapshot().collaborationRecords, {
        status: CollaborationRecordStatus.OFFLINE,
        errorMessage: 'Automatic query cancelled'
      });
    this.store.update({ collaborationRecords: sortCollaborationRecords(cancelledRecords) });
    this.automaticTaskId = '';
  }

  async runTlsProbe(): Promise<void> {
    if (this.tlsProbeRunning) {
      return;
    }
    this.tlsProbeRunning = true;
    try {
      await this.runTlsProbeOnce();
    } finally {
      this.tlsProbeRunning = false;
    }
  }

  private async runTlsProbeOnce(): Promise<void> {
    if (this.tls === undefined) throw new Error('E_DSK_UNAVAILABLE');
    const wasConnected: boolean = this.store.snapshot().connectionState === ConnectionState.CONNECTED;
    if (wasConnected) {
      await this.coordinator.disconnect();
    }
    const peers = await new TrustedDeviceResolver(new DistributedDeviceProvider(this.context.applicationInfo.name)).resolveAll();
    try {
      if (peers.length === 0) throw new Error('E_DEVICE_NOT_FOUND');
      for (const peer of peers) {
        await this.tls.connect(peer);
        await this.tls.probe(peer.deviceId);
      }
    } finally {
      if (wasConnected) {
        await this.coordinator.connect();
      }
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

  acceptCollaboration(wantParam: Record<string, Object>): boolean {
    if (this.tls !== undefined && this.tls.accept(wantParam)) {
      return true;
    }
    return this.coordinator.acceptCollaboration(wantParam);
  }

  destroy(): void {
    if (this.destroyed) {
      return;
    }
    this.destroyed = true;
    this.multiDeviceCoordinator.destroy();
    this.peerTaskResponder.destroy();
    this.runtimeTransport.destroy();
    this.coordinator.destroy();
    this.tls?.destroy().catch((): void => { });
    this.ownedKnowledgeService.destroy();
  }

  private createTlsCoordinator(context: common.UIAbilityContext, bundleName: string): Task3TlsCoordinator | undefined {
    try {
      return new Task3TlsCoordinator({ context: context, bundleName: bundleName });
    } catch (_) {
      return undefined;
    }
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
