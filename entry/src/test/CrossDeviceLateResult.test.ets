import { describe, expect, it } from '@ohos/hypium';
import { CrossDeviceQueryResult } from '../main/ets/agent/query/CrossDeviceKnowledgePort';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import {
  CrossDeviceKnowledgeQueryService, CrossDeviceQueryScope,
  LocalEvidenceSearch, RemoteEvidenceSearch
} from '../main/ets/crossdevice/application/CrossDeviceKnowledgeQueryService';

class EmptyLocal implements LocalEvidenceSearch {
  searchEvidence(_task: TaskRequest): Promise<EvidenceUnit[]> {
    return Promise.resolve([]);
  }
}

class DeferredRemote implements RemoteEvidenceSearch {
  resolvers: Array<(result: CrossDeviceQueryResult) => void> = [];
  search(_task: TaskRequest): Promise<CrossDeviceQueryResult> {
    return new Promise<CrossDeviceQueryResult>(
      (resolve: (result: CrossDeviceQueryResult) => void): void => {
        this.resolvers.push(resolve);
      }
    );
  }
  cancel(_taskId: string): void {}
}

function repeatedTask(): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: 'same-task', queryText: 'q',
    requiredConcepts: [], requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: 4096, privacyLevel: 'PRIVATE_GROUP',
    acceptableLevels: ['L1']
  };
}

export default function crossDeviceLateResultTest(): void {
  describe('CrossDeviceLateResult', () => {
    it('marks an older generation cancelled when it completes late', 0, async () => {
      const remote = new DeferredRemote();
      const service = new CrossDeviceKnowledgeQueryService(new EmptyLocal(), remote);
      const first = service.query(repeatedTask(), CrossDeviceQueryScope.REMOTE_ONLY);
      const second = service.query(repeatedTask(), CrossDeviceQueryScope.REMOTE_ONLY);
      remote.resolvers[1](CrossDeviceQueryResult.success([]));
      expect((await second).cancelled).assertFalse();
      remote.resolvers[0](CrossDeviceQueryResult.success([]));
      expect((await first).cancelled).assertTrue();
    });
  });
}
