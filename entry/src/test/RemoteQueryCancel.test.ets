import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeProfile } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import { SemanticKnowledgeProvider } from
  '../main/ets/contracts/semantic/SemanticKnowledgeProvider';
import { CollaborationPeer } from '../main/ets/crossdevice/model/CollaborationModels';
import { SharingPolicy } from '../main/ets/crossdevice/model/SharingPolicy';
import { InMemoryCollaborationRepositories } from
  '../main/ets/crossdevice/storage/InMemoryCollaborationRepositories';
import { CollaborationPeerRepository } from
  '../main/ets/crossdevice/storage/CollaborationRepositories';
import {
  InboundRemoteQuery,
  RemoteKnowledgeQueryServer,
  RemoteQueryResult
} from '../main/ets/crossdevice/query/RemoteKnowledgeQueryServer';

class CancellableProvider implements SemanticKnowledgeProvider {
  resolve: ((value: EvidenceUnit[]) => void) | undefined = undefined;
  getProfile(): Promise<KnowledgeProfile> {
    return Promise.reject(new Error('not used'));
  }
  searchEvidence(_task: TaskRequest): Promise<EvidenceUnit[]> {
    return new Promise<EvidenceUnit[]>((resolve: (value: EvidenceUnit[]) => void): void => {
      this.resolve = resolve;
    });
  }
}

class TwoCancelledThenCompleteProvider implements SemanticKnowledgeProvider {
  calls: number = 0;
  getProfile(): Promise<KnowledgeProfile> {
    return Promise.reject(new Error('not used'));
  }
  searchEvidence(_task: TaskRequest): Promise<EvidenceUnit[]> {
    this.calls++;
    if (this.calls === 3) {
      return Promise.resolve([]);
    }
    return new Promise<EvidenceUnit[]>(() => {});
  }
}

class DestroyedProvider implements SemanticKnowledgeProvider {
  calls: number = 0;
  private readonly resolvers: Array<(value: EvidenceUnit[]) => void> = [];
  getProfile(): Promise<KnowledgeProfile> {
    return Promise.reject(new Error('not used'));
  }
  searchEvidence(_task: TaskRequest): Promise<EvidenceUnit[]> {
    this.calls++;
    return new Promise<EvidenceUnit[]>((resolve: (value: EvidenceUnit[]) => void): void => {
      this.resolvers.push(resolve);
    });
  }
  releaseAll(): void {
    this.resolvers.forEach((resolve: (value: EvidenceUnit[]) => void): void => resolve([]));
    this.resolvers.splice(0);
  }
}

class DeferredPeerRepository implements CollaborationPeerRepository {
  private resolver: ((peer: CollaborationPeer | undefined) => void) | undefined;
  list(): Promise<CollaborationPeer[]> {
    return Promise.resolve([]);
  }
  get(_peerKey: string): Promise<CollaborationPeer | undefined> {
    return new Promise<CollaborationPeer | undefined>(
      (resolve: (peer: CollaborationPeer | undefined) => void): void => {
        this.resolver = resolve;
      }
    );
  }
  save(_peer: CollaborationPeer): Promise<void> {
    return Promise.resolve();
  }
  release(peer: CollaborationPeer): void {
    this.resolver?.(peer);
  }
  ready(): boolean {
    return this.resolver !== undefined;
  }
}

function request(): InboundRemoteQuery {
  return new InboundRemoteQuery(
    'request', 'peer', 'Peer', 'domain', 'L1',
    {
      semanticContractVersion: '1.0', taskId: 'task', queryText: 'domain',
      requiredConcepts: ['domain'], requiredConfidence: 0.8, coverageThreshold: 0.8,
      latencyBudgetMs: 1000, byteBudget: 4096, privacyLevel: 'PRIVATE_GROUP',
      acceptableLevels: ['L1']
    },
    1000
  );
}

function taskWithId(taskId: string): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: taskId, queryText: 'domain',
    requiredConcepts: ['domain'], requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: 4096, privacyLevel: 'PRIVATE_GROUP',
    acceptableLevels: ['L1']
  };
}

async function waitForProvider(provider: CancellableProvider): Promise<void> {
  for (let attempt: number = 0; attempt < 20; attempt++) {
    if (provider.resolve !== undefined) {
      return;
    }
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, 1);
    });
  }
  throw new Error('provider did not start');
}

export default function remoteQueryCancelTest(): void {
  describe('RemoteQueryCancel', () => {
    it('drops a running result after application cancellation', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'Peer', 1)
        .withTrustState('TRUSTED', 2));
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 2, 2)
      );
      const provider = new CancellableProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, repositories.sharingPolicy,
        repositories.accessRecords, (): number => 100
      );
      const result = server.handle(request());
      await waitForProvider(provider);
      server.cancel('peer', 'request', 'task');
      provider.resolve?.([]);
      expect((await result).status).assertEqual('CANCELLED');
    });

    it('releases cancelled execution slots before providers settle', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'Peer', 1)
        .withTrustState('TRUSTED', 2));
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 2, 2)
      );
      const provider = new TwoCancelledThenCompleteProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, repositories.sharingPolicy,
        repositories.accessRecords, (): number => 100
      );
      const first = server.handle(new InboundRemoteQuery(
        'cancel-1', 'peer', 'Peer', 'domain', 'L1',
        taskWithId('cancel-1'), 1000
      ));
      const second = server.handle(new InboundRemoteQuery(
        'cancel-2', 'peer', 'Peer', 'domain', 'L1',
        taskWithId('cancel-2'), 1000
      ));
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, 1);
      });
      server.cancel('peer', 'cancel-1', 'cancel-1');
      server.cancel('peer', 'cancel-2', 'cancel-2');
      const cancelled = await Promise.all([first, second]);
      expect(cancelled[0].status).assertEqual('CANCELLED');
      expect(cancelled[1].status).assertEqual('CANCELLED');

      const third = await server.handle(new InboundRemoteQuery(
        'after-cancel', 'peer', 'Peer', 'domain', 'L1',
        taskWithId('after-cancel'), 1000
      ));
      expect(provider.calls).assertEqual(3);
      expect(third.status).assertEqual('OK');
    });

    it('cancels active and queued work on destroy and ignores late provider results', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'Peer', 1)
        .withTrustState('TRUSTED', 2));
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 2, 2)
      );
      const provider = new DestroyedProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, repositories.sharingPolicy,
        repositories.accessRecords, (): number => 100
      );
      const pending: Promise<RemoteQueryResult>[] = [
        server.handle(new InboundRemoteQuery(
          'destroy-1', 'peer', 'Peer', 'domain', 'L1',
          taskWithId('destroy-1'), 1000)),
        server.handle(new InboundRemoteQuery(
          'destroy-2', 'peer', 'Peer', 'domain', 'L1',
          taskWithId('destroy-2'), 1000)),
        server.handle(new InboundRemoteQuery(
          'destroy-queued', 'peer', 'Peer', 'domain', 'L1',
          taskWithId('destroy-queued'), 1000))
      ];
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, 1);
      });
      expect(provider.calls).assertEqual(2);

      server.destroy();
      const cancelled: RemoteQueryResult[] = await Promise.all(pending);
      expect(cancelled.every((result: RemoteQueryResult): boolean =>
        result.status === 'CANCELLED')).assertTrue();
      provider.releaseAll();
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, 1);
      });
      expect(provider.calls).assertEqual(2);
      expect((await server.handle(request())).status).assertEqual('CANCELLED');
    });

    it('completes queued cancellation without waiting for active providers', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'Peer', 1)
        .withTrustState('TRUSTED', 2));
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 2, 2)
      );
      const provider = new DestroyedProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, repositories.sharingPolicy,
        repositories.accessRecords, (): number => 100
      );
      const first = server.handle(new InboundRemoteQuery(
        'active-a', 'peer', 'Peer', 'domain', 'L1',
        taskWithId('active-a'), 1000));
      const second = server.handle(new InboundRemoteQuery(
        'active-b', 'peer', 'Peer', 'domain', 'L1',
        taskWithId('active-b'), 1000));
      const queued = server.handle(new InboundRemoteQuery(
        'queued-cancel', 'peer', 'Peer', 'domain', 'L1',
        taskWithId('queued-cancel'), 1000));
      for (let attempt: number = 0; attempt < 20 && provider.calls < 2; attempt++) {
        await Promise.resolve();
      }
      expect(provider.calls).assertEqual(2);

      server.cancel('peer', 'queued-cancel', 'queued-cancel');
      expect((await queued).status).assertEqual('CANCELLED');
      expect(provider.calls).assertEqual(2);
      server.destroy();
      await Promise.all([first, second]);
    });

    it('does not resume authorization work after server destruction', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 2, 2)
      );
      const peers = new DeferredPeerRepository();
      const provider = new DestroyedProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, peers, repositories.sharingPolicy,
        repositories.accessRecords, (): number => 100
      );
      const result = server.handle(request());
      for (let attempt: number = 0; attempt < 20 && !peers.ready(); attempt++) {
        await Promise.resolve();
      }
      expect(peers.ready()).assertTrue();

      server.destroy();
      peers.release(CollaborationPeer.pending('peer', 'Peer', 1)
        .withTrustState('TRUSTED', 2));
      expect((await result).status).assertEqual('CANCELLED');
      expect(provider.calls).assertEqual(0);
    });
  });
}
