import { describe, expect, it } from '@ohos/hypium';
import { RemoteQueryIdempotencyCache, RemoteQueryResult } from
  '../main/ets/crossdevice/query/RemoteKnowledgeQueryServer';
import {
  InboundRemoteQuery,
  RemoteKnowledgeQueryServer
} from '../main/ets/crossdevice/query/RemoteKnowledgeQueryServer';
import { KnowledgeProfile } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { EvidenceUnit, TaskRequest } from
  '../main/ets/contracts/semantic/SemanticModels';
import { SemanticKnowledgeProvider } from
  '../main/ets/contracts/semantic/SemanticKnowledgeProvider';
import { CollaborationPeer, RemoteAccessRecord } from
  '../main/ets/crossdevice/model/CollaborationModels';
import { SharingPolicy } from
  '../main/ets/crossdevice/model/SharingPolicy';
import { InMemoryCollaborationRepositories } from
  '../main/ets/crossdevice/storage/InMemoryCollaborationRepositories';
import { RemoteAccessRecordRepository } from
  '../main/ets/crossdevice/storage/CollaborationRepositories';
import { SharingPolicyRepository } from
  '../main/ets/crossdevice/storage/CollaborationRepositories';

class CountingProvider implements SemanticKnowledgeProvider {
  calls: number = 0;
  getProfile(): Promise<KnowledgeProfile> {
    return Promise.reject(new Error('not used'));
  }
  searchEvidence(_task: TaskRequest): Promise<EvidenceUnit[]> {
    this.calls++;
    return Promise.resolve([]);
  }
}

class DeferredAccessRepository implements RemoteAccessRecordRepository {
  saves: number = 0;
  private readonly resolvers: Array<() => void> = [];
  listRecent(_limit: number): Promise<RemoteAccessRecord[]> {
    return Promise.resolve([]);
  }
  save(_record: RemoteAccessRecord): Promise<void> {
    this.saves++;
    return new Promise<void>((resolve: () => void): void => {
      this.resolvers.push(resolve);
    });
  }
  resolveAll(): void {
    this.resolvers.forEach((resolve: () => void): void => resolve());
    this.resolvers.splice(0);
  }
}

class RejectingAccessRepository implements RemoteAccessRecordRepository {
  listRecent(_limit: number): Promise<RemoteAccessRecord[]> {
    return Promise.resolve([]);
  }
  save(_record: RemoteAccessRecord): Promise<void> {
    return Promise.reject(new Error('controlled audit failure'));
  }
}

class DeferredProvider implements SemanticKnowledgeProvider {
  calls: number = 0;
  private resolver: ((evidence: EvidenceUnit[]) => void) | undefined;
  getProfile(): Promise<KnowledgeProfile> {
    return Promise.reject(new Error('not used'));
  }
  searchEvidence(_task: TaskRequest): Promise<EvidenceUnit[]> {
    this.calls++;
    return new Promise<EvidenceUnit[]>(
      (resolve: (evidence: EvidenceUnit[]) => void): void => {
        this.resolver = resolve;
      }
    );
  }
  ready(): boolean {
    return this.resolver !== undefined;
  }
  release(): void {
    this.resolver?.([]);
  }
}

class RecordingAccessRepository implements RemoteAccessRecordRepository {
  readonly statuses: string[] = [];
  listRecent(_limit: number): Promise<RemoteAccessRecord[]> {
    return Promise.resolve([]);
  }
  save(record: RemoteAccessRecord): Promise<void> {
    this.statuses.push(record.status);
    return Promise.resolve();
  }
}

class HookedPolicyRepository implements SharingPolicyRepository {
  loads: number = 0;
  current: SharingPolicy;
  hook: (() => void) | undefined = undefined;
  private readonly hookOnLoad: number;
  constructor(current: SharingPolicy, hookOnLoad: number) {
    this.current = current;
    this.hookOnLoad = hookOnLoad;
  }
  load(): Promise<SharingPolicy> {
    this.loads++;
    const snapshot: SharingPolicy = this.current;
    if (this.loads === this.hookOnLoad) {
      this.hook?.();
    }
    return Promise.resolve(snapshot);
  }
  save(policy: SharingPolicy): Promise<void> {
    this.current = policy;
    return Promise.resolve();
  }
}

class CachedResultRacePolicyRepository implements SharingPolicyRepository {
  loads: number = 0;
  private current: SharingPolicy;
  private resolver: ((policy: SharingPolicy) => void) | undefined;
  constructor(current: SharingPolicy) {
    this.current = current;
  }
  load(): Promise<SharingPolicy> {
    this.loads++;
    if (this.loads !== 3) {
      return Promise.resolve(this.current);
    }
    return new Promise<SharingPolicy>(
      (resolve: (policy: SharingPolicy) => void): void => {
        this.resolver = resolve;
      }
    );
  }
  save(policy: SharingPolicy): Promise<void> {
    this.current = policy;
    return Promise.resolve();
  }
  ready(): boolean {
    return this.resolver !== undefined;
  }
  release(): void {
    this.resolver?.(this.current);
  }
}

async function waitUntil(predicate: () => boolean): Promise<void> {
  for (let attempt: number = 0; attempt < 30; attempt++) {
    if (predicate()) {
      return;
    }
    await Promise.resolve();
  }
  throw new Error('controlled operation did not reach the expected phase');
}

function task(taskId: string): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: taskId, queryText: 'HarmonyOS',
    requiredConcepts: ['harmonyos'], requiredConfidence: 0.8,
    coverageThreshold: 0.8, latencyBudgetMs: 1000, byteBudget: 4096,
    privacyLevel: 'PRIVATE_GROUP', acceptableLevels: ['L1']
  };
}

function request(requestId: string, taskId: string,
  peerKey: string = 'peer'): InboundRemoteQuery {
  return new InboundRemoteQuery(
    requestId, peerKey, 'Peer', 'HarmonyOS', 'L1', task(taskId), 1000
  );
}

function requestAtLevel(requestId: string, taskId: string,
  level: 'L1' | 'L2'): InboundRemoteQuery {
  const query: TaskRequest = task(taskId);
  query.acceptableLevels = [level];
  return new InboundRemoteQuery(
    requestId, 'peer', 'Peer', 'HarmonyOS', level, query, 1000
  );
}

export default function remoteQueryIdempotencyTest(): void {
  describe('RemoteQueryIdempotency', () => {
    it('reuses results for five minutes and caps records at 128', 0, () => {
      const cache = new RemoteQueryIdempotencyCache();
      for (let index: number = 0; index < 140; index++) {
        cache.put('request-' + index, new RemoteQueryResult('OK', [], false), 100);
      }
      expect(cache.size()).assertEqual(128);
      expect(cache.get('request-139', 5 * 60 * 1000) !== undefined).assertTrue();
      expect(cache.get('request-139', 5 * 60 * 1000 + 101) === undefined).assertTrue();
    });

    it('caches before a delayed access audit completes', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'Peer', 1)
        .withTrustState('TRUSTED', 2));
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 2, 2)
      );
      const provider = new CountingProvider();
      const access = new DeferredAccessRepository();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, repositories.sharingPolicy,
        access, (): number => 100
      );

      expect((await server.handle(request('request', 'task'))).status).assertEqual('OK');
      expect((await server.handle(request('request', 'task'))).status).assertEqual('OK');
      expect(provider.calls).assertEqual(1);
      access.resolveAll();
    });

    it('isolates idempotency results by taskId', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'Peer', 1)
        .withTrustState('TRUSTED', 2));
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 2, 2)
      );
      const provider = new CountingProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, repositories.sharingPolicy,
        repositories.accessRecords, (): number => 100
      );

      await server.handle(request('same-request', 'task-a'));
      await server.handle(request('same-request', 'task-b'));
      expect(provider.calls).assertEqual(2);
    });

    it('isolates idempotency results by peer', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer-a', 'Peer A', 1)
        .withTrustState('TRUSTED', 2));
      await repositories.peers.save(CollaborationPeer.pending('peer-b', 'Peer B', 1)
        .withTrustState('TRUSTED', 2));
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 2, 2)
      );
      const provider = new CountingProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, repositories.sharingPolicy,
        repositories.accessRecords, (): number => 100
      );

      await server.handle(request('same-request', 'same-task', 'peer-a'));
      await server.handle(request('same-request', 'same-task', 'peer-b'));
      expect(provider.calls).assertEqual(2);
    });

    it('keeps cached business results when access audit persistence fails', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'Peer', 1)
        .withTrustState('TRUSTED', 2));
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 2, 2)
      );
      const provider = new CountingProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, repositories.sharingPolicy,
        new RejectingAccessRepository(), (): number => 100
      );

      expect((await server.handle(request('audit-failure', 'task'))).status)
        .assertEqual('OK');
      expect((await server.handle(request('audit-failure', 'task'))).status)
        .assertEqual('OK');
      expect(provider.calls).assertEqual(1);
    });

    it('commits only the final denial when sharing changes after provider completion', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'Peer', 1)
        .withTrustState('TRUSTED', 2));
      const allowed = new SharingPolicy(
        true, true, ['L1'], 5, 512, [], [], 2, 2);
      const policies = new HookedPolicyRepository(allowed, 3);
      const provider = new DeferredProvider();
      const access = new RecordingAccessRepository();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, policies, access, (): number => 100
      );
      policies.hook = (): void => {
        policies.current = new SharingPolicy(
          false, true, ['L1'], 5, 512, [], [], 3, 2);
        server.policyChanged();
      };
      const inbound = request('sharing-race', 'sharing-task');
      const first = server.handle(inbound);
      await waitUntil((): boolean => provider.ready());
      const duplicate = server.handle(inbound);
      await waitUntil((): boolean => policies.loads >= 2);

      provider.release();
      const results: RemoteQueryResult[] = await Promise.all([first, duplicate]);
      expect(results[0].status).assertEqual('LEVEL_DENIED');
      expect(results[1].status).assertEqual('LEVEL_DENIED');
      expect(provider.calls).assertEqual(1);
      expect(JSON.stringify(access.statuses)).assertEqual(
        JSON.stringify(['LEVEL_DENIED'])
      );
    });

    it('commits only LEVEL_DENIED when L2 closes before final submission', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'Peer', 1)
        .withTrustState('TRUSTED', 2));
      const policies = new HookedPolicyRepository(
        new SharingPolicy(true, true, ['L1', 'L2'], 5, 512, [], [], 2, 2), 3
      );
      const provider = new DeferredProvider();
      const access = new RecordingAccessRepository();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, policies, access, (): number => 100
      );
      policies.hook = (): void => {
        policies.current = new SharingPolicy(
          true, true, ['L1'], 5, 512, [], [], 3, 2);
        server.policyChanged();
      };
      const inbound = requestAtLevel('l2-race', 'l2-task', 'L2');
      const first = server.handle(inbound);
      await waitUntil((): boolean => provider.ready());
      const duplicate = server.handle(inbound);
      await waitUntil((): boolean => policies.loads >= 2);

      provider.release();
      const results: RemoteQueryResult[] = await Promise.all([first, duplicate]);
      expect(results[0].status).assertEqual('LEVEL_DENIED');
      expect(results[1].status).assertEqual('LEVEL_DENIED');
      expect(provider.calls).assertEqual(1);
      expect(JSON.stringify(access.statuses)).assertEqual(
        JSON.stringify(['LEVEL_DENIED'])
      );
    });

    it('commits only CANCELLED when cancellation wins final policy submission', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'Peer', 1)
        .withTrustState('TRUSTED', 2));
      const policies = new HookedPolicyRepository(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 2, 2), 3
      );
      const provider = new DeferredProvider();
      const access = new RecordingAccessRepository();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, policies, access, (): number => 100
      );
      policies.hook = (): void => {
        server.cancel('peer', 'cancel-race', 'cancel-task');
      };
      const inbound = request('cancel-race', 'cancel-task');
      const first = server.handle(inbound);
      await waitUntil((): boolean => provider.ready());
      const duplicate = server.handle(inbound);
      await waitUntil((): boolean => policies.loads >= 2);

      provider.release();
      const results: RemoteQueryResult[] = await Promise.all([first, duplicate]);
      expect(results[0].status).assertEqual('CANCELLED');
      expect(results[1].status).assertEqual('CANCELLED');
      expect(provider.calls).assertEqual(1);
      expect(JSON.stringify(access.statuses)).assertEqual(
        JSON.stringify(['CANCELLED'])
      );
    });

    it('rechecks denied query domains before committing the final result', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'Peer', 1)
        .withTrustState('TRUSTED', 2));
      const policies = new HookedPolicyRepository(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 2, 2), 99
      );
      const provider = new DeferredProvider();
      const access = new RecordingAccessRepository();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, policies, access, (): number => 100
      );
      const query: TaskRequest = task('domain-race-task');
      query.queryText = 'HarmonyOS private';
      const inbound = new InboundRemoteQuery(
        'domain-race', 'peer', 'Peer', 'HarmonyOS', 'L1', query, 1000
      );
      const first = server.handle(inbound);
      await waitUntil((): boolean => provider.ready());
      const duplicate = server.handle(inbound);
      await waitUntil((): boolean => policies.loads >= 2);
      policies.current = new SharingPolicy(
        true, true, ['L1'], 5, 512, [], ['private'], 3, 2);

      provider.release();
      const results: RemoteQueryResult[] = await Promise.all([first, duplicate]);
      expect(results[0].status).assertEqual('LEVEL_DENIED');
      expect(results[1].status).assertEqual('LEVEL_DENIED');
      expect(provider.calls).assertEqual(1);
      expect(JSON.stringify(access.statuses)).assertEqual(
        JSON.stringify(['LEVEL_DENIED'])
      );
    });

    it('does not return cached OK when cancel follows policy resolution', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'Peer', 1)
        .withTrustState('TRUSTED', 2));
      const policies = new CachedResultRacePolicyRepository(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 2, 2)
      );
      const provider = new CountingProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, policies,
        repositories.accessRecords, (): number => 100
      );
      const inbound = request('cached-cancel', 'cached-cancel-task');
      expect((await server.handle(inbound)).status).assertEqual('OK');
      expect(provider.calls).assertEqual(1);

      const cancelled = server.handle(inbound);
      await waitUntil((): boolean => policies.ready());
      policies.release();
      server.cancel('peer', 'cached-cancel', 'cached-cancel-task');
      expect((await cancelled).status).assertEqual('CANCELLED');
      expect(provider.calls).assertEqual(1);
    });
  });
}
