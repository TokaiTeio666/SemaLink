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
  InboundRemoteQuery,
  RemoteKnowledgeQueryServer,
  RemoteQueryResult
} from '../main/ets/crossdevice/query/RemoteKnowledgeQueryServer';

class BlockingProvider implements SemanticKnowledgeProvider {
  calls: number = 0;
  private resolvers: Array<(evidence: EvidenceUnit[]) => void> = [];
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
    const pending = this.resolvers.slice();
    this.resolvers = [];
    pending.forEach((resolve: (value: EvidenceUnit[]) => void): void => resolve([]));
  }
}

class ThirdCallCompletesProvider implements SemanticKnowledgeProvider {
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

function nextTurn(): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, 1);
  });
}

function task(id: string): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: id, queryText: 'domain',
    requiredConcepts: ['domain'], requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: 4096, privacyLevel: 'PRIVATE_GROUP',
    acceptableLevels: ['L1']
  };
}

export default function remoteQueryConcurrencyLimitTest(): void {
  describe('RemoteQueryConcurrencyLimit', () => {
    it('runs two, queues four, then returns BUSY', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'Peer', 1)
        .withTrustState('TRUSTED', 2));
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 2, 2)
      );
      const provider = new BlockingProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, repositories.sharingPolicy,
        repositories.accessRecords, (): number => 100
      );
      const pending: Promise<RemoteQueryResult>[] = [];
      for (let index: number = 0; index < 6; index++) {
        pending.push(server.handle(new InboundRemoteQuery(
          'request-' + index, 'peer', 'Peer', 'domain', 'L1',
          task('task-' + index), 1000
        )));
      }
      const busy = await server.handle(new InboundRemoteQuery(
        'request-6', 'peer', 'Peer', 'domain', 'L1', task('task-6'), 1000
      ));
      expect(provider.calls).assertEqual(2);
      expect(busy.status).assertEqual('BUSY');
      provider.releaseAll();
      await nextTurn();
      provider.releaseAll();
      await nextTurn();
      provider.releaseAll();
      await nextTurn();
      const completed: RemoteQueryResult[] = await Promise.all(pending);
      expect(completed.every((result: RemoteQueryResult): boolean =>
        result.status === 'OK')).assertTrue();
    });

    it('coalesces duplicate requests that are still in flight', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'Peer', 1)
        .withTrustState('TRUSTED', 2));
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 2, 2)
      );
      const provider = new BlockingProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, repositories.sharingPolicy,
        repositories.accessRecords, (): number => 100
      );
      const request = new InboundRemoteQuery(
        'same-request', 'peer', 'Peer', 'domain', 'L1', task('same-task'), 1000
      );
      const first = server.handle(request);
      const duplicate = server.handle(request);
      await nextTurn();
      expect(provider.calls).assertEqual(1);
      provider.releaseAll();
      const results: RemoteQueryResult[] = await Promise.all([first, duplicate]);
      expect(results[0].status).assertEqual('OK');
      expect(results[1].status).assertEqual('OK');
    });

    it('expires a queued request even when active providers never settle', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'Peer', 1)
        .withTrustState('TRUSTED', 2));
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 2, 2)
      );
      const provider = new BlockingProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, repositories.sharingPolicy,
        repositories.accessRecords, (): number => 100
      );
      server.handle(new InboundRemoteQuery(
        'active-1', 'peer', 'Peer', 'domain', 'L1', task('active-1'), 1000));
      server.handle(new InboundRemoteQuery(
        'active-2', 'peer', 'Peer', 'domain', 'L1', task('active-2'), 1000));
      await nextTurn();
      const queued = await server.handle(new InboundRemoteQuery(
        'queued', 'peer', 'Peer', 'domain', 'L1', task('queued'), 105));
      expect(queued.status).assertEqual('DEADLINE_EXCEEDED');
      provider.releaseAll();
    });

    it('releases timed-out execution slots before providers settle', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'Peer', 1)
        .withTrustState('TRUSTED', 2));
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 2, 2)
      );
      const provider = new ThirdCallCompletesProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, repositories.sharingPolicy,
        repositories.accessRecords, (): number => 100, 1
      );
      const first = server.handle(new InboundRemoteQuery(
        'timeout-1', 'peer', 'Peer', 'domain', 'L1', task('timeout-1'), 1000));
      const second = server.handle(new InboundRemoteQuery(
        'timeout-2', 'peer', 'Peer', 'domain', 'L1', task('timeout-2'), 1000));
      const timedOut: RemoteQueryResult[] = await Promise.all([first, second]);
      expect(timedOut[0].status).assertEqual('DEADLINE_EXCEEDED');
      expect(timedOut[1].status).assertEqual('DEADLINE_EXCEEDED');

      const third = await server.handle(new InboundRemoteQuery(
        'after-timeout', 'peer', 'Peer', 'domain', 'L1',
        task('after-timeout'), 1000
      ));
      expect(provider.calls).assertEqual(3);
      expect(third.status).assertEqual('OK');
    });
  });
}
