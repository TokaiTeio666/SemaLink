import { KnowledgeProfile } from '../knowledge/KnowledgeModels';
import { EvidenceUnit, TaskRequest } from './SemanticModels';

export interface SemanticKnowledgeProvider {
  getProfile(): Promise<KnowledgeProfile>;
  searchEvidence(task: TaskRequest): Promise<EvidenceUnit[]>;
}
