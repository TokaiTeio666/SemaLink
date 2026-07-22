import { describe, expect, it } from '@ohos/hypium';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import { EvidenceSchedule, EvidenceUtilityScheduler } from '../main/ets/communication/EvidenceUtilityScheduler';

function task(byteBudget: number = 1000): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: 'schedule-task', queryText: 'query',
    requiredConcepts: ['alpha', 'beta'], requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: byteBudget, privacyLevel: 'PRIVATE_GROUP',
    acceptableLevels: ['L1', 'L2']
  };
}

function evidence(id: string, level: 'L1' | 'L2', concepts: string[], bytes: number,
  relevance: number = 0.9, group: string = id,
  privacyLevel: 'LOCAL_ONLY' | 'PRIVATE_GROUP' = 'PRIVATE_GROUP'): EvidenceUnit {
  return {
    semanticContractVersion: '1.0', evidenceId: id, evidenceGroupId: group,
    sourceDeviceId: 'local-device', sourceDocId: 'doc-' + group,
    parentEvidenceId: level === 'L2' ? 'l1-' + group : undefined, level: level,
    title: id, summary: level === 'L1' ? 'summary' : undefined,
    snippet: level === 'L2' ? 'snippet' : undefined, relevance: relevance,
    coveredConcepts: concepts, estimatedCoverageGain: concepts.length / 2,
    byteCost: bytes, privacyLevel: privacyLevel,
    privacyCost: privacyLevel === 'LOCAL_ONLY' ? 1 : 0.2,
    energyCost: level === 'L1' ? 0.05 : 0.1, hash: 'hash-' + id,
    canEscalateTo: level === 'L1' ? ['L2'] : []
  };
}

export default function evidenceUtilitySchedulerTest(): void {
  describe('EvidenceUtilityScheduler', () => {
    const scheduler: EvidenceUtilityScheduler = new EvidenceUtilityScheduler();

    it('selects only L1 evidence in the first round', 0, () => {
      const result: EvidenceSchedule = scheduler.schedule(task(), [
        evidence('l2-alpha', 'L2', ['alpha'], 200), evidence('l1-alpha', 'L1', ['alpha'], 200)
      ], 1);

      expect(result.selected.length).assertEqual(1);
      expect(result.selected[0].evidenceId).assertEqual('l1-alpha');
    });

    it('selects second-round L2 evidence that adds missing concepts', 0, () => {
      const l1: EvidenceUnit = evidence('l1-alpha', 'L1', ['alpha'], 200);
      const result: EvidenceSchedule = scheduler.schedule(task(), [
        evidence('l2-alpha', 'L2', ['alpha'], 200), evidence('l2-beta', 'L2', ['beta'], 200)
      ], 2, [l1]);

      expect(result.selected.length).assertEqual(1);
      expect(result.selected[0].evidenceId).assertEqual('l2-beta');
    });

    it('does not select already sent evidence and stops at the byte budget', 0, () => {
      const alreadySent: EvidenceUnit = evidence('l1-alpha', 'L1', ['alpha'], 300);
      const result: EvidenceSchedule = scheduler.schedule(task(500), [
        alreadySent, evidence('l1-beta', 'L1', ['beta'], 300), evidence('l1-extra', 'L1', ['alpha'], 300)
      ], 1, [alreadySent]);

      expect(result.selected.length).assertEqual(0);
      expect(result.totalByteCost).assertEqual(300);
    });

    it('does not schedule local-only evidence for a private-group task', 0, () => {
      const result: EvidenceSchedule = scheduler.schedule(task(), [
        evidence('local-only', 'L1', ['alpha'], 200, 1, 'local-only', 'LOCAL_ONLY')
      ], 1);

      expect(result.selected.length).assertEqual(0);
    });

    it('uses evidenceId to break equal MEU ties', 0, () => {
      const result: EvidenceSchedule = scheduler.schedule(task(1000), [
        evidence('b', 'L1', ['alpha'], 200), evidence('a', 'L1', ['alpha'], 200)
      ], 1);

      expect(result.selected[0].evidenceId).assertEqual('a');
      expect(result.selected[1].evidenceId).assertEqual('b');
    });
  });
}
