import { AppError, ErrorStage } from '../common/AppError';
import { DeviceProfileAdvertisement, DeviceRuntimeSnapshot, EvidenceUnit, TaskPhase, TaskRequest,
  TaskSufficiencyResult, validateTaskRequest } from '../contracts/semantic/SemanticModels';
import { SemanticKnowledgeProvider } from '../contracts/semantic/SemanticKnowledgeProvider';
import { KnowledgeProfile } from '../contracts/knowledge/KnowledgeModels';
import { ErrorPayload, EvidencePayload, MessageType, ProtocolEnvelope, ProfilePayload, TaskPayload,
  TsfPayload } from '../protocol/ProtocolModels';
import { ProtocolCodec } from '../protocol/ProtocolCodec';
import { SessionManager } from './SessionManager';
import { DeviceDirectory } from './DeviceDirectory';
import { DeviceSemanticRouter } from './DeviceSemanticRouter';
import { EvidenceUtilityScheduler } from './EvidenceUtilityScheduler';
import { TaskSufficiencyEvaluator } from './TaskSufficiencyEvaluator';
import { AppStateStore } from '../state/AppStateStore';
import { utf8ByteLength } from '../knowledge/payload/Utf8Sizer';

export class ProgressiveQueryCoordinator {
  private readonly session: SessionManager;
  private readonly store: AppStateStore;
  private readonly provider: SemanticKnowledgeProvider;
  private readonly directory: DeviceDirectory;
  private readonly router: DeviceSemanticRouter;
  private readonly scheduler: EvidenceUtilityScheduler;
  private readonly evaluator: TaskSufficiencyEvaluator;
  private readonly clock: () => number;
  private readonly codec: ProtocolCodec = new ProtocolCodec();
  private activeTaskId: string | null = null;
  private cancelledTaskId: string | null = null;
  private remoteSessionId: string = 'semantic-session';
  private remoteEvidence: EvidenceUnit[] = [];
  private remoteCandidates: Map<string, EvidenceUnit[]> = new Map<string, EvidenceUnit[]>();
  private remoteTasks: Map<string, TaskRequest> = new Map<string, TaskRequest>();
  private pendingRemoteResolve: ((result: TaskSufficiencyResult) => void) | null = null;
  private pendingRemoteReject: ((reason: Object) => void) | null = null;
  private messageSequence: number = 0;
  private taskStartedAtMs: number = 0;
  private firstResultRecorded: boolean = false;
  private latencySamples: number[] = [];

  constructor(session: SessionManager, store: AppStateStore,
    provider: SemanticKnowledgeProvider,
    directory: DeviceDirectory, router: DeviceSemanticRouter, scheduler: EvidenceUtilityScheduler,
    evaluator: TaskSufficiencyEvaluator, clock: () => number = (): number => Date.now()) {
    this.session = session;
    this.store = store;
    this.provider = provider;
    this.directory = directory;
    this.router = router;
    this.scheduler = scheduler;
    this.evaluator = evaluator;
    this.clock = clock;
  }

  async submit(task: TaskRequest): Promise<TaskSufficiencyResult> {
    validateTaskRequest(task);
    if (this.activeTaskId !== null) {
      throw new AppError('E_BUSY', 'E_BUSY', ErrorStage.QUERY, true);
    }
    this.activeTaskId = task.taskId;
    this.cancelledTaskId = null;
    this.taskStartedAtMs = this.clock();
    this.firstResultRecorded = false;
    this.latencySamples = [];
    this.store.update({ taskId: task.taskId, taskPhase: 'ROUTING', taskRound: 0, taskFeedback: '',
      taskCoverage: 0, taskConfidence: 0, taskMissingConcepts: [], evidenceBytes: 0,
      taskPrivacyLevel: task.privacyLevel, protocolBytes: 0, latencySamplesMs: [],
      firstResultLatencyMs: 0, completionLatencyMs: 0, clearError: true });
    try {
      const profile: KnowledgeProfile = await this.provider.getProfile();
      this.ensureActive(task.taskId);
      this.directory.setLocal(this.localSnapshot(profile), this.localAdvertisement(profile));
      const route = this.router.route(task, this.directory.candidates(), this.clock());
      if (route.selected === null) {
        throw new AppError('E_NO_ROUTE', 'No local semantic route is available', ErrorStage.SELECTION, true);
      }
      this.store.update({ selectedDeviceId: route.selected.candidate.snapshot.deviceId,
        routeScore: route.selected.scores.total,
        routeSemanticMatch: route.selected.scores.semanticMatch,
        routeFilterMatch: route.selected.scores.filterMatch,
        routeFreshness: route.selected.scores.freshness,
        routeNormalizedRtt: route.selected.scores.normalizedRtt,
        routeLoad: route.selected.scores.load,
        routePrivacyRisk: route.selected.scores.privacyRisk });

      if (!route.selected.candidate.snapshot.isLocal) {
        return await this.submitRemote(task, route.selected.candidate.profile.deviceId);
      }

      const candidates: EvidenceUnit[] = await this.provider.searchEvidence(task);
      this.ensureActive(task.taskId);
      let sent: EvidenceUnit[] = [];
      let result: TaskSufficiencyResult = await this.runRound(task, candidates, 1, sent);
      sent = this.selectedEvidence(task, candidates, 1, sent);
      if (result.feedback === 'ENOUGH') {
        this.finish(task.taskId, 'SUFFICIENT', 1, result);
        return result;
      }
      result = await this.runRound(task, candidates, 2, sent);
      if (result.feedback === 'ENOUGH') {
        this.finish(task.taskId, 'SUFFICIENT', 2, result);
      } else {
        this.finish(task.taskId, 'ABORTED', 2, result);
      }
      return result;
    } catch (error) {
      if (error instanceof AppError && error.code === 'E_CANCELLED') {
        throw error;
      }
      this.store.update({ taskPhase: 'FAILED', knowledgeError: error instanceof Error ? error.message : 'Semantic task failed' });
      throw error;
    } finally {
      if (this.activeTaskId === task.taskId) {
        this.activeTaskId = null;
      }
    }
  }

  cancel(taskId: string): void {
    if (this.activeTaskId !== taskId) {
      return;
    }
    this.cancelledTaskId = taskId;
    this.activeTaskId = null;
    this.store.update({ taskPhase: 'ABORTED', taskFeedback: 'ABORT', taskId: taskId });
  }

  onProtocolEnvelope(envelope: ProtocolEnvelope): void {
    if (this.activeTaskId !== null && envelope.requestId === this.activeTaskId) {
      this.addProtocolBytes(envelope);
    }
    if (envelope.type === MessageType.PROFILE) {
      const payload: ProfilePayload = envelope.payload as ProfilePayload;
      this.remoteSessionId = envelope.sessionId;
      this.directory.setRemote(payload.profile);
      return;
    }
    if (envelope.type === MessageType.TASK) {
      this.handleRemoteTask(envelope).catch((_error: Object) => {});
      return;
    }
    if (envelope.type === MessageType.EVIDENCE) {
      this.handleRemoteEvidence(envelope);
      return;
    }
    if (envelope.type === MessageType.TSF) {
      this.handleRemoteTsf(envelope);
      return;
    }
    if (envelope.type === MessageType.ERROR) {
      const payload: ErrorPayload = envelope.payload as ErrorPayload;
      if (this.pendingRemoteReject !== null && envelope.requestId === this.activeTaskId) {
        const reject = this.pendingRemoteReject;
        this.pendingRemoteResolve = null;
        this.pendingRemoteReject = null;
        this.activeTaskId = null;
        this.store.update({ taskPhase: 'FAILED', knowledgeError: payload.message });
        reject(new AppError(payload.code, payload.message, ErrorStage.PROTOCOL, true));
      }
    }
  }

  async publishProfile(sessionId: string = this.remoteSessionId): Promise<void> {
    const profile: KnowledgeProfile = await this.provider.getProfile();
    await this.session.sendEnvelope(this.codec.createProfile(this.nextMessageId(), sessionId, 'profile', this.clock(),
      { profile: this.localAdvertisement(profile) }));
  }

  private async submitRemote(task: TaskRequest, _deviceId: string): Promise<TaskSufficiencyResult> {
    this.remoteEvidence = [];
    this.remoteTasks.set(task.taskId, task);
    this.pendingRemoteResolve = null;
    this.pendingRemoteReject = null;
    await this.session.sendEnvelope(this.codec.createTask(this.nextMessageId(), this.remoteSessionId, task.taskId,
      this.clock(), { task: task, round: 1 }));
    this.store.update({ taskPhase: 'AWAITING_L1', taskRound: 1 });
    return await new Promise<TaskSufficiencyResult>((resolve, reject) => {
      this.pendingRemoteResolve = resolve;
      this.pendingRemoteReject = reject;
    });
  }

  private async handleRemoteTask(envelope: ProtocolEnvelope): Promise<void> {
    const payload: TaskPayload = envelope.payload as TaskPayload;
    const task: TaskRequest = payload.task;
    const candidates: EvidenceUnit[] = await this.provider.searchEvidence(task);
    this.remoteCandidates.set(task.taskId, candidates);
    this.remoteTasks.set(task.taskId, task);
    await this.session.sendEnvelope(this.codec.createTaskAck(this.nextMessageId(), envelope.sessionId, task.taskId,
      this.clock(), { taskId: task.taskId, round: payload.round, acceptedAt: this.clock(), candidateCount: candidates.length }));
    await this.sendRemoteEvidence(envelope.sessionId, task, payload.round, candidates, []);
  }

  private async sendRemoteEvidence(sessionId: string, task: TaskRequest, round: number,
    candidates: EvidenceUnit[], alreadySent: EvidenceUnit[]): Promise<void> {
    const schedule = this.scheduler.schedule(task, candidates, round, alreadySent);
    if (schedule.selected.length === 0) {
      return;
    }
    await this.session.sendEnvelope(this.codec.createEvidence(this.nextMessageId(), sessionId, task.taskId, this.clock(),
      { taskId: task.taskId, round: round, evidence: schedule.selected }));
  }

  private handleRemoteEvidence(envelope: ProtocolEnvelope): void {
    const payload: EvidencePayload = envelope.payload as EvidencePayload;
    if (this.activeTaskId !== payload.taskId || this.pendingRemoteResolve === null) {
      return;
    }
    if (payload.round < 1 || payload.round > 2) {
      return;
    }
    let addedEvidence: boolean = false;
    for (const unit of payload.evidence) {
      let duplicate = false;
      for (const existing of this.remoteEvidence) {
        if (existing.evidenceId === unit.evidenceId) {
          duplicate = true;
          break;
        }
      }
      if (!duplicate) {
        this.remoteEvidence.push(unit);
        addedEvidence = true;
      }
    }
    if (!addedEvidence) {
      return;
    }
    const task: TaskRequest | null = this.activeTaskId === payload.taskId ? this.remoteTaskRequest : null;
    if (task === null) {
      return;
    }
    this.recordFirstResult();
    const result: TaskSufficiencyResult = this.evaluator.evaluate(task, this.remoteEvidence, payload.round);
    this.store.update({ taskPhase: payload.round === 1 ? 'EVALUATING_L1' : 'EVALUATING_L2', taskRound: payload.round,
      taskFeedback: result.feedback, taskCoverage: result.coverage, taskConfidence: result.confidence,
      taskMissingConcepts: result.missingConcepts, evidenceBytes: this.evidenceBytes() });
    this.session.sendEnvelope(this.codec.createTsf(this.nextMessageId(), envelope.sessionId, payload.taskId, this.clock(),
      { taskId: payload.taskId, round: payload.round, result: result })).catch((_error: Object) => {});
    if (result.feedback === 'ENOUGH' || payload.round === 2) {
      const resolve = this.pendingRemoteResolve;
      this.pendingRemoteResolve = null;
      this.pendingRemoteReject = null;
      this.activeTaskId = null;
      this.finish(payload.taskId, result.feedback === 'ENOUGH' ? 'SUFFICIENT' : 'ABORTED', payload.round, result);
      if (resolve !== null) {
        resolve(result);
      }
    }
  }

  private handleRemoteTsf(envelope: ProtocolEnvelope): void {
    const payload: TsfPayload = envelope.payload as TsfPayload;
    const task: TaskRequest | undefined = this.remoteTasks.get(payload.taskId);
    const candidates: EvidenceUnit[] | undefined = this.remoteCandidates.get(payload.taskId);
    if (task === undefined || candidates === undefined || payload.result.feedback !== 'NEED_MORE') {
      if (payload.result.feedback === 'ENOUGH' || payload.result.feedback === 'ABORT') {
        this.remoteTasks.delete(payload.taskId);
        this.remoteCandidates.delete(payload.taskId);
      }
      return;
    }
    this.sendRemoteEvidence(envelope.sessionId, task, 2, candidates, []).catch((_error: Object) => {});
  }

  private get remoteTaskRequest(): TaskRequest | null {
    return this.remoteTasks.get(this.activeTaskId ?? '') ?? null;
  }

  private evidenceBytes(): number {
    let total: number = 0;
    for (const unit of this.remoteEvidence) {
      total += unit.byteCost;
    }
    return total;
  }

  private nextMessageId(): string {
    this.messageSequence++;
    return 'semantic-' + this.messageSequence.toString();
  }

  private async runRound(task: TaskRequest, candidates: EvidenceUnit[], round: number,
    alreadySent: EvidenceUnit[]): Promise<TaskSufficiencyResult> {
    this.ensureActive(task.taskId);
    this.store.update({ taskPhase: round === 1 ? 'AWAITING_L1' : 'AWAITING_L2', taskRound: round });
    const schedule = this.scheduler.schedule(task, candidates, round, alreadySent);
    const sent: EvidenceUnit[] = alreadySent.concat(schedule.selected);
    this.store.update({ evidenceBytes: schedule.totalByteCost,
      taskPhase: round === 1 ? 'EVALUATING_L1' : 'EVALUATING_L2' });
    const result: TaskSufficiencyResult = this.evaluator.evaluate(task, sent, round);
    this.recordFirstResult();
    this.store.update({ taskFeedback: result.feedback, taskCoverage: result.coverage,
      taskConfidence: result.confidence, taskMissingConcepts: result.missingConcepts });
    return result;
  }

  private selectedEvidence(task: TaskRequest, candidates: EvidenceUnit[], round: number,
    alreadySent: EvidenceUnit[]): EvidenceUnit[] {
    return alreadySent.concat(this.scheduler.schedule(task, candidates, round, alreadySent).selected);
  }

  private ensureActive(taskId: string): void {
    if (this.cancelledTaskId === taskId) {
      throw new AppError('E_CANCELLED', 'Semantic task cancelled', ErrorStage.LIFECYCLE, true);
    }
  }

  private finish(taskId: string, phase: TaskPhase, round: number, result: TaskSufficiencyResult): void {
    const completionLatencyMs: number = Math.max(0, this.clock() - this.taskStartedAtMs);
    this.latencySamples.push(completionLatencyMs);
    this.store.update({ taskId: taskId, taskPhase: phase, taskRound: round, taskFeedback: result.feedback,
      taskCoverage: result.coverage, taskConfidence: result.confidence, taskMissingConcepts: result.missingConcepts,
      completionLatencyMs: completionLatencyMs, latencySamplesMs: this.latencySamples.slice() });
  }

  private recordFirstResult(): void {
    if (this.firstResultRecorded) {
      return;
    }
    this.firstResultRecorded = true;
    const latencyMs: number = Math.max(0, this.clock() - this.taskStartedAtMs);
    this.latencySamples.push(latencyMs);
    this.store.update({ firstResultLatencyMs: latencyMs, latencySamplesMs: this.latencySamples.slice() });
  }

  private addProtocolBytes(envelope: ProtocolEnvelope): void {
    this.store.update({ protocolBytes: this.store.snapshot().protocolBytes + utf8ByteLength(JSON.stringify(envelope)) });
  }

  private localAdvertisement(profile: KnowledgeProfile): DeviceProfileAdvertisement {
    return {
      semanticContractVersion: '1.0', deviceId: 'local-device', deviceAlias: 'local-device',
      profileVersion: profile.profileVersion, indexVersion: profile.indexVersion,
      indexState: profile.indexState === 'READY' ? 'READY' : 'INDEXING',
      knowledgeDomains: profile.knowledgeDomains.map((domain) => domain.tag),
      modalities: profile.modalities, retrievalModes: profile.retrievalModes,
      supportedLevels: profile.supportedLevels,
      advertisedAtMs: this.clock(), ttlMs: 5 * 60 * 1000
    };
  }

  private localSnapshot(profile: KnowledgeProfile): DeviceRuntimeSnapshot {
    const now: number = this.clock();
    return {
      deviceId: 'local-device', deviceAlias: 'local-device', isLocal: true,
      state: profile.indexState === 'READY' ? 'READY' : 'BUSY', profileVersion: profile.profileVersion,
      indexVersion: profile.indexVersion, lastSeenAtMs: now, averageRttMs: 0, load: 0, advertisedAtMs: now
    };
  }
}
