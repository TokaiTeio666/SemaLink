import { RetrievalCandidate } from '../model/RetrievalCandidate';
import { KnowledgeCandidateSearch } from '../storage/KnowledgeCandidateSearch';
import { KnowledgeRetrievalRequest, RetrievalEngine } from './RetrievalEngine';

export class RdbKeywordRetrievalEngine implements RetrievalEngine {
  private readonly candidateSearch: KnowledgeCandidateSearch;

  constructor(candidateSearch: KnowledgeCandidateSearch) {
    this.candidateSearch = candidateSearch;
  }

  mode(): 'keyword' {
    return 'keyword';
  }

  async search(request: KnowledgeRetrievalRequest): Promise<RetrievalCandidate[]> {
    return this.candidateSearch.searchCandidates(request);
  }
}
