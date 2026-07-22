import { describe, expect, it } from '@ohos/hypium';
import { RetrievalCandidate } from '../main/ets/knowledge/model/RetrievalCandidate';
import { RdbKeywordRetrievalEngine } from '../main/ets/knowledge/retrieval/RdbKeywordRetrievalEngine';
import { KnowledgeRetrievalRequest } from '../main/ets/knowledge/retrieval/RetrievalEngine';
import { KnowledgeCandidateSearch } from '../main/ets/knowledge/storage/KnowledgeCandidateSearch';

class RecordingCandidateSearch implements KnowledgeCandidateSearch {
  request?: KnowledgeRetrievalRequest;
  calls: number = 0;
  readonly candidates: RetrievalCandidate[] = [{
    document: {
      documentId: 'doc', title: 'Database', modality: 'text', tags: ['db'],
      updatedAt: 1, privacyLevel: 'PRIVATE_GROUP'
    },
    chunk: {
      chunkId: 'chunk', documentId: 'doc', chunkIndex: 0, text: 'transaction isolation',
      summary: 'transaction', keywords: ['transaction'], startOffset: 0, endOffset: 21, updatedAt: 1
    },
    relevance: 1,
    matchedPrimaryTerms: ['transaction'],
    matchedNgrams: [],
    exactPhraseMatched: true
  }];

  async searchCandidates(request: KnowledgeRetrievalRequest): Promise<RetrievalCandidate[]> {
    this.calls += 1;
    this.request = request;
    return this.candidates;
  }
}

export default function rdbKeywordRetrievalEngineTest() {
  describe('RdbKeywordRetrievalEngine', () => {
    it('only delegates the unchanged request to database candidate search', 0, async () => {
      const search = new RecordingCandidateSearch();
      const engine = new RdbKeywordRetrievalEngine(search);
      const request: KnowledgeRetrievalRequest = {
        queryText: 'transaction isolation', topK: 5, privacyLevel: 'PRIVATE_GROUP',
        filters: { documentIds: ['doc'], tags: ['db'], modalities: ['text'], updatedAfter: 0 }
      };

      const result: RetrievalCandidate[] = await engine.search(request);

      expect(engine.mode()).assertEqual('keyword');
      expect(search.calls).assertEqual(1);
      expect(search.request).assertEqual(request);
      expect(result).assertEqual(search.candidates);
    });
  });
}
