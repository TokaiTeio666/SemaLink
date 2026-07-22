import { AppError, ErrorStage } from '../common/AppError';
import { DeviceProfileAdvertisement, DeviceRuntimeSnapshot, EvidenceUnit, TaskPhase, TaskRequest,
  TaskSufficiencyResult, validateTaskRequest } from '../contracts/semantic/SemanticModels';
import { SemanticKnowledgeProvider } from '../contracts/semantic/SemanticKnowledgeProvider';
import { KnowledgeProfile } from '../contracts/knowledge/KnowledgeModels';
import { CancelPayload, EVIDENCE_PAGING_VERSION, ErrorPayload, EvidencePayload, MessageType,
  ProtocolEnvelope, ProfilePayload, TaskPayload, TsfPayload } from '../protocol/ProtocolModels';
import { ProtocolCodec } from '../protocol/ProtocolCodec';
import { EvidencePaginator } from '../protocol/EvidencePaginator';
import {
  ProtocolObserver,
  ProtocolSession
} from './SessionManager';
import { DeviceDirectory } from './DeviceDirectory';
import { DeviceSemanticRouter } from './DeviceSemanticRouter';
import { EvidenceUtilityScheduler } from './EvidenceUtilityScheduler';
import { TaskSufficiencyEvaluator } from './TaskSufficiencyEvaluator';
import { AppStateStore } from '../state/AppStateStore';
import { utf8ByteLength } from '../knowledge/payload/Utf8Sizer';
import { Scheduler, SystemScheduler } from '../common/Scheduler';

const NO_REMOTE_TIMER: number = -1;

enum EvidencePageAddResult {
  ADDED = 'ADDED',
  DUPLICATE = 'DUPLICATE',
  CONFLICT = 'CONFLICT'
}

class EvidencePageAssembly {
  readonly pageCount: number;
  private readonly pages: Map<number, EvidenceUnit[]> = new Map<number, EvidenceUnit[]>();

  constructor(pageCount: number) {
    this.pageCount = pageCount;
  }

  add(pageIndex: number, evidence: EvidenceUnit[]): EvidencePageAddResult {
    const existing: EvidenceUnit[] | undefined = this.pages.get(pageIndex);
    if (existing !== undefined) {
      return this.samePage(existing, evidence)
        ? EvidencePageAddResult.DUPLICATE
        : EvidencePageAddResult.CONFLICT;
    }
    this.pages.set(pageIndex, evidence.slice());
    return EvidencePageAddResult.ADDED;
  }

  isComplete(): boolean {
    return this.pages.size === this.pageCount;
  }

  flatten(): EvidenceUnit[] | null {
    const flattened: EvidenceUnit[] = [];
    const seenEvidence: Map<string, EvidenceUnit> = new Map<string, EvidenceUnit>();
    for (let pageIndex = 0; pageIndex < this.pageCount; pageIndex++) {
      const page: EvidenceUnit[] | undefined = this.pages.get(pageIndex);
      if (page === undefined) {
        return null;
      }
      for (const unit of page) {
        const existing: EvidenceUnit | undefined = seenEvidence.get(unit.evidenceId);
        if (existing === undefined) {
          seenEvidence.set(unit.evidenceId, unit);
          flattened.push(unit);
        } else if (!this.sameUnit(existing, unit)) {
          return null;
        }
      }
    }
    return flattened;
  }

  private samePage(left: EvidenceUnit[], right: EvidenceUnit[]): boolean {
    if (left.length !== right.length) {
      return false;
    }
    for (let i = 0; i < left.length; i++) {
      if (!this.sameUnit(left[i], right[i])) {
        return false;
      }
    }
    return true;
  }

  private sameUnit(left: EvidenceUnit, right: EvidenceUnit): boolean {
    return JSON.stringify(left) === JSON.stringify(right);
  }
}

export class ProgressiveQueryCoordinator implements ProtocolObserver {
  private readonly session: ProtocolSession;
  private readonly store: AppStateStore;
  private readonly provider: SemanticKnowledgeProvider;
  private readonly directory: DeviceDirectory;
  private readonly router: DeviceSemanticRouter;
  private readonly scheduler: EvidenceUtilityScheduler;
  private readonly evaluator: TaskSufficiencyEvaluator;
  private readonly clock: () => number;
  private readonly timerScheduler: Scheduler;
  private readonly codec: ProtocolCodec = new ProtocolCodec();
  private readonly paginator: EvidencePaginator = new EvidencePaginator(this.codec);
  private activeTaskId: string | null = null;
  private cancelledTaskId: string | null = null;
  private remoteSessionId: string = 'semantic-session';
  private remoteEvidence: EvidenceUnit[] = [];
  private remoteCandidates: Map<string, EvidenceUnit[]> = new Map<string, EvidenceUnit[]>();
  private remoteTasks: Map<string, TaskRequest> = new Map<string, TaskRequest>();
  private remotePagingVersions: Map<string, number> = new Map<string, number>();
  private remoteEvidencePages: Map<string, EvidencePageAssembly> = new Map<string, EvidencePageAssembly>();
  private completedEvidenceRounds: Set<string> = new Set<string>();
  private pendingRemoteResolve: ((result: TaskSufficiencyResult) => void) | null = null;
  private pendingRemoteReject: ((reason: Object) => void) | null = null;
  private messageSequence: number = 0;
  private taskStartedAtMs: number = 0;
  private firstResultRecorded: boolean = false;
  private latencySamples: number[] = [];
  private remoteRequestTimerId: number = NO_REMOTE_TIMER;

  constructor(session: ProtocolSession, store: AppStateStore,
    provider: SemanticKnowledgeProvider,
    directory: DeviceDirectory, router: DeviceSemanticRouter, scheduler: EvidenceUtilityScheduler,
    evaluator: TaskSufficiencyEvaluator, clock: () => number = (): number => Date.now(),
    timerScheduler: Scheduler = new SystemScheduler()) {
    this.session = session;
    this.store = store;
    this.provider = provider;
    this.directory = directory;
    this.router = router;
    this.scheduler = scheduler;
    this.evaluator = evaluator;
    this.clock = clock;
    this.timerScheduler = timerScheduler;
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

      const failure: Error = error instanceof Error
        ? error
        : new Error('Semantic task failed');

      this.store.update({
        taskPhase: 'FAILED',
        knowledgeError: failure.message
      });
      throw failure;
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
    const reject = this.pendingRemoteReject;
    this.pendingRemoteResolve = null;
    this.pendingRemoteReject = null;
    this.cancelledTaskId = taskId;
    this.clearTaskCaches(taskId, true);
    this.activeTaskId = null;
    this.store.update({ taskPhase: 'ABORTED', taskFeedback: 'ABORT', taskId: taskId });
    if (reject !== null) {
      reject(new AppError('E_CANCELLED', 'Semantic task cancelled', ErrorStage.LIFECYCLE, true));
    }
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
      this.handleRemoteTask(envelope).catch((error: Object) => {
        const payload: TaskPayload = envelope.payload as TaskPayload;
        this.sendRemoteError(envelope.sessionId, payload.task.taskId, error);
      });
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
    if (envelope.type === MessageType.CANCEL) {
      const payload: CancelPayload = envelope.payload as CancelPayload;
      if (this.activeTaskId === payload.taskId && this.pendingRemoteReject !== null) {
        const reject = this.pendingRemoteReject;
        this.pendingRemoteResolve = null;
        this.pendingRemoteReject = null;
        this.activeTaskId = null;
        this.clearTaskCaches(payload.taskId, true);
        this.store.update({ taskPhase: 'ABORTED', taskFeedback: 'ABORT', knowledgeError: payload.reason });
        reject(new AppError(payload.code, payload.reason, ErrorStage.LIFECYCLE, true));
      } else {
        this.clearTaskCaches(payload.taskId);
      }
      return;
    }
    if (envelope.type === MessageType.ERROR) {
      const payload: ErrorPayload = envelope.payload as ErrorPayload;
      if (this.pendingRemoteReject !== null && envelope.requestId === this.activeTaskId) {
        const reject = this.pendingRemoteReject;
        this.pendingRemoteResolve = null;
        this.pendingRemoteReject = null;
        this.activeTaskId = null;
        this.clearTaskCaches(envelope.requestId, true);
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
    this.remoteEvidencePages.clear();
    this.completedEvidenceRounds.clear();
    this.remoteTasks.set(task.taskId, task);
    this.pendingRemoteResolve = null;
    this.pendingRemoteReject = null;
    await this.session.sendEnvelope(this.codec.createTask(this.nextMessageId(), this.remoteSessionId, task.taskId,
      this.clock(), { task: task, round: 1, evidencePagingVersion: EVIDENCE_PAGING_VERSION }));
    this.store.update({ taskPhase: 'AWAITING_L1', taskRound: 1 });
    return await new Promise<TaskSufficiencyResult>((resolve, reject) => {
      this.pendingRemoteResolve = resolve;
      this.pendingRemoteReject = reject;
      this.startRemoteRequestTimeout(task);
    });
  }

  private async handleRemoteTask(envelope: ProtocolEnvelope): Promise<void> {
    const payload: TaskPayload = envelope.payload as TaskPayload;
    const task: TaskRequest = payload.task;
    const candidates: EvidenceUnit[] = await this.provider.searchEvidence(task);
    this.remoteCandidates.set(task.taskId, candidates);
    this.remoteTasks.set(task.taskId, task);
    if (payload.evidencePagingVersion === EVIDENCE_PAGING_VERSION) {
      this.remotePagingVersions.set(task.taskId, EVIDENCE_PAGING_VERSION);
    } else {
      this.remotePagingVersions.delete(task.taskId);
    }
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
    if (this.remotePagingVersions.get(task.taskId) === EVIDENCE_PAGING_VERSION) {
      const pages: ProtocolEnvelope[] = this.paginator.paginate(this.nextMessageId(), sessionId, task.taskId,
        this.clock(), round, schedule.selected);
      for (const page of pages) {
        await this.session.sendEnvelope(page);
      }
      return;
    }
    await this.session.sendEnvelope(this.codec.createEvidence(this.nextMessageId(), sessionId, task.taskId,
      this.clock(), { taskId: task.taskId, round: round, evidence: schedule.selected }));
  }

  private handleRemoteEvidence(envelope: ProtocolEnvelope): void {
    const payload: EvidencePayload = envelope.payload as EvidencePayload;
    if (this.activeTaskId !== payload.taskId || this.pendingRemoteResolve === null) {
      return;
    }
    if (payload.round < 1 || payload.round > 2) {
      return;
    }
    const pageIndex: number = payload.pageIndex ?? 0;
    const pageCount: number = payload.pageCount ?? 1;
    const pageKey: string = this.evidenceRoundKey(payload.taskId, payload.round);
    if (this.completedEvidenceRounds.has(pageKey)) {
      return;
    }
    let assembly: EvidencePageAssembly | undefined = this.remoteEvidencePages.get(pageKey);
    if (assembly === undefined) {
      assembly = new EvidencePageAssembly(pageCount);
      this.remoteEvidencePages.set(pageKey, assembly);
    } else if (assembly.pageCount !== pageCount) {
      this.failRemoteProtocol(payload.taskId, 'Evidence pages disagree on pageCount');
      return;
    }
    const addResult: EvidencePageAddResult = assembly.add(pageIndex, payload.evidence);
    if (addResult === EvidencePageAddResult.CONFLICT) {
      this.failRemoteProtocol(payload.taskId, 'Conflicting evidence page was received');
      return;
    }
    if (addResult === EvidencePageAddResult.DUPLICATE || !assembly.isComplete()) {
      return;
    }

    this.remoteEvidencePages.delete(pageKey);
    this.completedEvidenceRounds.add(pageKey);
    const roundEvidence: EvidenceUnit[] | null = assembly.flatten();
    if (roundEvidence === null) {
      this.failRemoteProtocol(payload.taskId, 'Conflicting evidence IDs were received across pages');
      return;
    }
    for (const unit of roundEvidence) {
      let duplicate = false;
      for (const existing of this.remoteEvidence) {
        if (existing.evidenceId === unit.evidenceId) {
          duplicate = true;
          break;
        }
      }
      if (!duplicate) {
        this.remoteEvidence.push(unit);
      }
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
      this.clearTaskCaches(payload.taskId, true);
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
        this.clearTaskCaches(payload.taskId);
      }
      return;
    }
    this.sendRemoteEvidence(envelope.sessionId, task, 2, candidates, []).catch((error: Object) => {
      this.sendRemoteError(envelope.sessionId, payload.taskId, error);
    });
  }

  private get remoteTaskRequest(): TaskRequest | null {
    return this.remoteTasks.get(this.activeTaskId ?? '') ?? null;
  }

  private evidenceRoundKey(taskId: string, round: number): string {
    return taskId + '#' + round.toString();
  }

  private clearTaskCaches(taskId: string, clearRequesterState: boolean = false): void {
    this.remoteTasks.delete(taskId);
    this.remoteCandidates.delete(taskId);
    this.remotePagingVersions.delete(taskId);
    if (clearRequesterState) {
      this.remoteEvidencePages.delete(this.evidenceRoundKey(taskId, 1));
      this.remoteEvidencePages.delete(this.evidenceRoundKey(taskId, 2));
      this.completedEvidenceRounds.delete(this.evidenceRoundKey(taskId, 1));
      this.completedEvidenceRounds.delete(this.evidenceRoundKey(taskId, 2));
      this.remoteEvidence = [];
      this.cancelRemoteRequestTimeout();
    }
  }

  private failRemoteProtocol(taskId: string, message: string): void {
    this.failRemoteRequest(taskId, 'E_SEMANTIC_PROTOCOL_INVALID', message);
  }

  private failRemoteRequest(taskId: string, code: string, message: string): void {
    if (this.activeTaskId !== taskId || this.pendingRemoteReject === null) {
      return;
    }
    const reject = this.pendingRemoteReject;
    this.pendingRemoteResolve = null;
    this.pendingRemoteReject = null;
    this.activeTaskId = null;
    this.clearTaskCaches(taskId, true);
    this.store.update({ taskPhase: 'FAILED', knowledgeError: message });
    reject(new AppError(code, message, ErrorStage.PROTOCOL, false));
  }

  private startRemoteRequestTimeout(task: TaskRequest): void {
    this.cancelRemoteRequestTimeout();
    this.remoteRequestTimerId = this.timerScheduler.schedule(task.latencyBudgetMs, (): void => {
      this.remoteRequestTimerId = NO_REMOTE_TIMER;
      this.failRemoteRequest(task.taskId, 'E_EVIDENCE_PAGE_TIMEOUT',
        'Timed out waiting for all evidence pages');
    });
  }

  private cancelRemoteRequestTimeout(): void {
    if (this.remoteRequestTimerId === NO_REMOTE_TIMER) {
      return;
    }
    this.timerScheduler.cancel(this.remoteRequestTimerId);
    this.remoteRequestTimerId = NO_REMOTE_TIMER;
  }

  private sendRemoteError(sessionId: string, taskId: string, error: Object): void {
    let code: string = 'E_EVIDENCE_SEND_FAILED';
    let message: string = 'Evidence delivery failed';
    if (error instanceof AppError) {
      code = error.code;
      message = error.message;
    } else if (error instanceof Error) {
      message = error.message;
    }
    this.clearTaskCaches(taskId);
    this.session.sendEnvelope(this.codec.createError(this.nextMessageId(), sessionId, taskId, this.clock(),
      { code: code, message: message })).catch((_sendError: Object) => {});
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
