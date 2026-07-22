import { RetrievalCandidate } from '../../../../main/ets/knowledge/model/RetrievalCandidate';
import { KnowledgeRetrievalRequest } from '../../../../main/ets/knowledge/retrieval/RetrievalEngine';
import { KnowledgeCandidateSearch } from '../../../../main/ets/knowledge/storage/KnowledgeCandidateSearch';

export class CountingCandidateSearch implements KnowledgeCandidateSearch {
  private readonly inner: KnowledgeCandidateSearch;
  private searchCallCount: number = 0;
  private rowCount: number = 0;

  constructor(inner: KnowledgeCandidateSearch) {
    this.inner = inner;
  }

  get searchCalls(): number {
    return this.searchCallCount;
  }

  get totalRowsReturned(): number {
    return this.rowCount;
  }

  async searchCandidates(request: KnowledgeRetrievalRequest): Promise<RetrievalCandidate[]> {
    this.searchCallCount += 1;
    const candidates = await this.inner.searchCandidates(request);
    this.rowCount += candidates.length;
    return candidates;
  }
}
