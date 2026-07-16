import { RetrievalMode } from '../../contracts/knowledge/KnowledgeModels';
import { PrivacyLevel, TaskRequestFilters } from '../../contracts/semantic/SemanticModels';
import { DocumentChunk } from '../model/DocumentChunk';
import { KnowledgeDocument } from '../model/KnowledgeDocument';
import { RetrievalCandidate } from '../model/RetrievalCandidate';

export const RETRIEVAL_CANDIDATE_LIMIT: number = 20;

export interface KnowledgeRetrievalRequest {
  queryText: string;
  topK: number;
  privacyLevel: PrivacyLevel;
  filters?: TaskRequestFilters;
}

export interface RetrievalEngine {
  mode(): RetrievalMode;
  search(
    request: KnowledgeRetrievalRequest,
    documents: KnowledgeDocument[],
    chunks: DocumentChunk[]
  ): RetrievalCandidate[];
}
