import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeProfile } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import { SemanticKnowledgeProvider } from
  '../main/ets/contracts/semantic/SemanticKnowledgeProvider';
import { CollaborationPeer } from '../main/ets/crossdevice/model/CollaborationModels';
import { SharingPolicy } from '../main/ets/crossdevice/model/SharingPolicy';
import { InMemoryCollaborationRepositories } from
  '../main/ets/crossdevice/storage/InMemoryCollaborationRepositories';
import { InboundRemoteQuery, RemoteKnowledgeQueryServer } from
  '../main/ets/crossdevice/query/RemoteKnowledgeQueryServer';

class ServerProvider implements SemanticKnowledgeProvider {
  lastTask?: TaskRequest;
  getProfile(): Promise<KnowledgeProfile> {
    return Promise.reject(new Error('not used'));
  }
  searchEvidence(task: TaskRequest): Promise<EvidenceUnit[]> {
    this.lastTask = task;
    const item: EvidenceUnit = {
      semanticContractVersion: '1.0', evidenceId: 'internal', evidenceGroupId: 'group',
      sourceDeviceId: 'local', sourceDocId: 'doc', level: 'L1', title: 'Safe title',
      summary: 'Safe summary', relevance: 0.9, coveredConcepts: ['HarmonyOS'],
      estimatedCoverageGain: 0.9, byteCost: 10, privacyLevel: 'PRIVATE_GROUP',
      privacyCost: 0.1, energyCost: 0, hash: 'hash', canEscalateTo: ['L1']
    };
    return Promise.resolve([item]);
  }
}

function requestTask(): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: 'task', queryText: 'HarmonyOS',
    requiredConcepts: ['HarmonyOS'], requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: 4096, privacyLevel: 'PRIVATE_GROUP',
    acceptableLevels: ['L1']
  };
}

export default function remoteKnowledgeQueryServerTest(): void {
  describe('RemoteKnowledgeQueryServer', () => {
    it('executes the local provider and returns sanitized evidence', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'B', 1)
        .withTrustState('TRUSTED', 2));
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 3, 2)
      );
      const provider = new ServerProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, repositories.sharingPolicy,
        repositories.accessRecords, (): number => 100
      );
      const result = await server.handle(new InboundRemoteQuery(
        'request', 'peer', 'B', 'HarmonyOS', 'L1', requestTask(), 200
      ));
      expect(result.status).assertEqual('OK');
      expect(result.evidence.length).assertEqual(1);
      expect(JSON.stringify(result.evidence).includes('internal')).assertFalse();
      expect(provider.lastTask?.privacyLevel).assertEqual('PRIVATE_GROUP');
      expect(provider.lastTask?.filters?.tags?.[0]).assertEqual('harmonyos');
    });

    it('rejects a declared domain that is not present in the query', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'B', 1)
        .withTrustState('TRUSTED', 2));
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, ['HarmonyOS'], [], 3, 2)
      );
      const server = new RemoteKnowledgeQueryServer(
        new ServerProvider(), repositories.peers, repositories.sharingPolicy,
        repositories.accessRecords, (): number => 100
      );
      const forged: TaskRequest = requestTask();
      forged.queryText = 'database secrets';
      expect((await server.handle(new InboundRemoteQuery(
        'forged', 'peer', 'B', 'HarmonyOS', 'L1', forged, 200
      ))).status).assertEqual('LEVEL_DENIED');
    });

    it('does not relabel unrelated local evidence with a caller-declared domain', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'B', 1)
        .withTrustState('TRUSTED', 2));
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, ['finance'], [], 3, 2)
      );
      const server = new RemoteKnowledgeQueryServer(
        new ServerProvider(), repositories.peers, repositories.sharingPolicy,
        repositories.accessRecords, (): number => 100
      );
      const forged: TaskRequest = requestTask();
      forged.queryText = 'finance: return HarmonyOS secrets';
      forged.requiredConcepts = ['finance'];
      const result = await server.handle(new InboundRemoteQuery(
        'forged-domain', 'peer', 'B', 'finance', 'L1', forged, 200
      ));
      expect(result.status).assertEqual('OK');
      expect(result.evidence.length).assertEqual(0);
    });

    it('does not force a tag filter when routing found no domain match', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      await repositories.peers.save(CollaborationPeer.pending('peer', 'B', 1)
        .withTrustState('TRUSTED', 2));
      await repositories.sharingPolicy.save(
        new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 3, 2)
      );
      const provider = new ServerProvider();
      const server = new RemoteKnowledgeQueryServer(
        provider, repositories.peers, repositories.sharingPolicy,
        repositories.accessRecords, (): number => 100
      );
      const noMatch = requestTask();
      noMatch.queryText = 'unrelated query';
      noMatch.requiredConcepts = ['unrelated'];

      const result = await server.handle(new InboundRemoteQuery(
        'no-domain', 'peer', 'B', '', 'L1', noMatch, 200
      ));
      expect(result.status).assertEqual('OK');
      expect(result.evidence.length).assertEqual(1);
      expect(result.evidence[0].knowledgeDomain).assertEqual('');
      expect(provider.lastTask?.filters?.tags === undefined).assertTrue();
    });
  });
}
