import { SemanticKnowledgeProvider } from
  '../../contracts/semantic/SemanticKnowledgeProvider';
import {
  EvidenceLevel,
  EvidenceUnit,
  TaskRequest,
  validateTaskRequest
} from '../../contracts/semantic/SemanticModels';
import {
  CollaborationPeer,
  RemoteAccessRecord
} from '../model/CollaborationModels';
import { SharingPolicy } from '../model/SharingPolicy';
import {
  CollaborationPeerRepository,
  RemoteAccessRecordRepository,
  SharingPolicyRepository
} from '../storage/CollaborationRepositories';
import {
  RemoteEvidence,
  RemoteEvidenceSanitizer
} from './RemoteEvidenceSanitizer';
import { normalizeKnowledgeDomain } from
  '../../contracts/semantic/KnowledgeDomainNormalizer';

export type RemoteQueryStatus =
  'OK' |
  'UNAUTHORIZED' |
  'SHARING_DISABLED' |
  'LEVEL_DENIED' |
  'DEADLINE_EXCEEDED' |
  'BUSY' |
  'CANCELLED' |
  'INVALID_REQUEST' |
  'INTERNAL_ERROR';

export class InboundRemoteQuery {
  readonly requestId: string;
  readonly peerKey: string;
  readonly peerAlias: string;
  readonly knowledgeDomain: string;
  readonly requestedLevel: EvidenceLevel;
  readonly task: TaskRequest;
  readonly deadlineAtMs: number;

  constructor(requestId: string, peerKey: string, peerAlias: string,
    knowledgeDomain: string, requestedLevel: EvidenceLevel, task: TaskRequest,
    deadlineAtMs: number) {
    this.requestId = requestId;
    this.peerKey = peerKey;
    this.peerAlias = peerAlias;
    this.knowledgeDomain = knowledgeDomain;
    this.requestedLevel = requestedLevel;
    this.task = task;
    this.deadlineAtMs = deadlineAtMs;
  }
}

export class RemoteQueryResult {
  readonly status: RemoteQueryStatus;
  readonly evidence: RemoteEvidence[];
  readonly truncated: boolean;

  constructor(status: RemoteQueryStatus, evidence: RemoteEvidence[], truncated: boolean) {
    this.status = status;
    this.evidence = evidence;
    this.truncated = truncated;
  }
}

class CachedRemoteQueryResult {
  readonly result: RemoteQueryResult;
  readonly createdAtMs: number;

  constructor(result: RemoteQueryResult, createdAtMs: number) {
    this.result = result;
    this.createdAtMs = createdAtMs;
  }
}

class QueuedRemoteQuery {
  readonly request: InboundRemoteQuery;
  readonly resolve: (result: RemoteQueryResult) => void;
  readonly cacheKey: string;
  readonly startedAtMs: number;
  timer: number = 0;
  settled: boolean = false;
  constructor(request: InboundRemoteQuery,
    resolve: (result: RemoteQueryResult) => void, cacheKey: string = '',
    startedAtMs: number = 0) {
    this.request = request;
    this.resolve = resolve;
    this.cacheKey = cacheKey;
    this.startedAtMs = startedAtMs;
  }
}

type SearchOutcomeKind = 'OK' | 'CANCELLED' | 'DEADLINE_EXCEEDED' | 'INTERNAL_ERROR';

class SearchOutcome {
  readonly kind: SearchOutcomeKind;
  readonly evidence: EvidenceUnit[];
  constructor(kind: SearchOutcomeKind, evidence: EvidenceUnit[] = []) {
    this.kind = kind;
    this.evidence = evidence;
  }
}

class ExecutionLease {
  private released: boolean = false;
  private readonly release: () => void;

  constructor(release: () => void) {
    this.release = release;
  }

  releaseOnce(): boolean {
    if (this.released) {
      return false;
    }
    this.released = true;
    this.release();
    return true;
  }
}

type RequestLifecycleStage = 'AUTHORIZING' | 'QUEUED' | 'ACTIVE' | 'TERMINAL';
type LifecycleCancellationReason = 'NONE' | 'USER' | 'POLICY' | 'DESTROY';

class LifecycleAwaitResult<T> {
  readonly cancelled: boolean;
  readonly value: T | undefined;
  constructor(cancelled: boolean, value?: T) {
    this.cancelled = cancelled;
    this.value = value;
  }
}

class RequestLifecycle {
  stage: RequestLifecycleStage = 'AUTHORIZING';
  cancelled: boolean = false;
  cancellationReason: LifecycleCancellationReason = 'NONE';
  references: number = 0;
  readonly cancellation: Promise<void>;
  private cancelResolve: (() => void) | undefined;

  constructor() {
    this.cancellation = new Promise<void>((resolve: () => void): void => {
      this.cancelResolve = resolve;
    });
  }

  retain(): void {
    this.references++;
  }

  release(): number {
    this.references = Math.max(0, this.references - 1);
    return this.references;
  }

  cancel(reason: LifecycleCancellationReason): void {
    if (this.cancelled || this.stage === 'TERMINAL') {
      return;
    }
    this.cancelled = true;
    this.cancellationReason = reason;
    this.cancelResolve?.();
    this.cancelResolve = undefined;
  }
}

export class RemoteQueryIdempotencyCache {
  private readonly values: Map<string, CachedRemoteQueryResult> =
    new Map<string, CachedRemoteQueryResult>();

  get(requestId: string, nowMs: number): RemoteQueryResult | undefined {
    const cached: CachedRemoteQueryResult | undefined = this.values.get(requestId);
    if (cached === undefined) {
      return undefined;
    }
    if (nowMs - cached.createdAtMs > 5 * 60 * 1000) {
      this.values.delete(requestId);
      return undefined;
    }
    return cached.result;
  }

  put(requestId: string, result: RemoteQueryResult, nowMs: number): void {
    this.values.delete(requestId);
    this.values.set(requestId, new CachedRemoteQueryResult(result, nowMs));
    while (this.values.size > 128) {
      const oldest: string | undefined = this.values.keys().next().value;
      if (oldest === undefined) {
        break;
      }
      this.values.delete(oldest);
    }
  }

  size(): number {
    return this.values.size;
  }
}

export class RemoteKnowledgeQueryServer {
  private readonly provider: SemanticKnowledgeProvider;
  private readonly peers: CollaborationPeerRepository;
  private readonly policies: SharingPolicyRepository;
  private readonly accessRecords: RemoteAccessRecordRepository;
  private readonly clock: () => number;
  private readonly sanitizer: RemoteEvidenceSanitizer = new RemoteEvidenceSanitizer();
  private readonly cache: RemoteQueryIdempotencyCache = new RemoteQueryIdempotencyCache();
  private readonly inFlight: Map<string, Promise<RemoteQueryResult>> =
    new Map<string, Promise<RemoteQueryResult>>();
  private readonly cancelledTaskIds: Set<string> = new Set<string>();
  private readonly queue: QueuedRemoteQuery[] = [];
  private readonly activeTaskIds: Set<string> = new Set<string>();
  private readonly cancelWaiters: Map<string, () => void> =
    new Map<string, () => void>();
  private readonly lifecycles: Map<string, RequestLifecycle> =
    new Map<string, RequestLifecycle>();
  private readonly executionLimitMs: number;
  private activeCount: number = 0;
  private policyEpoch: number = 0;
  private destroyed: boolean = false;

  constructor(provider: SemanticKnowledgeProvider, peers: CollaborationPeerRepository,
    policies: SharingPolicyRepository, accessRecords: RemoteAccessRecordRepository,
    clock: () => number, executionLimitMs: number = 5000) {
    this.provider = provider;
    this.peers = peers;
    this.policies = policies;
    this.accessRecords = accessRecords;
    this.clock = clock;
    this.executionLimitMs = executionLimitMs;
  }

  cancel(peerKey: string, requestId: string, taskId: string): void {
    const key: string = this.executionKey(peerKey, requestId, taskId);
    const lifecycle: RequestLifecycle | undefined = this.lifecycles.get(key);
    lifecycle?.cancel('USER');
    const queuedIndex: number = this.queue.findIndex(
      (item: QueuedRemoteQuery): boolean =>
        this.executionKey(item.request.peerKey, item.request.requestId,
          item.request.task.taskId) === key
    );
    if (queuedIndex >= 0) {
      const queued: QueuedRemoteQuery = this.queue.splice(queuedIndex, 1)[0];
      this.completeQueuedCancellation(queued);
      return;
    }
    if (!this.activeTaskIds.has(key)) {
      return;
    }
    this.cancelledTaskIds.add(key);
    this.cancelWaiters.get(key)?.();
  }

  cancelAll(reason: LifecycleCancellationReason = 'USER'): void {
    this.lifecycles.forEach((lifecycle: RequestLifecycle): void =>
      lifecycle.cancel(reason));
    this.activeTaskIds.forEach((taskId: string): void => {
      this.cancelledTaskIds.add(taskId);
      this.cancelWaiters.get(taskId)?.();
    });
    const queuedItems: QueuedRemoteQuery[] = this.queue.splice(0);
    queuedItems.forEach((queued: QueuedRemoteQuery): void =>
      this.completeQueuedCancellation(
        queued, reason === 'POLICY' ? 'LEVEL_DENIED' : 'CANCELLED'));
  }

  policyChanged(): void {
    this.policyEpoch++;
    this.cancelAll('POLICY');
  }

  destroy(): void {
    if (this.destroyed) {
      return;
    }
    this.destroyed = true;
    this.cancelAll('DESTROY');
    this.cancelWaiters.forEach((cancel: () => void): void => cancel());
    this.cancelWaiters.clear();
  }

  handle(request: InboundRemoteQuery): Promise<RemoteQueryResult> {
    if (this.destroyed) {
      return Promise.resolve(new RemoteQueryResult('CANCELLED', [], false));
    }
    const executionKey: string =
      this.executionKey(request.peerKey, request.requestId, request.task.taskId);
    let lifecycle: RequestLifecycle | undefined = this.lifecycles.get(executionKey);
    if (lifecycle === undefined) {
      lifecycle = new RequestLifecycle();
      this.lifecycles.set(executionKey, lifecycle);
    }
    lifecycle.retain();
    const execution: Promise<RemoteQueryResult> =
      this.handleRegistered(request, executionKey, lifecycle);
    return execution.then((result: RemoteQueryResult): RemoteQueryResult => {
      lifecycle!.stage = 'TERMINAL';
      return result;
    }).finally((): void => {
      if (lifecycle!.release() === 0 &&
        this.lifecycles.get(executionKey) === lifecycle) {
        this.lifecycles.delete(executionKey);
      }
    });
  }

  private async handleRegistered(request: InboundRemoteQuery,
    executionKey: string,
    lifecycle: RequestLifecycle): Promise<RemoteQueryResult> {
    const startedAtMs: number = this.clock();
    if (this.destroyed) {
      return new RemoteQueryResult('CANCELLED', [], false);
    }
    const startingPolicyEpoch: number = this.policyEpoch;
    if (request.deadlineAtMs < startedAtMs) {
      return this.finish(request, 'DEADLINE_EXCEEDED', [], false, startedAtMs);
    }
    let peer: CollaborationPeer | undefined;
    let policy: SharingPolicy;
    try {
      validateTaskRequest(request.task);
      const peerResult: LifecycleAwaitResult<CollaborationPeer | undefined> =
        await this.awaitLifecycle(this.peers.get(request.peerKey), lifecycle);
      if (peerResult.cancelled) {
        return this.finish(
          request, this.cancelledStatus(lifecycle), [], false, startedAtMs);
      }
      peer = peerResult.value;
      if (peer === undefined || peer.trustState !== 'TRUSTED') {
        return this.finish(request, 'UNAUTHORIZED', [], false, startedAtMs);
      }
      const policyResult: LifecycleAwaitResult<SharingPolicy> =
        await this.awaitLifecycle(this.policies.load(), lifecycle);
      if (policyResult.cancelled || policyResult.value === undefined) {
        return this.finish(
          request, this.cancelledStatus(lifecycle), [], false, startedAtMs);
      }
      policy = policyResult.value;
    } catch (_) {
      return this.finish(request, 'INVALID_REQUEST', [], false, startedAtMs);
    }
    if (this.destroyed) {
      return this.finish(request, 'CANCELLED', [], false, startedAtMs);
    }
    if (lifecycle.cancelled) {
      return this.finish(
        request, this.cancelledStatus(lifecycle), [], false, startedAtMs);
    }
    if (startingPolicyEpoch !== this.policyEpoch) {
      return this.finish(request, 'LEVEL_DENIED', [], false, startedAtMs);
    }
    if (!policy.enabled) {
      return this.finish(request, 'SHARING_DISABLED', [], false, startedAtMs);
    }
    if (!this.hasValidDomainBinding(request, policy) ||
      !policy.allows(peer, request.requestedLevel, request.knowledgeDomain)) {
      return this.finish(request, 'LEVEL_DENIED', [], false, startedAtMs);
    }
    const cacheKey: string = request.peerKey + '|' + request.requestId +
      '|' + request.task.taskId +
      '|policy-' + policy.revision;
    const cached: RemoteQueryResult | undefined = this.cache.get(cacheKey, startedAtMs);
    if (cached !== undefined) {
      return cached;
    }
    const duplicate: Promise<RemoteQueryResult> | undefined = this.inFlight.get(cacheKey);
    if (duplicate !== undefined) {
      return duplicate;
    }
    const execution: Promise<RemoteQueryResult> = (async (): Promise<RemoteQueryResult> => {
      if (lifecycle.cancelled || this.cancelledTaskIds.has(executionKey)) {
        return this.finish(
          request, this.cancelledStatus(lifecycle), [], false, startedAtMs, cacheKey);
      }
      if (this.activeCount >= 2) {
        if (this.queue.length >= 4) {
          return this.finish(request, 'BUSY', [], false, startedAtMs, cacheKey);
        }
        return new Promise<RemoteQueryResult>(
          (resolve: (result: RemoteQueryResult) => void): void => {
            lifecycle.stage = 'QUEUED';
            const queued = new QueuedRemoteQuery(
              request, resolve, cacheKey, startedAtMs);
            const delayMs: number = Math.max(1, request.deadlineAtMs - this.clock());
            queued.timer = setTimeout((): void => {
              if (queued.settled) return;
              queued.settled = true;
              const index: number = this.queue.indexOf(queued);
              if (index >= 0) this.queue.splice(index, 1);
              this.finish(request, 'DEADLINE_EXCEEDED', [], false, startedAtMs, cacheKey)
                .then(resolve).catch((): void =>
                  resolve(new RemoteQueryResult('DEADLINE_EXCEEDED', [], false)));
            }, delayMs);
            this.queue.push(queued);
          }
        );
      }
      if (this.destroyed) {
        return this.finish(request, 'CANCELLED', [], false, startedAtMs, cacheKey);
      }
      lifecycle.stage = 'ACTIVE';
      this.activeCount++;
      this.activeTaskIds.add(executionKey);
      const lease = new ExecutionLease((): void => this.releaseExecution());
      try {
        const maximumMs: number = Math.max(
          1,
          Math.min(this.executionLimitMs, request.deadlineAtMs - this.clock())
        );
        const outcome: SearchOutcome = await this.searchBounded(
          request, this.remoteTask(request), maximumMs, lease);
        if (outcome.kind === 'CANCELLED' || lifecycle.cancelled ||
          this.cancelledTaskIds.has(executionKey)) {
          return this.finish(
            request, this.cancelledStatus(lifecycle), [], false, startedAtMs, cacheKey);
        }
        if (outcome.kind === 'DEADLINE_EXCEEDED' || this.clock() > request.deadlineAtMs) {
          return this.finish(request, 'DEADLINE_EXCEEDED', [], false, startedAtMs, cacheKey);
        }
        if (outcome.kind === 'INTERNAL_ERROR') {
          return this.finish(request, 'INTERNAL_ERROR', [], false, startedAtMs, cacheKey);
        }
        const currentPolicyResult: LifecycleAwaitResult<SharingPolicy> =
          await this.awaitLifecycle(this.policies.load(), lifecycle);
        if (currentPolicyResult.cancelled || lifecycle.cancelled) {
          return this.finish(
            request, this.cancelledStatus(lifecycle), [], false, startedAtMs, cacheKey);
        }
        const currentPolicy: SharingPolicy | undefined = currentPolicyResult.value;
        if (currentPolicy === undefined) {
          return this.finish(
            request, 'INTERNAL_ERROR', [], false, startedAtMs, cacheKey);
        }
        if (startingPolicyEpoch !== this.policyEpoch ||
          currentPolicy.revision !== policy.revision || !currentPolicy.enabled ||
          !this.hasValidDomainBinding(request, currentPolicy) ||
          !currentPolicy.allows(peer as CollaborationPeer, request.requestedLevel,
            request.knowledgeDomain)) {
          return this.finish(request, 'LEVEL_DENIED', [], false, startedAtMs, cacheKey);
        }
        const sanitized = this.sanitizer.sanitize(
          outcome.evidence, currentPolicy, request.peerAlias,
          request.knowledgeDomain, this.clock()
        );
        return this.finish(
          request, 'OK', sanitized.evidence, sanitized.truncated, startedAtMs, cacheKey
        );
      } catch (_) {
        return this.finish(request, 'INTERNAL_ERROR', [], false, startedAtMs, cacheKey);
      } finally {
        lease.releaseOnce();
        this.cancelWaiters.delete(executionKey);
        this.cancelledTaskIds.delete(executionKey);
        this.activeTaskIds.delete(executionKey);
      }
    })();
    this.inFlight.set(cacheKey, execution);
    try {
      return await execution;
    } finally {
      if (this.inFlight.get(cacheKey) === execution) {
        this.inFlight.delete(cacheKey);
      }
    }
  }

  private awaitLifecycle<T>(operation: Promise<T>,
    lifecycle: RequestLifecycle): Promise<LifecycleAwaitResult<T>> {
    if (lifecycle.cancelled) {
      return Promise.resolve(new LifecycleAwaitResult<T>(true));
    }
    return Promise.race<LifecycleAwaitResult<T>>([
      operation.then((value: T): LifecycleAwaitResult<T> =>
        new LifecycleAwaitResult<T>(false, value)),
      lifecycle.cancellation.then((): LifecycleAwaitResult<T> =>
        new LifecycleAwaitResult<T>(true))
    ]);
  }

  private searchBounded(request: InboundRemoteQuery, task: TaskRequest,
    timeoutMs: number, lease: ExecutionLease): Promise<SearchOutcome> {
    const executionKey: string =
      this.executionKey(request.peerKey, request.requestId, task.taskId);
    return new Promise<SearchOutcome>((resolve: (outcome: SearchOutcome) => void): void => {
      let settled: boolean = false;
      const finish = (outcome: SearchOutcome): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        lease.releaseOnce();
        resolve(outcome);
      };
      const timer: number = setTimeout((): void => {
        finish(new SearchOutcome('DEADLINE_EXCEEDED'));
      }, timeoutMs);
      this.cancelWaiters.set(executionKey, (): void => {
        finish(new SearchOutcome('CANCELLED'));
      });
      let search: Promise<EvidenceUnit[]>;
      try {
        search = this.provider.searchEvidence(task);
      } catch (_) {
        finish(new SearchOutcome('INTERNAL_ERROR'));
        return;
      }
      search
        .then((evidence: EvidenceUnit[]): void => {
          finish(new SearchOutcome('OK', evidence));
        })
        .catch((): void => {
          finish(new SearchOutcome('INTERNAL_ERROR'));
        });
    });
  }

  private releaseExecution(): void {
    this.activeCount = Math.max(0, this.activeCount - 1);
    this.drainQueue();
  }

  private completeQueuedCancellation(queued: QueuedRemoteQuery,
    status: RemoteQueryStatus = 'CANCELLED'): void {
    if (queued.settled) {
      return;
    }
    queued.settled = true;
    clearTimeout(queued.timer);
    this.finish(
      queued.request, status, [], false,
      queued.startedAtMs, queued.cacheKey
    ).then(queued.resolve).catch((): void =>
      queued.resolve(new RemoteQueryResult(status, [], false)));
  }

  private drainQueue(): void {
    if (this.destroyed) {
      return;
    }
    if (this.activeCount >= 2 || this.queue.length === 0) {
      return;
    }
    const queued: QueuedRemoteQuery | undefined = this.queue.shift();
    if (queued === undefined) {
      return;
    }
    if (queued.settled) {
      this.drainQueue();
      return;
    }
    queued.settled = true;
    clearTimeout(queued.timer);
    this.inFlight.delete(queued.cacheKey);
    this.handle(queued.request)
      .then((result: RemoteQueryResult): void => queued.resolve(result))
      .catch((): void => queued.resolve(
        new RemoteQueryResult('INTERNAL_ERROR', [], false)
      ));
  }

  private async finish(request: InboundRemoteQuery, status: RemoteQueryStatus,
    evidence: RemoteEvidence[], truncated: boolean,
    startedAtMs: number, cacheKey: string = ''): Promise<RemoteQueryResult> {
    const result = new RemoteQueryResult(status, evidence, truncated);
    if (cacheKey.length > 0) {
      this.cache.put(cacheKey, result, this.clock());
    }
    this.accessRecords.save(new RemoteAccessRecord(
      'INBOUND|' + request.peerKey + '|' + request.requestId +
        '|' + request.task.taskId,
      'INBOUND',
      request.peerKey,
      request.task.taskId,
      request.knowledgeDomain.slice(0, 128),
      request.requestedLevel,
      evidence.length,
      status,
      startedAtMs,
      this.clock()
      )).catch((): void => {});
    return result;
  }

  private remoteTask(request: InboundRemoteQuery): TaskRequest {
    const originalFilters = request.task.filters;
    const normalizedDomain: string =
      normalizeKnowledgeDomain(request.knowledgeDomain);
    return {
      semanticContractVersion: request.task.semanticContractVersion,
      taskId: request.task.taskId,
      queryText: request.task.queryText,
      requiredConcepts: request.task.requiredConcepts.slice(),
      requiredConfidence: request.task.requiredConfidence,
      coverageThreshold: request.task.coverageThreshold,
      latencyBudgetMs: request.task.latencyBudgetMs,
      byteBudget: request.task.byteBudget,
      privacyLevel: 'PRIVATE_GROUP',
      acceptableLevels: request.task.acceptableLevels.slice(),
      filters: normalizedDomain.length > 0 ? {
        tags: [normalizedDomain],
        modalities: originalFilters?.modalities?.slice(),
        updatedAfter: originalFilters?.updatedAfter
      } : originalFilters === undefined ? undefined : {
        tags: undefined,
        modalities: originalFilters.modalities?.slice(),
        updatedAfter: originalFilters.updatedAfter
      }
    };
  }

  private hasValidDomainBinding(request: InboundRemoteQuery,
    policy: SharingPolicy): boolean {
    const domain: string = normalizeKnowledgeDomain(request.knowledgeDomain);
    const queryText: string = normalizeKnowledgeDomain(request.task.queryText);
    if (domain.length === 0) {
      return policy.allowedDomains.length === 0;
    }
    if (request.task.requiredConcepts.map((value: string): string =>
      normalizeKnowledgeDomain(value)).indexOf(domain) < 0 ||
      queryText.indexOf(domain) < 0) {
      return false;
    }
    return !policy.deniedDomains.some((denied: string): boolean => {
      const normalized: string = normalizeKnowledgeDomain(denied);
      return normalized.length > 0 && queryText.indexOf(normalized) >= 0;
    });
  }

  private executionKey(peerKey: string, requestId: string,
    taskId: string): string {
    return peerKey + '|' + requestId + '|' + taskId;
  }

  private cancelledStatus(lifecycle: RequestLifecycle): RemoteQueryStatus {
    return lifecycle.cancellationReason === 'POLICY'
      ? 'LEVEL_DENIED' : 'CANCELLED';
  }
}
