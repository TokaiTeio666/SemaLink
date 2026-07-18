import { describe, expect, it } from '@ohos/hypium';
import { EvidenceUnit, TaskRequest, TaskSufficiencyResult } from '../main/ets/contracts/semantic/SemanticModels';
import { TaskSufficiencyEvaluator } from '../main/ets/communication/TaskSufficiencyEvaluator';

function task(): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: 'evaluation-task', queryText: 'query',
    requiredConcepts: ['alpha', 'beta'], requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: 1000, privacyLevel: 'PRIVATE_GROUP',
    acceptableLevels: ['L1', 'L2']
  };
}

function unit(id: string, concepts: string[], relevance: number, group: string): EvidenceUnit {
  return {
    semanticContractVersion: '1.0', evidenceId: id, evidenceGroupId: group,
    sourceDeviceId: 'local-device', sourceDocId: 'doc-' + group, level: 'L1', title: id,
    summary: 'summary', relevance: relevance, coveredConcepts: concepts,
    estimatedCoverageGain: concepts.length / 2, byteCost: 200,
    privacyLevel: 'PRIVATE_GROUP', privacyCost: 0.2, energyCost: 0.05,
    hash: 'hash-' + id, canEscalateTo: ['L2']
  };
}

export default function taskSufficiencyEvaluatorTest(): void {
  describe('TaskSufficiencyEvaluator', () => {
    const evaluator: TaskSufficiencyEvaluator = new TaskSufficiencyEvaluator();

    it('returns ENOUGH when coverage and confidence reach 0.80', 0, () => {
      const result: TaskSufficiencyResult = evaluator.evaluate(task(), [
        unit('ev-alpha', ['alpha'], 1, 'group-a'), unit('ev-beta', ['beta'], 1, 'group-b')
      ], 2);

      expect(result.feedback).assertEqual('ENOUGH');
      expect(result.coverage).assertEqual(1);
      expect(result.confidence).assertEqual(1);
      expect(result.diversity).assertEqual(1);
    });

    it('returns NEED_MORE after an insufficient first round', 0, () => {
      const result: TaskSufficiencyResult = evaluator.evaluate(task(), [
        unit('ev-alpha', ['alpha'], 0.9, 'group-a')
      ], 1);

      expect(result.feedback).assertEqual('NEED_MORE');
      expect(result.coverage).assertEqual(0.5);
      expect(result.missingConcepts.length).assertEqual(1);
    });

    it('returns ABORT when the second round remains insufficient', 0, () => {
      const result: TaskSufficiencyResult = evaluator.evaluate(task(), [
        unit('ev-alpha', ['alpha'], 0.9, 'group-a')
      ], 2);

      expect(result.feedback).assertEqual('ABORT');
    });

    it('deduplicates evidence IDs before calculating diversity and confidence', 0, () => {
      const first: EvidenceUnit = unit('ev-alpha', ['alpha'], 0.9, 'group-a');
      const result: TaskSufficiencyResult = evaluator.evaluate(task(), [first, first], 1);

      expect(result.acceptedEvidenceIds.length).assertEqual(1);
      expect(result.diversity).assertEqual(1);
    });
  });
}
