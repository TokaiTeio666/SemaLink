import { describe, expect, it } from '@ohos/hypium';
import { CrossDeviceQueryResult } from '../main/ets/agent/query/CrossDeviceKnowledgePort';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import {
  CrossDeviceKnowledgeQueryService, CrossDeviceQueryScope,
  LocalEvidenceSearch, RemoteEvidenceSearch
} from '../main/ets/crossdevice/application/CrossDeviceKnowledgeQueryService';

class UnusedLocal implements LocalEvidenceSearch {
  calls: number = 0;
  searchEvidence(_task: TaskRequest): Promise<EvidenceUnit[]> {
    this.calls++;
    return Promise.resolve([]);
  }
}

class UnavailableRemote implements RemoteEvidenceSearch {
  search(_task: TaskRequest): Promise<CrossDeviceQueryResult> {
    return Promise.resolve(CrossDeviceQueryResult.failed('REMOTE_UNAVAILABLE'));
  }
  cancel(_taskId: string): void {}
}

function remoteOnlyTask(): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: 'remote-only', queryText: 'q',
    requiredConcepts: [], requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: 4096, privacyLevel: 'PRIVATE_GROUP',
    acceptableLevels: ['L1']
  };
}

export default function remoteOnlyQueryTest(): void {
  describe('RemoteOnlyQuery', () => {
    it('does not invoke local search and reports unavailable remote explicitly', 0, async () => {
      const local = new UnusedLocal();
      const service = new CrossDeviceKnowledgeQueryService(local, new UnavailableRemote());
      const result = await service.query(remoteOnlyTask(), CrossDeviceQueryScope.REMOTE_ONLY);
      expect(local.calls).assertEqual(0);
      expect(result.evidence.length).assertEqual(0);
      expect(result.failures[0]).assertEqual('REMOTE_UNAVAILABLE');
    });
  });
}
