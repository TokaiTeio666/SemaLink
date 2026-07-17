import { KnowledgeError, KnowledgeErrorCode } from '../../contracts/knowledge/KnowledgeError';
import { TaskRequestFilters } from '../../contracts/semantic/SemanticModels';
import { KnowledgeRetrievalRequest, RETRIEVAL_CANDIDATE_LIMIT } from './RetrievalEngine';

export const MAX_RETRIEVAL_QUERY_CHARACTERS: number = 1000;
export const MAX_RETRIEVAL_DOCUMENT_IDS: number = 100;
export const MAX_RETRIEVAL_TAGS: number = 20;
export const MAX_RETRIEVAL_MODALITIES: number = 4;
export const MAX_RETRIEVAL_DOCUMENT_ID_CHARACTERS: number = 200;
export const MAX_RETRIEVAL_TAG_CHARACTERS: number = 64;

function invalid(code: KnowledgeErrorCode, message: string): never {
  throw new KnowledgeError(code, message, false);
}

function resemblesStorageReference(value: string): boolean {
  return /[a-z][a-z0-9+.-]*:\/\//i.test(value) || /[a-z]:[\\/]/i.test(value) ||
    value.startsWith('/') || value.startsWith('\\\\');
}

function validateUniqueStrings(values: string[] | undefined, maximumCount: number,
  maximumCharacters: number): void {
  if (values === undefined) return;
  if (!Array.isArray(values) || values.length > maximumCount) {
    invalid('E_FILTER_INVALID', 'Knowledge retrieval filters are invalid');
  }
  const seen = new Set<string>();
  for (const value of values) {
    if (typeof value !== 'string') {
      invalid('E_FILTER_INVALID', 'Knowledge retrieval filters are invalid');
    }
    const normalized = value.trim();
    if (normalized.length === 0 || value.length > maximumCharacters ||
      resemblesStorageReference(normalized) || seen.has(normalized)) {
      invalid('E_FILTER_INVALID', 'Knowledge retrieval filters are invalid');
    }
    seen.add(normalized);
  }
}

function validateModalities(modalities: string[] | undefined): void {
  if (modalities === undefined) return;
  if (!Array.isArray(modalities) || modalities.length > MAX_RETRIEVAL_MODALITIES) {
    invalid('E_FILTER_INVALID', 'Knowledge retrieval filters are invalid');
  }
  const seen = new Set<string>();
  for (const modality of modalities) {
    if ((modality !== 'text' && modality !== 'pdf' && modality !== 'image' && modality !== 'ocr_text') ||
      seen.has(modality)) {
      invalid('E_FILTER_INVALID', 'Knowledge retrieval filters are invalid');
    }
    seen.add(modality);
  }
}

function validateFilters(filters: TaskRequestFilters | undefined): void {
  if (filters === undefined) return;
  if (typeof filters !== 'object' || filters === null || Array.isArray(filters)) {
    invalid('E_FILTER_INVALID', 'Knowledge retrieval filters are invalid');
  }
  validateUniqueStrings(filters.documentIds, MAX_RETRIEVAL_DOCUMENT_IDS,
    MAX_RETRIEVAL_DOCUMENT_ID_CHARACTERS);
  validateUniqueStrings(filters.tags, MAX_RETRIEVAL_TAGS, MAX_RETRIEVAL_TAG_CHARACTERS);
  validateModalities(filters.modalities);
  if (filters.updatedAfter !== undefined &&
    (!Number.isInteger(filters.updatedAfter) || filters.updatedAfter < 0)) {
    invalid('E_FILTER_INVALID', 'Knowledge retrieval filters are invalid');
  }
}

export function validateKnowledgeRetrievalRequest(request: KnowledgeRetrievalRequest): void {
  if (typeof request !== 'object' || request === null || typeof request.queryText !== 'string' ||
    request.queryText.trim().length === 0 || request.queryText.length > MAX_RETRIEVAL_QUERY_CHARACTERS ||
    (request.privacyLevel !== 'LOCAL_ONLY' && request.privacyLevel !== 'PRIVATE_GROUP')) {
    invalid('E_QUERY_INVALID', 'Knowledge retrieval query is invalid');
  }
  if (!Number.isInteger(request.topK) || request.topK < 1 || request.topK > RETRIEVAL_CANDIDATE_LIMIT) {
    invalid('E_TOP_K_INVALID', 'Knowledge retrieval topK is invalid');
  }
  validateFilters(request.filters);
}
