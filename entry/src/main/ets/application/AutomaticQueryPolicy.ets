import { KnowledgeError } from '../contracts/knowledge/KnowledgeError';
import { PrivacyLevel, SEMANTIC_CONTRACT_VERSION, TaskPhase, TaskRequest } from '../contracts/semantic/SemanticModels';

export type AutomaticQueryProgress =
  | 'IDLE'
  | 'ROUTING'
  | 'SEARCHING'
  | 'ANALYZING'
  | 'ANSWER_READY'
  | 'INSUFFICIENT'
  | 'FAILED';

export function buildAutomaticTask(
  taskId: string,
  question: string,
  privacyLevel: PrivacyLevel = 'PRIVATE_GROUP'
): TaskRequest {
  const queryText: string = question.trim();
  if (queryText.length === 0) {
    throw new KnowledgeError('E_QUERY_INVALID', 'Automatic query question is empty', false);
  }
  return {
    semanticContractVersion: SEMANTIC_CONTRACT_VERSION,
    taskId,
    queryText,
    requiredConcepts: [],
    requiredConfidence: 0.80,
    coverageThreshold: 0.80,
    latencyBudgetMs: 10000,
    byteBudget: 8192,
    privacyLevel,
    acceptableLevels: ['L1', 'L2']
  };
}

export function queryProgressFor(phase: TaskPhase): AutomaticQueryProgress {
  switch (phase) {
    case 'ROUTING': return 'ROUTING';
    case 'AWAITING_L1':
    case 'EVALUATING_L1':
    case 'NEED_MORE':
    case 'AWAITING_L2': return 'SEARCHING';
    case 'EVALUATING_L2': return 'ANALYZING';
    case 'SUFFICIENT': return 'ANSWER_READY';
    case 'ABORTED': return 'INSUFFICIENT';
    case 'FAILED': return 'FAILED';
    default: return 'IDLE';
  }
}
