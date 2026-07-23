import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeProfile } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import { SemanticKnowledgeProvider } from
  '../main/ets/contracts/semantic/SemanticKnowledgeProvider';
import { CollaborationPeer } from '../main/ets/crossdevice/model/CollaborationModels';
import { SharingPolicy } from '../main/ets/crossdevice/model/SharingPolicy';
import { InMemoryCollaborationRepositories } from
  '../main/ets/crossdevice/storage/InMemoryCollaborationRepositories';
import {
  CollaborationPeerRepository,
  SharingPolicyRepository
} from '../main/ets/crossdevice/storage/CollaborationRepositories';
import {
  InboundRemoteQuery,
  RemoteKnowledgeQueryServer
} from '../main/ets/crossdevice/query/RemoteKnowledgeQueryServer';

class EmptyProvider implements SemanticKnowledgeProvider {
  calls: number = 0;
  getProfile(): Promise<KnowledgeProfile> {
    return Promise.reject(new Error('not used'));
  }
  searchEvidence(_task: TaskRequest): Promise<EvidenceUnit[]> {
    this.calls++;
    return Promise.resolve([]);
  }
}

class DeferredPeerRepository implements CollaborationPeerRepository {
  private resolver: ((peer: CollaborationPeer | undefined) => void) | undefined;
  private resolvedPeer: CollaborationPeer | undefined = undefined;
  private released: boolean = false;
  list(): Promise<CollaborationPeer[]> {
    return Promise.resolve(this.resolvedPeer === undefined ? [] : [this.resolvedPeer]);
  }
  get(_peerKey: string): Promise<CollaborationPeer | undefined> {
    if (this.released) {
      return Promise.resolve(this.resolvedPeer);
    }
    return new Promise<CollaborationPeer | undefined>(
      (resolve: (peer: CollaborationPeer | undefined) => void): void => {
        this.resolver = resolve;
      }
    );
  }
  save(peer: CollaborationPeer): Promise<void> {
    this.resolvedPeer = peer;
    return Promise.resolve();
  }
  release(peer: CollaborationPeer): void {
    this.resolvedPeer = peer;
    this.released = true;
    this.resolver?.(peer);
  }
  ready(): boolean {
    return this.resolver !== undefined;
  }
}

class DeferredPolicyRepository implements SharingPolicyRepository {
  private resolver: ((policy: SharingPolicy) => void) | undefined;
  private current: SharingPolicy;
  private firstLoad: boolean = true;
  constructor(current: SharingPolicy) {
    this.current = current;
  }
  load(): Promise<SharingPolicy> {
    if (!this.firstLoad) {
      return Promise.resolve(this.current);
    }
    this.firstLoad = false;
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
  release(): void {
    this.resolver?.(this.current);
  }
  ready(): boolean {
    return this.resolver !== undefined;
  }
}

async function waitUntil(predicate: () => boolean): Promise<void> {
  for (let attempt: number = 0; attempt < 20; attempt++) {
    if (predicate()) {
      return;
    }
    await Promise.resolve();
  }
  throw new Error('deferred operation did not start');
}

function task(): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: 'task', queryText: 'domain',
    requiredConcepts: ['domain'], requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: 4096, privacyLevel: 'PRIVATE_GROUP',
    acceptableLevels: ['L1']
  };
}

export default function remoteQueryAuthorizationTest(): void {
  describe('RemoteQueryAuthorization', () => {
    it('requires both application trust and live sharing policy', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      const provider = new EmptyProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, repositories.sharingPolicy,
        repositories.accessRecords, (): number => 100
      );
      const unauthorizedRequest = new InboundRemoteQuery(
        'request-1', 'peer', 'Alias', 'domain', 'L1', task(), 200
      );
      expect((await server.handle(unauthorizedRequest)).status).assertEqual('UNAUTHORIZED');
      await repositories.peers.save(CollaborationPeer.pending('peer', 'Alias', 1)
        .withTrustState('TRUSTED', 2));
      const disabledRequest = new InboundRemoteQuery(
        'request-2', 'peer', 'Alias', 'domain', 'L1', task(), 200
      );
      expect((await server.handle(disabledRequest)).status).assertEqual('SHARING_DISABLED');
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 3, 2)
      );
      const allowedRequest = new InboundRemoteQuery(
        'request-3', 'peer', 'Alias', 'domain', 'L1', task(), 200
      );
      expect((await server.handle(allowedRequest)).status).assertEqual('OK');
      expect(provider.calls).assertEqual(1);
      const trusted = await repositories.peers.get('peer');
      if (trusted === undefined) {
        throw new Error('missing peer');
      }
      await repositories.peers.save(trusted.withTrustState('REVOKED', 4));
      expect((await server.handle(allowedRequest)).status).assertEqual('UNAUTHORIZED');
      expect(provider.calls).assertEqual(1);
    });

    it('cancels while peer authorization is pending and cleans the lifecycle', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 3, 2)
      );
      const peers = new DeferredPeerRepository();
      const provider = new EmptyProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, peers, repositories.sharingPolicy,
        repositories.accessRecords, (): number => 100
      );
      const inbound = new InboundRemoteQuery(
        'auth-peer', 'peer', 'Alias', 'domain', 'L1', task(), 200
      );
      const result = server.handle(inbound);
      await waitUntil((): boolean => peers.ready());

      server.cancel('peer', 'auth-peer', 'task');
      server.cancel('peer', 'auth-peer', 'task');
      peers.release(CollaborationPeer.pending('peer', 'Alias', 1)
        .withTrustState('TRUSTED', 2));
      expect((await result).status).assertEqual('CANCELLED');
      expect(provider.calls).assertEqual(0);

      expect((await server.handle(inbound)).status).assertEqual('OK');
      expect(provider.calls).assertEqual(1);
    });

    it('cancels while sharing policy authorization is pending', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'Alias', 1)
        .withTrustState('TRUSTED', 2));
      const policies = new DeferredPolicyRepository(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 3, 2)
      );
      const provider = new EmptyProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, policies,
        repositories.accessRecords, (): number => 100
      );
      const result = server.handle(new InboundRemoteQuery(
        'auth-policy', 'peer', 'Alias', 'domain', 'L1', task(), 200
      ));
      await waitUntil((): boolean => policies.ready());

      server.cancel('peer', 'auth-policy', 'task');
      policies.release();
      expect((await result).status).assertEqual('CANCELLED');
      expect(provider.calls).assertEqual(0);
    });

    it('destroys pending authorization without waiting for its repository', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      const peers = new DeferredPeerRepository();
      const provider = new EmptyProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, peers, repositories.sharingPolicy,
        repositories.accessRecords, (): number => 100
      );
      const result = server.handle(new InboundRemoteQuery(
        'auth-destroy', 'peer', 'Alias', 'domain', 'L1', task(), 200
      ));
      await waitUntil((): boolean => peers.ready());
      let completed: boolean = false;
      result.then((): void => {
        completed = true;
      });

      server.destroy();
      for (let turn: number = 0; turn < 20 && !completed; turn++) {
        await Promise.resolve();
      }
      expect(completed).assertTrue();
      expect((await result).status).assertEqual('CANCELLED');
      peers.release(CollaborationPeer.pending('peer', 'Alias', 1)
        .withTrustState('TRUSTED', 2));
      expect(provider.calls).assertEqual(0);
    });
  });
}
