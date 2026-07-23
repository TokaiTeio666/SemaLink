import { describe, expect, it } from '@ohos/hypium';
import { CrossDeviceQueryResult } from
  '../main/ets/agent/query/CrossDeviceKnowledgePort';
import {
  DeviceProfileAdvertisement, DeviceRuntimeSnapshot, EvidenceUnit, TaskRequest
} from '../main/ets/contracts/semantic/SemanticModels';
import { DeviceRoutingCandidate } from '../main/ets/communication/DeviceDirectory';
import { DeviceSemanticRouter } from
  '../main/ets/communication/DeviceSemanticRouter';
import {
  CrossDeviceKnowledgeQueryService,
  CrossDeviceQueryScope,
  LocalEvidenceSearch,
  RemoteEvidenceSearch
} from '../main/ets/crossdevice/application/CrossDeviceKnowledgeQueryService';

class ImmediateLocalSearch implements LocalEvidenceSearch {
  searchEvidence(_task: TaskRequest): Promise<EvidenceUnit[]> {
    return Promise.resolve([]);
  }
}

class ForbiddenRemoteSearch implements RemoteEvidenceSearch {
  calls: number = 0;
  search(_task: TaskRequest): Promise<CrossDeviceQueryResult> {
    this.calls++;
    return Promise.resolve(CrossDeviceQueryResult.success([]));
  }
  cancel(_taskId: string): void {}
}

function task(index: number): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: 'perf-' + index, queryText: 'q',
    requiredConcepts: [], requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: 4096, privacyLevel: 'LOCAL_ONLY',
    acceptableLevels: ['L1']
  };
}

function candidate(index: number, domains: string[]): DeviceRoutingCandidate {
  const snapshot: DeviceRuntimeSnapshot = {
    deviceId: 'peer-' + index, deviceAlias: 'Peer', isLocal: false,
    state: 'READY', profileVersion: 'v1', indexVersion: 'i1',
    lastSeenAtMs: 100, averageRttMs: index, load: 0, advertisedAtMs: 100
  };
  const profile: DeviceProfileAdvertisement = {
    semanticContractVersion: '1.0', deviceId: 'peer-' + index, deviceAlias: 'Peer',
    profileVersion: 'v1', indexVersion: 'i1', indexState: 'READY',
    knowledgeDomains: domains, modalities: ['text'], retrievalModes: ['keyword'],
    supportedLevels: ['L1'], advertisedAtMs: 100, ttlMs: 300000
  };
  return { snapshot: snapshot, profile: profile };
}

export default function crossDeviceKnowledgePerformanceTest(): void {
  describe('CrossDeviceKnowledgePerformance', () => {
    it('keeps local-only coordination overhead below ten milliseconds average', 0, async () => {
      const remote = new ForbiddenRemoteSearch();
      const service = new CrossDeviceKnowledgeQueryService(
        new ImmediateLocalSearch(), remote
      );
      const startedAt: number = Date.now();
      for (let index: number = 0; index < 100; index++) {
        await service.query(task(index), CrossDeviceQueryScope.LOCAL_ONLY);
      }
      const averageMs: number = (Date.now() - startedAt) / 100;
      expect(averageMs <= 10).assertTrue();
      expect(remote.calls).assertEqual(0);
    });

    it('routes one hundred cached peers with twenty domains below twenty milliseconds average',
      0, () => {
        const domains: string[] = [];
        for (let domainIndex: number = 0; domainIndex < 20; domainIndex++) {
          domains.push('domain-' + domainIndex);
        }
        const candidates: DeviceRoutingCandidate[] = [];
        for (let peerIndex: number = 0; peerIndex < 100; peerIndex++) {
          candidates.push(candidate(peerIndex, domains));
        }
        const request: TaskRequest = task(1000);
        request.privacyLevel = 'PRIVATE_GROUP';
        request.requiredConcepts = ['domain-7'];
        const router = new DeviceSemanticRouter();
        const startedAt: number = Date.now();
        for (let run: number = 0; run < 100; run++) {
          expect(router.route(request, candidates, 100).routed.length).assertEqual(100);
        }
        expect((Date.now() - startedAt) / 100 <= 20).assertTrue();
      });
  });
}
