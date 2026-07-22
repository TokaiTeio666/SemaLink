import { describe, expect, it } from '@ohos/hypium';
import { buildAutomaticTask, queryProgressFor } from '../main/ets/application/AutomaticQueryPolicy';
import { TaskRequest, TaskPhase } from '../main/ets/contracts/semantic/SemanticModels';
import { KnowledgeError } from '../main/ets/contracts/knowledge/KnowledgeError';

export default function automaticQueryPolicyTest(): void {
  describe('AutomaticQueryPolicy', () => {
    it('buildsAnAutomaticTaskFromOnlyTheQuestion', 0, () => {
      const task: TaskRequest = buildAutomaticTask('q-1', '  project meeting decisions?  ', 'PRIVATE_GROUP');
      expect(task.semanticContractVersion).assertEqual('1.0');
      expect(task.taskId).assertEqual('q-1');
      expect(task.queryText).assertEqual('project meeting decisions?');
      expect(task.requiredConcepts.length).assertEqual(0);
      expect(task.requiredConfidence).assertEqual(0.80);
      expect(task.coverageThreshold).assertEqual(0.80);
      expect(task.latencyBudgetMs).assertEqual(10000);
      expect(task.byteBudget).assertEqual(8192);
      expect(task.privacyLevel).assertEqual('PRIVATE_GROUP');
      expect(task.acceptableLevels[0]).assertEqual('L1');
      expect(task.acceptableLevels[1]).assertEqual('L2');
    });

    it('rejectsAnEmptyQuestion', 0, () => {
      let error: KnowledgeError | undefined;
      try {
        buildAutomaticTask('q-1', '   ', 'PRIVATE_GROUP');
      } catch (caught) {
        error = caught as KnowledgeError;
      }
      expect(error?.code).assertEqual('E_QUERY_INVALID');
    });

    it('mapsSemanticPhasesToStableQueryProgress', 0, () => {
      expect(queryProgressFor('ROUTING' as TaskPhase)).assertEqual('ROUTING');
      expect(queryProgressFor('AWAITING_L1' as TaskPhase)).assertEqual('SEARCHING');
      expect(queryProgressFor('EVALUATING_L2' as TaskPhase)).assertEqual('ANALYZING');
      expect(queryProgressFor('SUFFICIENT' as TaskPhase)).assertEqual('ANSWER_READY');
      expect(queryProgressFor('ABORTED' as TaskPhase)).assertEqual('INSUFFICIENT');
      expect(queryProgressFor('FAILED' as TaskPhase)).assertEqual('FAILED');
    });
  });
}
