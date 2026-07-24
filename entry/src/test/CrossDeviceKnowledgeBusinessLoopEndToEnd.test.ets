import { describe, expect, it } from '@ohos/hypium';
import { CrossDeviceQueryResult } from '../main/ets/agent/query/CrossDeviceKnowledgePort';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import { RemoteKnowledgeProfile } from '../main/ets/crossdevice/model/CollaborationModels';
import { InMemoryCollaborationRepositories } from
  '../main/ets/crossdevice/storage/InMemoryCollaborationRepositories';
import { TrustedDeviceDirectory } from
  '../main/ets/crossdevice/trust/TrustedDeviceDirectory';
import {
  HarmonyCrossDeviceKnowledgePort, HarmonyRemoteQueryClient
} from '../main/ets/crossdevice/transport/HarmonyCrossDeviceKnowledgePort';

function evidence(peerKey: string, domain: string): EvidenceUnit {
  return {
    semanticContractVersion: '1.0', evidenceId: peerKey + '-e',
    evidenceGroupId: peerKey + '-g', sourceDeviceId: peerKey,
    sourceDocId: 'remote-evidence', level: 'L1', title: domain,
    summary: domain + ' summary', relevance: 0.9, coveredConcepts: [domain],
    estimatedCoverageGain: 0.9, byteCost: 32, privacyLevel: 'PRIVATE_GROUP',
    privacyCost: 0.1, energyCost: 0, hash: domain, canEscalateTo: ['L1']
  };
}

class ThreeDeviceFakeClient implements HarmonyRemoteQueryClient {
  isPeerConnected(_peerKey: string): boolean {
    return true;
  }
  queriedPeers: string[] = [];
  rejectB: boolean = false;
  deferNext: boolean = false;
  deferredResolve: ((result: CrossDeviceQueryResult) => void) | undefined = undefined;
  cancelledTaskId: string = '';

  query(peerKey: string, request: TaskRequest): Promise<CrossDeviceQueryResult> {
    this.queriedPeers.push(peerKey);
    if (this.deferNext) {
      this.deferNext = false;
      return new Promise<CrossDeviceQueryResult>(
        (resolve: (result: CrossDeviceQueryResult) => void): void => {
          this.deferredResolve = resolve;
        }
      );
    }
    if (peerKey === 'peer-b' && this.rejectB) {
      return Promise.resolve(CrossDeviceQueryResult.failed('REMOTE_LEVEL_DENIED'));
    }
    const domain: string = request.requiredConcepts[0] ?? '';
    return Promise.resolve(CrossDeviceQueryResult.success([evidence(peerKey, domain)]));
  }

  cancel(taskId: string): void {
    this.cancelledTaskId = taskId;
  }

  destroy(): void {}
}

function query(taskId: string, domain: string): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: taskId, queryText: domain,
    requiredConcepts: [domain], requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: 4096, privacyLevel: 'PRIVATE_GROUP',
    acceptableLevels: ['L1']
  };
}

async function waitForDeferred(client: ThreeDeviceFakeClient): Promise<void> {
  for (let attempt: number = 0; attempt < 20; attempt++) {
    if (client.deferredResolve !== undefined) {
      return;
    }
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, 1);
    });
  }
  throw new Error('deferred query was not registered');
}

export default function crossDeviceKnowledgeBusinessLoopEndToEndTest(): void {
  describe('CrossDeviceKnowledgeBusinessLoopEndToEnd', () => {
    it('routes by cached profiles, handles refusal/offline, and drops cancelled late data', 0,
      async () => {
        const repositories = new InMemoryCollaborationRepositories();
        const directory = new TrustedDeviceDirectory(repositories.peers, (): number => 100);
        await directory.observeCandidate('peer-b', 'B', true);
        await directory.trust('peer-b');
        await directory.observeCandidate('peer-c', 'C', true);
        await directory.trust('peer-c');
        await repositories.profiles.save(new RemoteKnowledgeProfile(
          'peer-b', 'v1', 'b', 'READY', ['HarmonyOS'], 1, 1, ['keyword'], ['L1'],
          100, 100, 300100
        ));
        await repositories.profiles.save(new RemoteKnowledgeProfile(
          'peer-c', 'v1', 'c', 'READY', ['数据库'], 1, 1, ['keyword'], ['L1'],
          100, 100, 300100
        ));
        const client = new ThreeDeviceFakeClient();
        const port = new HarmonyCrossDeviceKnowledgePort(
          directory, repositories.profiles, client, (): number => 100
        );

        expect((await port.getRemoteProfiles()).length).assertEqual(2);
        const harmony = await port.search(query('harmony', 'HarmonyOS'));
        expect(client.queriedPeers[0]).assertEqual('peer-b');
        expect(harmony.evidence[0].sourceDeviceId).assertEqual('peer-b');
        const database = await port.search(query('database', '数据库'));
        expect(client.queriedPeers[1]).assertEqual('peer-c');
        expect(database.evidence[0].sourceDeviceId).assertEqual('peer-c');

        client.rejectB = true;
        const denied = await port.search(query('denied', 'HarmonyOS'));
        expect(denied.reason).assertEqual('REMOTE_LEVEL_DENIED');
        await directory.observeCandidate('peer-c', 'C', false);
        expect((await directory.routablePeers()).some(
          (peer): boolean => peer.peerKey === 'peer-c'
        )).assertFalse();

        client.rejectB = false;
        client.deferNext = true;
        const late = port.search(query('cancelled', 'HarmonyOS'));
        await waitForDeferred(client);
        port.cancel('cancelled');
        const resolveLate = client.deferredResolve;
        if (resolveLate === undefined) {
          throw new Error('missing deferred resolver');
        }
        resolveLate(CrossDeviceQueryResult.success([evidence('peer-b', 'HarmonyOS')]));
        expect((await late).cancelled).assertTrue();
        expect(client.cancelledTaskId).assertEqual('cancelled');
      });
  });
}
