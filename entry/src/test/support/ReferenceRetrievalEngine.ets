import { PrivacyLevel, TaskRequestFilters, validateTaskRequestFilters } from '../../main/ets/contracts/semantic/SemanticModels';
import { DocumentChunk } from '../../main/ets/knowledge/model/DocumentChunk';
import { KnowledgeDocument } from '../../main/ets/knowledge/model/KnowledgeDocument';
import { RetrievalCandidate, RetrievalDocument } from '../../main/ets/knowledge/model/RetrievalCandidate';
import { analyzeQuery, QueryAnalysis } from '../../main/ets/knowledge/retrieval/QueryTokenizer';
import { KnowledgeRetrievalRequest, RetrievalEngine } from '../../main/ets/knowledge/retrieval/RetrievalEngine';

interface ReferenceScore {
  relevance: number;
  matchedPrimaryTerms: string[];
  matchedNgrams: string[];
  exactPhraseMatched: boolean;
  passesQualityGate: boolean;
}

function matchedTerms(terms: string[], text: string): string[] {
  const matched: string[] = [];
  const lower = text.toLowerCase();
  for (const term of terms) if (lower.includes(term)) matched.push(term);
  return matched;
}

function ratio(terms: string[], text: string): number {
  return terms.length === 0 ? 0 : matchedTerms(terms, text).length / terms.length;
}

function boundedFrequency(primaryTerms: string[], ngrams: string[], text: string): number {
  const lower = text.toLowerCase();
  let hits = 0;
  for (const term of primaryTerms) if (lower.includes(term)) hits += 1;
  for (const term of ngrams) if (lower.includes(term)) hits += 0.15;
  return Math.min(1, hits / Math.max(1, primaryTerms.length));
}

function ngramEvidence(ngrams: string[], text: string): number {
  const lower = text.toLowerCase();
  let evidence = 0;
  for (const term of ngrams) if (lower.includes(term)) evidence += term.length >= 3 ? 0.25 : 0.10;
  return Math.min(1, evidence);
}

function hasDiscriminatingNgrams(matched: string[]): boolean {
  let strong = 0;
  for (const term of matched) if (term.length >= 3) strong += 1;
  return strong >= 2 || strong >= 1 && matched.length >= 4;
}

function compact(text: string): string {
  return text.toLowerCase().replace(/[\s，。？！、；：,.?!;:()（）\[\]【】]+/g, '');
}

function score(analysis: QueryAnalysis, document: KnowledgeDocument, chunk: DocumentChunk): ReferenceScore {
  const titleAndTags = document.title + ' ' + document.tags.join(' ');
  const searchable = titleAndTags + ' ' + chunk.text;
  const matchedPrimary = matchedTerms(analysis.primaryTerms, searchable);
  const matchedNgrams = matchedTerms(analysis.ngrams, searchable);
  const normalized = compact(searchable);
  const joinedPrimary = analysis.primaryTerms.join('');
  const exact = analysis.normalizedQuery.length >= 2 && normalized.includes(analysis.normalizedQuery) ||
    joinedPrimary.length >= 2 && normalized.includes(joinedPrimary);
  const multiple = analysis.primaryTerms.length > 1;
  const quality = analysis.primaryTerms.length > 0 && (exact || !multiple && matchedPrimary.length >= 1 ||
    multiple && matchedPrimary.length >= 2 || hasDiscriminatingNgrams(matchedNgrams));
  const titleScore = Math.max(ratio(analysis.primaryTerms, document.title),
    ngramEvidence(analysis.ngrams, document.title));
  const tagScore = Math.max(ratio(analysis.primaryTerms, document.tags.join(' ')),
    ngramEvidence(analysis.ngrams, document.tags.join(' ')));
  const primaryCoverage = analysis.primaryTerms.length === 0 ? 0 : matchedPrimary.length / analysis.primaryTerms.length;
  const coverage = primaryCoverage * 0.75 + ngramEvidence(analysis.ngrams, searchable) * 0.25;
  const value = titleScore * 0.25 + tagScore * 0.20 + coverage * 0.25 +
    boundedFrequency(analysis.primaryTerms, analysis.ngrams, chunk.text) * 0.20 + (exact ? 0.10 : 0);
  return {
    relevance: Math.max(0, Math.min(1, Math.round(value * 10000) / 10000)),
    matchedPrimaryTerms: matchedPrimary, matchedNgrams: matchedNgrams,
    exactPhraseMatched: exact, passesQualityGate: quality
  };
}

function includesValue(values: string[] | undefined, value: string): boolean {
  return values === undefined || values.length === 0 || values.indexOf(value) >= 0;
}

function matchesTags(required: string[] | undefined, actual: string[]): boolean {
  if (required === undefined || required.length === 0) return true;
  for (const tag of required) if (actual.indexOf(tag) < 0) return false;
  return true;
}

function matchesFilters(document: KnowledgeDocument, filters: TaskRequestFilters | undefined,
  privacy: PrivacyLevel): boolean {
  if (privacy === 'PRIVATE_GROUP' && document.privacyLevel !== 'PRIVATE_GROUP') return false;
  if (filters === undefined) return true;
  if (!includesValue(filters.documentIds, document.documentId) || !matchesTags(filters.tags, document.tags)) return false;
  if (filters.modalities !== undefined && filters.modalities.length > 0 &&
    filters.modalities.indexOf(document.modality) < 0) return false;
  return filters.updatedAfter === undefined || document.updatedAt > filters.updatedAfter;
}

function findDocument(documents: KnowledgeDocument[], documentId: string): KnowledgeDocument | undefined {
  for (const document of documents) if (document.documentId === documentId) return document;
  return undefined;
}

function retrievalDocument(document: KnowledgeDocument): RetrievalDocument {
  return {
    documentId: document.documentId, title: document.title, modality: document.modality,
    tags: document.tags, updatedAt: document.updatedAt, privacyLevel: document.privacyLevel
  };
}

export class ReferenceKeywordSearch {
  mode(): 'keyword' { return 'keyword'; }

  search(request: KnowledgeRetrievalRequest, documents: KnowledgeDocument[], chunks: DocumentChunk[]): RetrievalCandidate[] {
    const analysis = analyzeQuery(request.queryText);
    validateTaskRequestFilters(request.filters);
    const results: RetrievalCandidate[] = [];
    for (const chunk of chunks) {
      const document = findDocument(documents, chunk.documentId);
      if (document === undefined || !matchesFilters(document, request.filters, request.privacyLevel)) continue;
      const relevance = score(analysis, document, chunk);
      if (relevance.passesQualityGate && relevance.relevance >= 0.15) {
        results.push({
          document: retrievalDocument(document), chunk: chunk, relevance: relevance.relevance,
          matchedPrimaryTerms: relevance.matchedPrimaryTerms, matchedNgrams: relevance.matchedNgrams,
          exactPhraseMatched: relevance.exactPhraseMatched
        });
      }
    }
    results.sort((left: RetrievalCandidate, right: RetrievalCandidate): number => {
      if (right.relevance !== left.relevance) return right.relevance - left.relevance;
      const documentOrder = left.document.documentId.localeCompare(right.document.documentId);
      return documentOrder !== 0 ? documentOrder : left.chunk.chunkId.localeCompare(right.chunk.chunkId);
    });
    return results.slice(0, request.topK);
  }
}

export class ReferenceRetrievalEngine implements RetrievalEngine {
  private readonly documents: KnowledgeDocument[];
  private readonly chunks: DocumentChunk[];
  private readonly reference = new ReferenceKeywordSearch();

  constructor(documents: KnowledgeDocument[], chunks: DocumentChunk[]) {
    this.documents = documents;
    this.chunks = chunks;
  }

  mode(): 'keyword' { return 'keyword'; }

  async search(request: KnowledgeRetrievalRequest): Promise<RetrievalCandidate[]> {
    return this.reference.search(request, this.documents, this.chunks);
  }
}
