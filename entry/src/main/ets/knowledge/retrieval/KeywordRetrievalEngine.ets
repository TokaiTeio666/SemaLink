import { DocumentChunk } from '../model/DocumentChunk';
import { KnowledgeDocument } from '../model/KnowledgeDocument';
import { RetrievalCandidate } from '../model/RetrievalCandidate';
import { analyzeQuery } from './QueryTokenizer';
import { RelevanceScore, scoreChunk } from './RelevanceScorer';
import {
  KnowledgeRetrievalRequest,
  RetrievalEngine
} from './RetrievalEngine';
import {
  PrivacyLevel,
  TaskRequestFilters,
  validateTaskRequestFilters
} from '../../contracts/semantic/SemanticModels';

function includesValue(values: string[] | undefined, value: string): boolean {
  return values === undefined || values.length === 0 || values.indexOf(value) >= 0;
}

function matchesTags(required: string[] | undefined, actual: string[]): boolean {
  if (required === undefined || required.length === 0) {
    return true;
  }
  for (const tag of required) {
    if (actual.indexOf(tag) < 0) {
      return false;
    }
  }
  return true;
}

function matchesFilters(document: KnowledgeDocument, filters: TaskRequestFilters | undefined,
  privacyLevel: PrivacyLevel): boolean {
  if (privacyLevel === 'PRIVATE_GROUP' && document.privacyLevel !== 'PRIVATE_GROUP') {
    return false;
  }
  if (filters === undefined) {
    return true;
  }
  if (!includesValue(filters.documentIds, document.documentId) || !matchesTags(filters.tags, document.tags)) {
    return false;
  }
  if (filters.modalities !== undefined && filters.modalities.length > 0 &&
    filters.modalities.indexOf(document.modality) < 0) {
    return false;
  }
  return filters.updatedAfter === undefined || document.updatedAt > filters.updatedAfter;
}

function findDocument(documents: KnowledgeDocument[], documentId: string): KnowledgeDocument | undefined {
  for (const document of documents) {
    if (document.documentId === documentId) {
      return document;
    }
  }
  return undefined;
}

export class KeywordRetrievalEngine implements RetrievalEngine {
  mode(): 'keyword' {
    return 'keyword';
  }

  search(request: KnowledgeRetrievalRequest,
    documents: KnowledgeDocument[], chunks: DocumentChunk[]): RetrievalCandidate[] {
    const analysis = analyzeQuery(request.queryText);
    validateTaskRequestFilters(request.filters);
    const results: RetrievalCandidate[] = [];
    for (const chunk of chunks) {
      const document = findDocument(documents, chunk.documentId);
      if (document === undefined || !matchesFilters(document, request.filters, request.privacyLevel)) {
        continue;
      }
      const score: RelevanceScore = scoreChunk(analysis, document, chunk);
      if (score.passesQualityGate && score.relevance >= 0.15) {
        results.push({
          document: document,
          chunk: chunk,
          relevance: score.relevance,
          matchedPrimaryTerms: score.matchedPrimaryTerms,
          matchedNgrams: score.matchedNgrams,
          exactPhraseMatched: score.exactPhraseMatched
        });
      }
    }
    results.sort((left: RetrievalCandidate, right: RetrievalCandidate): number => {
      if (right.relevance !== left.relevance) {
        return right.relevance - left.relevance;
      }
      const documentOrder = left.document.documentId.localeCompare(right.document.documentId);
      return documentOrder !== 0 ? documentOrder : left.chunk.chunkId.localeCompare(right.chunk.chunkId);
    });
    return results.slice(0, request.topK);
  }
}
