import { describe, expect, it } from '@ohos/hypium';
import { CrossDeviceQueryResult } from '../main/ets/agent/query/CrossDeviceKnowledgePort';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import {
  CrossDeviceKnowledgeQueryService, CrossDeviceQueryScope,
  LocalEvidenceSearch, RemoteEvidenceSearch
} from '../main/ets/crossdevice/application/CrossDeviceKnowledgeQueryService';

function localEvidence(): EvidenceUnit {
  return {
    semanticContractVersion: '1.0', evidenceId: 'local', evidenceGroupId: 'local',
    sourceDeviceId: 'local-device', sourceDocId: 'opaque', level: 'L1',
    title: 'Local', summary: 'available', relevance: 0.8, coveredConcepts: [],
    estimatedCoverageGain: 0.8, byteCost: 1, privacyLevel: 'LOCAL_ONLY',
    privacyCost: 0, energyCost: 0, hash: 'local', canEscalateTo: ['L1']
  };
}

class SuccessfulLocal implements LocalEvidenceSearch {
  searchEvidence(_task: TaskRequest): Promise<EvidenceUnit[]> {
    return Promise.resolve([localEvidence()]);
  }
}

class FailedRemote implements RemoteEvidenceSearch {
  search(_task: TaskRequest): Promise<CrossDeviceQueryResult> {
    return Promise.resolve(CrossDeviceQueryResult.timeout());
  }
  cancel(_taskId: string): void {}
}

function combinedTask(): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: 'partial', queryText: 'q',
    requiredConcepts: [], requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: 4096, privacyLevel: 'LOCAL_ONLY',
    acceptableLevels: ['L1']
  };
}

export default function crossDevicePartialFailureTest(): void {
  describe('CrossDevicePartialFailure', () => {
    it('preserves local success when the remote source times out', 0, async () => {
      const service = new CrossDeviceKnowledgeQueryService(
        new SuccessfulLocal(), new FailedRemote()
      );
      const result = await service.query(
        combinedTask(), CrossDeviceQueryScope.LOCAL_AND_REMOTE
      );
      expect(result.evidence.length).assertEqual(1);
      expect(result.evidence[0].sourceDeviceId).assertEqual('local-device');
      expect(result.failures[0]).assertEqual('REMOTE_TIMEOUT');
    });
  });
}
