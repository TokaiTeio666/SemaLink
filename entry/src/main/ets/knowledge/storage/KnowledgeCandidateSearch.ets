import { RetrievalCandidate } from '../model/RetrievalCandidate';
import { KnowledgeRetrievalRequest } from '../retrieval/RetrievalEngine';

export interface KnowledgeCandidateSearch {
  searchCandidates(request: KnowledgeRetrievalRequest): Promise<RetrievalCandidate[]>;
}
