import { CrossDeviceQueryResult } from
  '../../agent/query/CrossDeviceKnowledgePort';
import {
  EvidenceUnit,
  TaskRequest
} from '../../contracts/semantic/SemanticModels';

export enum CrossDeviceQueryScope {
  LOCAL_ONLY = 'LOCAL_ONLY',
  REMOTE_ONLY = 'REMOTE_ONLY',
  LOCAL_AND_REMOTE = 'LOCAL_AND_REMOTE'
}

export interface LocalEvidenceSearch {
  searchEvidence(task: TaskRequest): Promise<EvidenceUnit[]>;
}

export interface RemoteEvidenceSearch {
  search(task: TaskRequest): Promise<CrossDeviceQueryResult>;
  cancel(taskId: string): void;
}

export class CrossDeviceKnowledgeQueryResult {
  readonly evidence: EvidenceUnit[];
  readonly queriedLocal: boolean;
  readonly queriedRemote: boolean;
  readonly failures: string[];
  readonly cancelled: boolean;

  constructor(evidence: EvidenceUnit[], queriedLocal: boolean, queriedRemote: boolean,
    failures: string[], cancelled: boolean) {
    this.evidence = evidence;
    this.queriedLocal = queriedLocal;
    this.queriedRemote = queriedRemote;
    this.failures = failures;
    this.cancelled = cancelled;
  }
}

export class CrossDeviceEvidenceMerger {
  merge(input: EvidenceUnit[]): EvidenceUnit[] {
    const byHash: Map<string, EvidenceUnit> = new Map<string, EvidenceUnit>();
    input.forEach((item: EvidenceUnit): void => {
      const existing: EvidenceUnit | undefined = byHash.get(item.hash);
      if (existing === undefined ||
        item.relevance > existing.relevance ||
        (item.relevance === existing.relevance && item.evidenceId < existing.evidenceId)) {
        byHash.set(item.hash, item);
      }
    });
    const ranked: EvidenceUnit[] = Array.from(byHash.values());
    ranked.sort((left: EvidenceUnit, right: EvidenceUnit): number =>
      right.relevance - left.relevance ||
      left.evidenceId.localeCompare(right.evidenceId));

    const perDevice: Map<string, number> = new Map<string, number>();
    const output: EvidenceUnit[] = [];
    for (const item of ranked) {
      const count: number = perDevice.get(item.sourceDeviceId) ?? 0;
      if (count >= 5) {
        continue;
      }
      output.push(item);
      perDevice.set(item.sourceDeviceId, count + 1);
      if (output.length >= 8) {
        break;
      }
    }
    return output;
  }
}

class LocalOutcome {
  readonly evidence: EvidenceUnit[];
  readonly failed: boolean;
  constructor(evidence: EvidenceUnit[], failed: boolean) {
    this.evidence = evidence;
    this.failed = failed;
  }
}

export class CrossDeviceKnowledgeQueryService {
  private readonly local: LocalEvidenceSearch;
  private readonly remote: RemoteEvidenceSearch;
  private readonly merger: CrossDeviceEvidenceMerger = new CrossDeviceEvidenceMerger();
  private readonly generations: Map<string, number> = new Map<string, number>();

  constructor(local: LocalEvidenceSearch, remote: RemoteEvidenceSearch) {
    this.local = local;
    this.remote = remote;
  }

  async query(task: TaskRequest,
    scope: CrossDeviceQueryScope = CrossDeviceQueryScope.LOCAL_ONLY):
    Promise<CrossDeviceKnowledgeQueryResult> {
    const generation: number = this.bumpGeneration(task.taskId);
    const useLocal: boolean = scope !== CrossDeviceQueryScope.REMOTE_ONLY;
    const useRemote: boolean = scope !== CrossDeviceQueryScope.LOCAL_ONLY;

    const localPromise: Promise<LocalOutcome> = useLocal
      ? this.local.searchEvidence(task)
        .then((evidence: EvidenceUnit[]): LocalOutcome => new LocalOutcome(evidence, false))
        .catch((): LocalOutcome => new LocalOutcome([], true))
      : Promise.resolve(new LocalOutcome([], false));
    const remotePromise: Promise<CrossDeviceQueryResult> = useRemote
      ? this.remote.search(this.asRemoteTask(task))
        .catch((): CrossDeviceQueryResult =>
          CrossDeviceQueryResult.failed('REMOTE_QUERY_FAILED'))
      : Promise.resolve(CrossDeviceQueryResult.success([]));

    const outcomes = await Promise.all([localPromise, remotePromise]);
    if (this.generations.get(task.taskId) !== generation) {
      return new CrossDeviceKnowledgeQueryResult([], useLocal, useRemote, [], true);
    }
    const localOutcome: LocalOutcome = outcomes[0] as LocalOutcome;
    const remoteOutcome: CrossDeviceQueryResult = outcomes[1] as CrossDeviceQueryResult;
    const failures: string[] = [];
    if (localOutcome.failed) {
      failures.push('LOCAL_QUERY_FAILED');
    }
    if (useRemote && (remoteOutcome.failedSources > 0 || remoteOutcome.timedOut)) {
      failures.push(remoteOutcome.reason);
    }
    return new CrossDeviceKnowledgeQueryResult(
      this.merger.merge(localOutcome.evidence.concat(remoteOutcome.evidence)),
      useLocal,
      useRemote,
      failures,
      remoteOutcome.cancelled
    );
  }

  cancel(taskId: string): void {
    this.bumpGeneration(taskId);
    this.remote.cancel(taskId);
  }

  private bumpGeneration(taskId: string): number {
    const generation: number = (this.generations.get(taskId) ?? 0) + 1;
    this.generations.delete(taskId);
    this.generations.set(taskId, generation);
    while (this.generations.size > 128) {
      const oldest: string | undefined = this.generations.keys().next().value;
      if (oldest === undefined) {
        break;
      }
      this.generations.delete(oldest);
    }
    return generation;
  }

  private asRemoteTask(task: TaskRequest): TaskRequest {
    return {
      semanticContractVersion: task.semanticContractVersion,
      taskId: task.taskId,
      queryText: task.queryText,
      requiredConcepts: task.requiredConcepts.slice(),
      requiredConfidence: task.requiredConfidence,
      coverageThreshold: task.coverageThreshold,
      latencyBudgetMs: task.latencyBudgetMs,
      byteBudget: task.byteBudget,
      privacyLevel: 'PRIVATE_GROUP',
      acceptableLevels: task.acceptableLevels.slice(),
      filters: task.filters === undefined ? undefined : {
        tags: task.filters.tags?.slice(),
        modalities: task.filters.modalities?.slice(),
        updatedAfter: task.filters.updatedAfter
      }
    };
  }
}
