import { describe, expect, it } from '@ohos/hypium';
import { CrossDeviceQueryResult } from
  '../main/ets/agent/query/CrossDeviceKnowledgePort';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import {
  CrossDeviceKnowledgeQueryService,
  CrossDeviceQueryScope,
  LocalEvidenceSearch,
  RemoteEvidenceSearch
} from '../main/ets/crossdevice/application/CrossDeviceKnowledgeQueryService';

class LocalSearch implements LocalEvidenceSearch {
  calls: number = 0;
  searchEvidence(_task: TaskRequest): Promise<EvidenceUnit[]> {
    this.calls++;
    return Promise.resolve([]);
  }
}

class RemoteSearch implements RemoteEvidenceSearch {
  calls: number = 0;
  lastTask: TaskRequest | undefined = undefined;
  search(task: TaskRequest): Promise<CrossDeviceQueryResult> {
    this.calls++;
    this.lastTask = task;
    return Promise.resolve(CrossDeviceQueryResult.success([]));
  }
  cancel(_taskId: string): void {}
}

function task(): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: 'task', queryText: 'q',
    requiredConcepts: [], requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: 4096, privacyLevel: 'LOCAL_ONLY',
    acceptableLevels: ['L1']
  };
}

export default function localAndRemoteQueryTest(): void {
  describe('CrossDeviceKnowledgeQueryService', () => {
    it('does not touch remote search for the default local scope', 0, async () => {
      const local = new LocalSearch();
      const remote = new RemoteSearch();
      const service = new CrossDeviceKnowledgeQueryService(local, remote);
      await service.query(task(), CrossDeviceQueryScope.LOCAL_ONLY);
      expect(local.calls).assertEqual(1);
      expect(remote.calls).assertEqual(0);
    });

    it('runs both sources only for explicit combined scope', 0, async () => {
      const local = new LocalSearch();
      const remote = new RemoteSearch();
      const service = new CrossDeviceKnowledgeQueryService(local, remote);
      await service.query(task(), CrossDeviceQueryScope.LOCAL_AND_REMOTE);
      expect(local.calls).assertEqual(1);
      expect(remote.calls).assertEqual(1);
    });

    it('removes local document identifiers from a remote request', 0, async () => {
      const remote = new RemoteSearch();
      const service = new CrossDeviceKnowledgeQueryService(new LocalSearch(), remote);
      const filtered: TaskRequest = task();
      filtered.filters = {
        documentIds: ['local-row-id'],
        tags: ['safe-tag'],
        modalities: ['text']
      };
      await service.query(filtered, CrossDeviceQueryScope.REMOTE_ONLY);
      expect(remote.lastTask?.filters?.documentIds === undefined).assertTrue();
      expect(remote.lastTask?.filters?.tags?.[0]).assertEqual('safe-tag');
    });
  });
}
