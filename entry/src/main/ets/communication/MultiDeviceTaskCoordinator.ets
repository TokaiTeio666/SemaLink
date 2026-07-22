import { AppError, ErrorStage } from '../common/AppError';
import { EvidenceUnit, TaskRequest, TaskSufficiencyResult, validateTaskRequest } from '../contracts/semantic/SemanticModels';
import { TaskSufficiencyEvaluator } from './TaskSufficiencyEvaluator';
import { DataEnvelope, EvidenceBatchPayload } from '../protocol/MultiDeviceProtocolModels';
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

interface CancelEnvelope {
  type: 'CANCEL';
  taskId: string;
}

interface TaskEnvelope {
  type: 'TASK';
  taskId: string;
  peerTaskId: string;
  round: 1;
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

  async submit(task: TaskRequest): Promise<TaskSufficiencyResult> {
    if (this.active) throw new AppError('E_BUSY', 'Another semantic task is active', ErrorStage.LIFECYCLE, true);
    validateTaskRequest(task);
    this.active = true;
    this.activeTaskId = task.taskId;
    this.aggregator.clear();
    try {
      const selected: CoordinatorCandidate[] = this.candidates().filter((candidate: CoordinatorCandidate): boolean => candidate.ready)
        .sort((left: CoordinatorCandidate, right: CoordinatorCandidate): number => {
          if (left.isLocal !== right.isLocal) return left.isLocal ? -1 : 1;
          return left.deviceId.localeCompare(right.deviceId);
        }).slice(0, 3);
      if (selected.length === 0) throw new AppError('E_ALL_PEERS_FAILED', 'No ready task participants', ErrorStage.QUERY, true);
      const remoteSends: Promise<void>[] = [];
      for (const candidate of selected) {
        if (!candidate.isLocal) {
          const envelope: TaskEnvelope = {
            type: 'TASK', taskId: task.taskId, peerTaskId: task.taskId + '@' + candidate.deviceId, round: 1
          };
          remoteSends.push(this.transport.send(candidate.deviceId, envelope));
        }
      }
      await Promise.all(remoteSends);
      const roundOne: EvidenceUnit[][] = await Promise.all(selected.map((candidate: CoordinatorCandidate): Promise<EvidenceUnit[]> =>
        this.search(candidate.deviceId, task, 1)));
      for (let index = 0; index < selected.length; index += 1) {
        this.addEvidence(roundOne[index], selected[index].deviceId, 1);
      }
      let result: TaskSufficiencyResult = this.evaluate(task, 1);
      if (result.feedback === 'NEED_MORE' && task.acceptableLevels.indexOf('L2') >= 0) {
        const roundTwo: EvidenceUnit[][] = await Promise.all(selected.map((candidate: CoordinatorCandidate): Promise<EvidenceUnit[]> =>
          this.search(candidate.deviceId, task, 2)));
        for (let index = 0; index < selected.length; index += 1) {
          this.addEvidence(roundTwo[index], selected[index].deviceId, 2);
        }
        result = this.evaluate(task, 2);
      }
      this.terminalTaskIds.add(task.taskId);
      return result;
    } finally {
      this.active = false;
      this.activeTaskId = '';
    }
  }

  async cancel(taskId: string): Promise<void> {
    if (!this.active || this.activeTaskId !== taskId) return;
    for (const candidate of this.candidates().filter((value: CoordinatorCandidate): boolean => !value.isLocal && value.ready)) {
      const cancel: CancelEnvelope = { type: 'CANCEL', taskId: taskId };
      await this.transport.send(candidate.deviceId, cancel);
    }
    this.terminalTaskIds.add(taskId);
  }

  onEnvelope(deviceId: string, envelope: DataEnvelope): void {
    if (!this.active || envelope.type !== 'EVIDENCE_BATCH') return;
    const payload: EvidenceBatchPayload = envelope.payload as EvidenceBatchPayload;
    if (payload.taskId !== this.activeTaskId) return;
    this.addEvidence(payload.evidence, deviceId, payload.round);
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
    return this.evaluator.evaluate(task, valid, round);
  }
}
