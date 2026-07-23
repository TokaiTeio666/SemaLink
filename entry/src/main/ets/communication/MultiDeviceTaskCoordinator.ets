import { AppError, ErrorStage } from '../common/AppError';
import { EvidenceUnit, TaskRequest, TaskSufficiencyResult, validateTaskRequest } from '../contracts/semantic/SemanticModels';
import { TaskSufficiencyEvaluator } from './TaskSufficiencyEvaluator';
import { DataEnvelope, EvidenceBatchPayload, EvidencePagePayload, DataPayload, EvidenceAckPayload } from '../protocol/MultiDeviceProtocolModels';
import { EvidenceAggregator, VerifiedEvidence } from './EvidenceAggregator';

export interface PeerTaskState {
  deviceId: string;
  peerTaskId: string;
  status: string;
  allocatedBytes: number;
  receivedBytes: number;
  evidenceCount: number;
  failureCode: string;
}

export interface CoordinatorCandidate {
  deviceId: string;
  isLocal: boolean;
  routeScore: number;
  ready: boolean;
}

export interface CoordinatorTransport {
  send(deviceId: string, envelope: Object): Promise<void>;
  search(deviceId: string, task: TaskRequest, round: 1 | 2): Promise<EvidenceUnit[]>;
}

export interface CoordinatedTaskResult extends TaskSufficiencyResult {
  acceptedEvidence: EvidenceUnit[];
}

export class MultiDeviceTaskCoordinator {
  private activeTaskId: string = '';
  private active = false;
  private readonly evaluator = new TaskSufficiencyEvaluator();
  private readonly aggregator = new EvidenceAggregator();
  private readonly terminalTaskIds = new Set<string>();

  private readonly transport: CoordinatorTransport;
  private readonly candidates: () => CoordinatorCandidate[];

  constructor(transport: CoordinatorTransport, candidates: () => CoordinatorCandidate[]) {
    this.transport = transport;
    this.candidates = candidates;
  }

  async submit(task: TaskRequest): Promise<CoordinatedTaskResult> {
    if (this.active) throw new AppError('E_BUSY', 'Another semantic task is active', ErrorStage.LIFECYCLE, true);
    validateTaskRequest(task);
    this.active = true;
    this.activeTaskId = task.taskId;
    this.aggregator.clear();
    try {
      const ready: CoordinatorCandidate[] = this.candidates().filter((candidate: CoordinatorCandidate): boolean => candidate.ready);
      const local: CoordinatorCandidate | undefined = ready.find((candidate: CoordinatorCandidate): boolean => candidate.isLocal);
      const remotes: CoordinatorCandidate[] = ready.filter((candidate: CoordinatorCandidate): boolean => !candidate.isLocal)
        .sort((left: CoordinatorCandidate, right: CoordinatorCandidate): number => {
          if (right.routeScore !== left.routeScore) return right.routeScore - left.routeScore;
          return left.deviceId.localeCompare(right.deviceId);
        }).slice(0, 2);
      const selected: CoordinatorCandidate[] = [];
      if (local !== undefined) selected.push(local);
      for (const remote of remotes) selected.push(remote);
      if (selected.length === 0) throw new AppError('E_ALL_PEERS_FAILED', 'No ready task participants', ErrorStage.QUERY, true);
      const availableRemoteIds: Set<string> = new Set<string>();
      const remoteSends: Promise<void>[] = [];
      for (const candidate of selected) {
        if (!candidate.isLocal) {
          const envelope: DataEnvelope = this.makeEnvelope(candidate.deviceId, task, 'TASK', { task: task });
          remoteSends.push(this.transport.send(candidate.deviceId, envelope)
            .then((): void => { availableRemoteIds.add(candidate.deviceId); })
            .catch((): void => {}));
        }
      }
      await Promise.all(remoteSends);
      const activeSelected: CoordinatorCandidate[] = selected.filter((candidate: CoordinatorCandidate): boolean =>
        candidate.isLocal || availableRemoteIds.has(candidate.deviceId));
      const roundOne: EvidenceUnit[][] = await Promise.all(activeSelected.map((candidate: CoordinatorCandidate): Promise<EvidenceUnit[]> =>
        this.search(candidate.deviceId, task, 1)));
      for (let index = 0; index < activeSelected.length; index += 1) {
        this.addEvidence(roundOne[index], activeSelected[index].deviceId, 1);
      }
      let result: TaskSufficiencyResult = this.evaluate(task, 1);
      if (result.feedback === 'NEED_MORE' && task.acceptableLevels.indexOf('L2') >= 0) {
        const escalationSends: Promise<void>[] = [];
        for (const candidate of activeSelected) {
          if (!candidate.isLocal) {
            escalationSends.push(this.transport.send(candidate.deviceId,
              this.makeEnvelope(candidate.deviceId, task, 'TSF', {
                taskId: task.taskId, peerTaskId: task.taskId + '@' + candidate.deviceId, round: 1, feedback: 'NEED_MORE'
              })).catch((): void => {}));
          }
        }
        await Promise.all(escalationSends);
        const roundTwo: EvidenceUnit[][] = await Promise.all(activeSelected.map((candidate: CoordinatorCandidate): Promise<EvidenceUnit[]> =>
          this.search(candidate.deviceId, task, 2)));
        for (let index = 0; index < activeSelected.length; index += 1) {
          this.addEvidence(roundTwo[index], activeSelected[index].deviceId, 2);
        }
        result = this.evaluate(task, 2);
      }
      this.terminalTaskIds.add(task.taskId);
      return this.withAcceptedEvidence(result);
    } finally {
      this.active = false;
      this.activeTaskId = '';
    }
  }

  async cancel(taskId: string): Promise<void> {
    if (!this.active || this.activeTaskId !== taskId) return;
    for (const candidate of this.candidates().filter((value: CoordinatorCandidate): boolean => !value.isLocal && value.ready)) {
      const cancel: DataEnvelope = {
        version: '2.0', type: 'CANCEL', messageId: taskId + '-cancel-' + candidate.deviceId, sentAtMs: Date.now(),
        peer: { taskId: taskId, peerTaskId: taskId + '@' + candidate.deviceId, sessionEpoch: 'runtime', sequence: 1 },
        payload: { taskId: taskId, peerTaskId: taskId + '@' + candidate.deviceId, code: 'CANCELLED', reason: 'user_cancelled' }
      };
      await this.transport.send(candidate.deviceId, cancel).catch((): void => {});
    }
    this.terminalTaskIds.add(taskId);
  }

  onEnvelope(deviceId: string, envelope: DataEnvelope): void {
    if (!this.active) return;
    if (envelope.type === 'EVIDENCE_BATCH') {
      const payload: EvidenceBatchPayload = envelope.payload as EvidenceBatchPayload;
      if (payload.taskId === this.activeTaskId) this.addEvidence(payload.evidence, deviceId, payload.round);
      return;
    }
    if (envelope.type === 'EVIDENCE_PAGE') {
      const payload: EvidencePagePayload = envelope.payload as EvidencePagePayload;
      if (payload.taskId !== this.activeTaskId) return;
      this.addEvidence(payload.evidence, deviceId, payload.round);
      const ack: DataEnvelope = {
        version: '2.0', type: 'EVIDENCE_ACK', messageId: envelope.messageId + '-ACK', sentAtMs: Date.now(), peer: envelope.peer,
        payload: { taskId: payload.taskId, peerTaskId: payload.peerTaskId, pageIndex: payload.pageIndex, status: 'OK' } as EvidenceAckPayload
      };
      this.transport.send(deviceId, ack).catch((): void => {});
    }
  }

  destroy(): void {
    this.aggregator.clear();
    this.active = false;
    this.activeTaskId = '';
    this.terminalTaskIds.clear();
  }

  private async search(deviceId: string, task: TaskRequest, round: 1 | 2): Promise<EvidenceUnit[]> {
    try { return await this.transport.search(deviceId, task, round); } catch (_) { return []; }
  }

  private addEvidence(units: EvidenceUnit[], sourceDeviceId: string, round: 1 | 2): void {
    for (const unit of units) {
      const verified: VerifiedEvidence = {
        evidence: unit,
        sourceDeviceId: sourceDeviceId,
        contentDigest: unit.hash,
        round: round
      };
      this.aggregator.add(verified);
    }
  }

  private evaluate(task: TaskRequest, round: 1 | 2): TaskSufficiencyResult {
    const aggregated = this.aggregator.result();
    const valid: EvidenceUnit[] = aggregated.evidence.map((value) => value.evidence);
    if (valid.length === 0 && round === 2) {
      return { feedback: 'ABORT', coverage: 0, confidence: 0, diversity: 0, coveredConcepts: [],
        missingConcepts: task.requiredConcepts.slice(), acceptedEvidenceIds: [] };
    }
    const result = this.evaluator.evaluate(task, valid, round);
    if (task.requiredConcepts.length === 0 && valid.length > 0 && result.feedback !== 'ABORT') {
      const confidence: number = Math.min(1, result.confidence / 0.6);
      return {
        feedback: confidence >= task.requiredConfidence ? 'ENOUGH' : (round === 1 ? 'NEED_MORE' : 'ABORT'),
        coverage: 1,
        confidence: confidence,
        diversity: result.diversity,
        coveredConcepts: result.coveredConcepts,
        missingConcepts: [],
        acceptedEvidenceIds: result.acceptedEvidenceIds
      };
    }
    return result;
  }

  private withAcceptedEvidence(result: TaskSufficiencyResult): CoordinatedTaskResult {
    const acceptedIds = new Set<string>(result.acceptedEvidenceIds);
    const acceptedEvidence: EvidenceUnit[] = [];
    for (const verified of this.aggregator.result().evidence) {
      if (acceptedIds.has(verified.evidence.evidenceId)) {
        acceptedEvidence.push(this.cloneEvidence(verified.evidence));
      }
    }
    return {
      feedback: result.feedback,
      coverage: result.coverage,
      confidence: result.confidence,
      diversity: result.diversity,
      coveredConcepts: result.coveredConcepts.slice(),
      missingConcepts: result.missingConcepts.slice(),
      acceptedEvidenceIds: result.acceptedEvidenceIds.slice(),
      acceptedEvidence: acceptedEvidence
    };
  }

  private cloneEvidence(unit: EvidenceUnit): EvidenceUnit {
    return {
      semanticContractVersion: unit.semanticContractVersion,
      evidenceId: unit.evidenceId,
      evidenceGroupId: unit.evidenceGroupId,
      sourceDeviceId: unit.sourceDeviceId,
      sourceDocId: unit.sourceDocId,
      sourceChunkId: unit.sourceChunkId,
      parentEvidenceId: unit.parentEvidenceId,
      level: unit.level,
      title: unit.title,
      summary: unit.summary,
      snippet: unit.snippet,
      relevance: unit.relevance,
      coveredConcepts: unit.coveredConcepts.slice(),
      estimatedCoverageGain: unit.estimatedCoverageGain,
      byteCost: unit.byteCost,
      privacyLevel: unit.privacyLevel,
      privacyCost: unit.privacyCost,
      energyCost: unit.energyCost,
      hash: unit.hash,
      canEscalateTo: unit.canEscalateTo.slice()
    };
  }

  private makeEnvelope(deviceId: string, task: TaskRequest, type: 'TASK' | 'TSF', payload: DataPayload): DataEnvelope {
    return {
      version: '2.0', type: type, messageId: task.taskId + '-' + type + '-' + deviceId,
      sentAtMs: Date.now(), peer: { taskId: task.taskId, peerTaskId: task.taskId + '@' + deviceId,
        sessionEpoch: 'runtime', sequence: Date.now() }, payload: payload
    };
  }
}
