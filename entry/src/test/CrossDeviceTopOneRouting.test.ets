import { describe, expect, it } from '@ohos/hypium';
import { CrossDeviceQueryResult } from
  '../main/ets/agent/query/CrossDeviceKnowledgePort';
import { TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import { RemoteKnowledgeProfile } from '../main/ets/crossdevice/model/CollaborationModels';
import { InMemoryCollaborationRepositories } from
  '../main/ets/crossdevice/storage/InMemoryCollaborationRepositories';
import { TrustedDeviceDirectory } from
  '../main/ets/crossdevice/trust/TrustedDeviceDirectory';
import {
  HarmonyCrossDeviceKnowledgePort,
  HarmonyRemoteQueryClient
} from '../main/ets/crossdevice/transport/HarmonyCrossDeviceKnowledgePort';

class RecordingRemoteClient implements HarmonyRemoteQueryClient {
  peers: string[] = [];
  domains: string[] = [];
  connected: boolean = true;
  isPeerConnected(_peerKey: string): boolean {
    return this.connected;
  }
  query(peerKey: string, _request: TaskRequest,
    matchedDomain: string = ''): Promise<CrossDeviceQueryResult> {
    this.peers.push(peerKey);
    this.domains.push(matchedDomain);
    return Promise.resolve(CrossDeviceQueryResult.success([]));
  }
  cancel(_taskId: string): void {}
  destroy(): void {}
}

function task(): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: 'task', queryText: 'target',
    requiredConcepts: ['target'], requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: 4096, privacyLevel: 'PRIVATE_GROUP',
    acceptableLevels: ['L1']
  };
}

export default function crossDeviceTopOneRoutingTest(): void {
  describe('CrossDeviceTopOneRouting', () => {
    it('queries only the highest ranked trusted online peer', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      const directory = new TrustedDeviceDirectory(repositories.peers, (): number => 100);
      await directory.observeCandidate('peer-a', 'A', true);
      await directory.trust('peer-a');
      await directory.observeCandidate('peer-b', 'B', true);
      await directory.trust('peer-b');
      await repositories.profiles.save(new RemoteKnowledgeProfile(
        'peer-a', 'v1', 'a', 'READY', ['other'], 1, 1, ['keyword'], ['L1'],
        100, 100, 300100
      ));
      await repositories.profiles.save(new RemoteKnowledgeProfile(
        'peer-b', 'v1', 'b', 'READY', ['target'], 1, 1, ['keyword'], ['L1'],
        100, 100, 300100
      ));
      const client = new RecordingRemoteClient();
      const port = new HarmonyCrossDeviceKnowledgePort(
        directory, repositories.profiles, client, (): number => 100
      );
      await port.search(task());
      expect(client.peers.length).assertEqual(1);
      expect(client.peers[0]).assertEqual('peer-b');
    });

    it('routes HarmonyOS to B and sends the actual matched profile domain', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      const directory = new TrustedDeviceDirectory(repositories.peers, (): number => 100);
      await directory.observeCandidate('peer-b', 'B', true);
      await directory.trust('peer-b');
      await directory.observeCandidate('peer-c', 'C', true);
      await directory.trust('peer-c');
      await repositories.profiles.save(new RemoteKnowledgeProfile(
        'peer-b', 'v1', 'b', 'READY', ['HarmonyOS', 'ArkTS'], 1, 1,
        ['keyword'], ['L1'], 100, 100, 300100
      ));
      await repositories.profiles.save(new RemoteKnowledgeProfile(
        'peer-c', 'v1', 'c', 'READY', ['Database'], 1, 1,
        ['keyword'], ['L1'], 100, 100, 300100
      ));
      const client = new RecordingRemoteClient();
      const port = new HarmonyCrossDeviceKnowledgePort(
        directory, repositories.profiles, client, (): number => 100
      );
      const request = task();
      request.queryText = 'HarmonyOS';
      request.requiredConcepts = ['harmonyos'];

      await port.search(request);
      expect(client.peers[0]).assertEqual('peer-b');
      expect(client.domains[0]).assertEqual('HarmonyOS');
    });

    it('routes database to C and sends the actual matched profile domain', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      const directory = new TrustedDeviceDirectory(repositories.peers, (): number => 100);
      await directory.observeCandidate('peer-b', 'B', true);
      await directory.trust('peer-b');
      await directory.observeCandidate('peer-c', 'C', true);
      await directory.trust('peer-c');
      await repositories.profiles.save(new RemoteKnowledgeProfile(
        'peer-b', 'v1', 'b', 'READY', ['HarmonyOS'], 1, 1,
        ['keyword'], ['L1'], 100, 100, 300100
      ));
      await repositories.profiles.save(new RemoteKnowledgeProfile(
        'peer-c', 'v1', 'c', 'READY', ['Database'], 1, 1,
        ['keyword'], ['L1'], 100, 100, 300100
      ));
      const client = new RecordingRemoteClient();
      const port = new HarmonyCrossDeviceKnowledgePort(
        directory, repositories.profiles, client, (): number => 100
      );
      const request = task();
      request.queryText = 'database';
      request.requiredConcepts = ['database'];

      await port.search(request);
      expect(client.peers[0]).assertEqual('peer-c');
      expect(client.domains[0]).assertEqual('Database');
    });

    it('does not route a persisted online peer without a current session mapping', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      const directory = new TrustedDeviceDirectory(repositories.peers, (): number => 100);
      await directory.observeCandidate('peer-b', 'B', true);
      await directory.trust('peer-b');
      await repositories.profiles.save(new RemoteKnowledgeProfile(
        'peer-b', 'v1', 'b', 'READY', ['HarmonyOS'], 1, 1,
        ['keyword'], ['L1'], 100, 100, 300100
      ));
      const client = new RecordingRemoteClient();
      client.connected = false;
      const port = new HarmonyCrossDeviceKnowledgePort(
        directory, repositories.profiles, client, (): number => 100
      );

      const result = await port.search(task());
      expect(result.reason).assertEqual('REMOTE_UNAVAILABLE');
      expect(client.peers.length).assertEqual(0);
    });
  });
}
