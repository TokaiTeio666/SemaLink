import { SemanticKnowledgeProvider } from '../../contracts/semantic/SemanticKnowledgeProvider';
import { EvidenceUnit, TaskRequest, TaskSufficiencyResult } from '../../contracts/semantic/SemanticModels';
import { TaskSufficiencyEvaluator } from '../../communication/TaskSufficiencyEvaluator';
import { Scheduler, SystemScheduler } from '../../common/Scheduler';
import { AgentKnowledgeQueryPort } from './AgentKnowledgeQueryPort';
import { AgentQueryRequest, AgentQueryResult, AgentQueryScope } from './AgentQueryModels';
import {
  CrossDeviceAvailability,
  CrossDeviceKnowledgePort,
  CrossDeviceQueryResult
} from './CrossDeviceKnowledgePort';

export class LocalFirstAgentKnowledgeQueryService implements AgentKnowledgeQueryPort {
  private readonly local: SemanticKnowledgeProvider;
  private readonly remote: CrossDeviceKnowledgePort;
  private readonly clock: () => number;
  private readonly evaluator: TaskSufficiencyEvaluator = new TaskSufficiencyEvaluator();
  private readonly cancelled: Set<string> = new Set<string>();
  private readonly active: Set<string> = new Set<string>();
  private readonly remoteTimeoutMs: number;
  private readonly scheduler: Scheduler;

  constructor(local: SemanticKnowledgeProvider, remote: CrossDeviceKnowledgePort,
    clock: () => number = (): number => Date.now(), remoteTimeoutMs: number = 5000,
    scheduler: Scheduler = new SystemScheduler()) {
    this.local = local;
    this.remote = remote;
    this.clock = clock;
    this.remoteTimeoutMs = remoteTimeoutMs;
    this.scheduler = scheduler;
  }

  async query(request: AgentQueryRequest): Promise<AgentQueryResult> {
    this.active.add(request.internalTaskId);
    try {
      return await this.executeQuery(request);
    } finally {
      this.active.delete(request.internalTaskId);
      this.cancelled.delete(request.internalTaskId);
    }
  }

  private async executeQuery(request: AgentQueryRequest): Promise<AgentQueryResult> {
    const startedAt: number = this.clock();
    const task: TaskRequest = this.taskRequest(request);
    const failedSources: string[] = [];
    const localEvidence: EvidenceUnit[] = [];
    const remoteEvidence: EvidenceUnit[] = [];
    let queriedLocal: boolean = false;
    let queriedRemote: boolean = false;
    const availability: CrossDeviceAvailability = this.remote.availability();

    if (request.scope !== AgentQueryScope.REMOTE_ONLY) {
      queriedLocal = true;
      try {
        const found: EvidenceUnit[] = await this.local.searchEvidence(task);
        localEvidence.push(...found);
      } catch (_error) {
        failedSources.push('LOCAL_QUERY_FAILED');
      }
    }
    this.ensureNotCancelled(request.internalTaskId);

    if (request.scope !== AgentQueryScope.LOCAL_ONLY && availability.available) {
      try {
        const remoteResult: CrossDeviceQueryResult = await this.remoteWithTimeout(task);
        queriedRemote = remoteResult.executed;
        if (remoteResult.cancelled) {
          this.cancelled.add(request.internalTaskId);
        } else if (remoteResult.failedSources > 0 || remoteResult.timedOut) {
          failedSources.push(remoteResult.reason);
        }
        remoteEvidence.push(...remoteResult.evidence);
      } catch (_error) {
        queriedRemote = true;
        failedSources.push('REMOTE_QUERY_FAILED');
      }
    }
    this.ensureNotCancelled(request.internalTaskId);

    const evidence: EvidenceUnit[] = this.merge(localEvidence, remoteEvidence);
    const remoteEvidenceIds: string[] = this.remoteIds(evidence, remoteEvidence);
    const sufficiency: TaskSufficiencyResult = this.evaluator.evaluate(task, evidence, 2);
    return new AgentQueryResult(
      request.internalTaskId,
      evidence,
      sufficiency,
      queriedLocal,
      queriedRemote,
      availability.available,
      failedSources,
      Math.max(0, this.clock() - startedAt),
      remoteEvidenceIds,
      request.scope
    );
  }

  private remoteWithTimeout(task: TaskRequest): Promise<CrossDeviceQueryResult> {
    return new Promise<CrossDeviceQueryResult>((resolve: (value: CrossDeviceQueryResult) => void): void => {
      let settled: boolean = false;
      const timerId: number = this.scheduler.schedule(this.remoteTimeoutMs, (): void => {
        if (!settled) {
          settled = true;
          resolve(CrossDeviceQueryResult.timeout());
        }
      });
      this.remote.search(task).then((result: CrossDeviceQueryResult): void => {
        if (!settled) {
          settled = true;
          this.scheduler.cancel(timerId);
          resolve(result);
        }
      }).catch((_error: Object): void => {
        if (!settled) {
          settled = true;
          this.scheduler.cancel(timerId);
          resolve(CrossDeviceQueryResult.failed('REMOTE_QUERY_FAILED'));
        }
      });
    });
  }

  cancel(internalTaskId: string): void {
    if (this.active.has(internalTaskId)) {
      this.cancelled.add(internalTaskId);
    }
    this.remote.cancel(internalTaskId);
  }

  private taskRequest(request: AgentQueryRequest): TaskRequest {
    const concepts: string[] = [request.queryText];
    return {
      semanticContractVersion: '1.0',
      taskId: request.internalTaskId,
      queryText: request.queryText,
      requiredConcepts: concepts,
      requiredConfidence: 0.8,
      coverageThreshold: 0.8,
      latencyBudgetMs: 5000,
      byteBudget: 8192,
      privacyLevel: request.scope === AgentQueryScope.LOCAL_ONLY ? 'LOCAL_ONLY' : 'PRIVATE_GROUP',
      acceptableLevels: ['L1', 'L2']
    };
  }

  private ensureNotCancelled(internalTaskId: string): void {
    if (this.cancelled.has(internalTaskId)) {
      throw new Error('E_AGENT_TASK_CANCELLED');
    }
  }

  private merge(local: EvidenceUnit[], remote: EvidenceUnit[]): EvidenceUnit[] {
    const byHash: Map<string, EvidenceUnit> = new Map<string, EvidenceUnit>();
    const all: EvidenceUnit[] = local.concat(remote);
    for (const unit of all) {
      const existing: EvidenceUnit | undefined = byHash.get(unit.hash);
      if (existing === undefined || unit.evidenceId < existing.evidenceId) {
        byHash.set(unit.hash, unit);
      }
    }
    return Array.from(byHash.values()).sort((left: EvidenceUnit, right: EvidenceUnit): number =>
      right.relevance - left.relevance || left.title.localeCompare(right.title) ||
      left.evidenceId.localeCompare(right.evidenceId));
  }

  private remoteIds(merged: EvidenceUnit[], remote: EvidenceUnit[]): string[] {
    const remoteHashes: Set<string> = new Set<string>();
    for (const unit of remote) {
      remoteHashes.add(unit.hash);
    }
    const ids: string[] = [];
    for (const unit of merged) {
      if (remoteHashes.has(unit.hash)) {
        ids.push(unit.evidenceId);
      }
    }
    return ids.sort();
  }
}
