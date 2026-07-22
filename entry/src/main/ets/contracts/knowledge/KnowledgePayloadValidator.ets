import { KnowledgeError } from './KnowledgeError';
import {
  KnowledgeDomain,
  KnowledgeModality,
  KnowledgeProfile,
  KnowledgeQueryFilters,
  LocalKnowledgeQuery,
  LocalKnowledgeResult
} from './KnowledgeModels';
import {
  L1KnowledgeItem,
  L1KnowledgePayload,
  L2KnowledgeItem,
  L2KnowledgePayload
} from './KnowledgePayloadSchemas';

const MIN_PAYLOAD_BYTES: number = 1024;
const MAX_PAYLOAD_BYTES: number = 262144;

function invalid(code: 'E_CONTRACT_VERSION_UNSUPPORTED' | 'E_QUERY_INVALID' | 'E_TOP_K_INVALID' |
  'E_PAYLOAD_BUDGET_INVALID' | 'E_FILTER_INVALID', message: string): never {
  throw new KnowledgeError(code, message, true);
}

function payloadInvalid(message: string): never {
  throw new KnowledgeError('E_PAYLOAD_INVALID', message, false);
}

function isInteger(value: number): boolean {
  return Number.isInteger(value);
}

function hasDuplicate(values: string[]): boolean {
  const seen: Set<string> = new Set<string>();
  for (const value of values) {
    if (seen.has(value)) {
      return true;
    }
    seen.add(value);
  }
  return false;
}

function validateFilters(filters: KnowledgeQueryFilters): void {
  if (filters.documentIds !== undefined && filters.documentIds.length > 100) {
    invalid('E_FILTER_INVALID', 'documentIds must contain at most 100 items');
  }
  if (filters.tags !== undefined) {
    if (filters.tags.length > 20) {
      invalid('E_FILTER_INVALID', 'tags must contain at most 20 items');
    }
    for (const tag of filters.tags) {
      const length = tag.trim().length;
      if (length < 1 || length > 64) {
        invalid('E_FILTER_INVALID', 'tag length is invalid');
      }
    }
  }
  if (filters.modalities !== undefined) {
    const values: string[] = filters.modalities;
    if (hasDuplicate(values)) {
      invalid('E_FILTER_INVALID', 'modalities must not contain duplicates');
    }
    for (const modality of filters.modalities) {
      if (!isSupportedModality(modality)) {
        invalid('E_FILTER_INVALID', 'modality is unsupported');
      }
    }
  }
  if (filters.updatedAfter !== undefined &&
    (!isInteger(filters.updatedAfter) || filters.updatedAfter < 0)) {
    invalid('E_FILTER_INVALID', 'updatedAfter must be a non-negative integer');
  }
}

function isSupportedModality(modality: KnowledgeModality): boolean {
  return modality === 'text' || modality === 'pdf' || modality === 'image' || modality === 'ocr_text';
}

export function validateKnowledgeRequest(request: LocalKnowledgeQuery): void {
  if (request.contractVersion !== '1.0') {
    invalid('E_CONTRACT_VERSION_UNSUPPORTED', 'Unsupported knowledge contract version');
  }
  const queryLength = request.queryText.trim().length;
  if (queryLength < 1 || queryLength > 1000 || request.requestId.trim().length === 0) {
    invalid('E_QUERY_INVALID', 'Query text or request identifier is invalid');
  }
  if (!isInteger(request.topK) || request.topK < 1 || request.topK > 20) {
    invalid('E_TOP_K_INVALID', 'topK must be between 1 and 20');
  }
  if (!isInteger(request.maxPayloadBytes) || request.maxPayloadBytes < MIN_PAYLOAD_BYTES ||
    request.maxPayloadBytes > MAX_PAYLOAD_BYTES) {
    invalid('E_PAYLOAD_BUDGET_INVALID', 'Payload budget must be between 1024 and 262144 bytes');
  }
  if (request.filters !== undefined) {
    validateFilters(request.filters);
  }
}

function utf8ByteLength(text: string): number {
  let bytes = 0;
  for (let index = 0; index < text.length; index++) {
    const code = text.charCodeAt(index);
    if (code <= 0x7F) {
      bytes += 1;
    } else if (code <= 0x7FF) {
      bytes += 2;
    } else if (code >= 0xD800 && code <= 0xDBFF && index + 1 < text.length) {
      const low = text.charCodeAt(index + 1);
      if (low >= 0xDC00 && low <= 0xDFFF) {
        bytes += 4;
        index += 1;
      } else {
        bytes += 3;
      }
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

function validateOrderAndIds(relevances: number[], ids: string[]): void {
  if (hasDuplicate(ids)) {
    payloadInvalid('Evidence identifiers must be unique');
  }
  for (let index = 0; index < relevances.length; index++) {
    const relevance = relevances[index];
    if (relevance < 0 || relevance > 1) {
      payloadInvalid('Relevance must be between 0 and 1');
    }
    if (index > 0 && relevance > relevances[index - 1]) {
      payloadInvalid('Items must be sorted by relevance');
    }
  }
}

function validateL1(payload: L1KnowledgePayload): void {
  if (payload.schemaVersion !== '1.0' || payload.level !== 'L1' || !Array.isArray(payload.items)) {
    payloadInvalid('Invalid L1 payload root');
  }
  const ids: string[] = [];
  const relevances: number[] = [];
  for (const item of payload.items) {
    validateL1Item(item);
    ids.push(item.evidenceId);
    relevances.push(item.relevance);
  }
  validateOrderAndIds(relevances, ids);
}

function validateL1Item(item: L1KnowledgeItem): void {
  if (typeof item.evidenceId !== 'string' || item.evidenceId.length === 0 ||
    typeof item.documentId !== 'string' || item.documentId.length === 0 ||
    typeof item.title !== 'string' || typeof item.summary !== 'string' || item.summary.length > 300 ||
    !Array.isArray(item.tags) || typeof item.relevance !== 'number' ||
    typeof item.updatedAt !== 'number' || item.updatedAt < 0) {
    payloadInvalid('Invalid L1 item');
  }
}

function validateL2(payload: L2KnowledgePayload): void {
  if (payload.schemaVersion !== '1.0' || payload.level !== 'L2' || !Array.isArray(payload.items)) {
    payloadInvalid('Invalid L2 payload root');
  }
  const ids: string[] = [];
  const relevances: number[] = [];
  for (const item of payload.items) {
    validateL2Item(item);
    ids.push(item.evidenceId);
    relevances.push(item.relevance);
  }
  validateOrderAndIds(relevances, ids);
}

function validateL2Item(item: L2KnowledgeItem): void {
  if (typeof item.evidenceId !== 'string' || item.evidenceId.length === 0 ||
    typeof item.documentId !== 'string' || item.documentId.length === 0 ||
    typeof item.chunkId !== 'string' || item.chunkId.length === 0 ||
    typeof item.title !== 'string' || typeof item.snippet !== 'string' || item.snippet.length > 1500 ||
    typeof item.relevance !== 'number' || typeof item.truncated !== 'boolean') {
    payloadInvalid('Invalid L2 item');
  }
}

function parseL1(json: string): L1KnowledgePayload {
  try {
    return JSON.parse(json) as L1KnowledgePayload;
  } catch (error) {
    payloadInvalid('Payload JSON is invalid');
  }
}

function parseL2(json: string): L2KnowledgePayload {
  try {
    return JSON.parse(json) as L2KnowledgePayload;
  } catch (error) {
    payloadInvalid('Payload JSON is invalid');
  }
}

export class KnowledgePayloadValidator {
  validateResult(request: LocalKnowledgeQuery, result: LocalKnowledgeResult): void {
    if (result.contractVersion !== '1.0' || result.requestId !== request.requestId ||
      result.level !== request.requestedLevel || result.retrievalMs < 0 || result.generatedAt < 0 ||
      utf8ByteLength(result.payloadJson) > request.maxPayloadBytes) {
      payloadInvalid('Result envelope does not match the request');
    }
    if (result.level === 'L1') {
      const payload = parseL1(result.payloadJson);
      validateL1(payload);
      if (payload.items.length !== result.itemCount) {
        payloadInvalid('Item count mismatch');
      }
    } else {
      const payload = parseL2(result.payloadJson);
      validateL2(payload);
      if (payload.items.length !== result.itemCount) {
        payloadInvalid('Item count mismatch');
      }
    }
    const lower = result.payloadJson.toLowerCase();
    if (lower.includes('file://') || lower.includes('embedding') || lower.includes('row_id') ||
      lower.includes('document_chunks')) {
      payloadInvalid('Payload contains a forbidden field');
    }
  }

  validateProfile(profile: KnowledgeProfile): void {
    if (profile.contractVersion !== '1.0' || profile.documentCount < 0 || profile.chunkCount < 0 ||
      profile.knowledgeDomains.length > 20 || profile.embeddingModelVersion !== '' ||
      profile.retrievalModes.length !== 1 || profile.retrievalModes[0] !== 'keyword' ||
      profile.supportedLevels.length !== 2 || profile.supportedLevels[0] !== 'L1' ||
      profile.supportedLevels[1] !== 'L2') {
      payloadInvalid('Knowledge profile is invalid');
    }
    let previousWeight = 1;
    for (const domain of profile.knowledgeDomains) {
      this.validateDomain(domain, previousWeight);
      previousWeight = domain.weight;
    }
  }

  private validateDomain(domain: KnowledgeDomain, previousWeight: number): void {
    if (domain.tag.trim().length === 0 || domain.weight < 0 || domain.weight > 1 ||
      domain.weight > previousWeight || !isInteger(domain.documentCount) || domain.documentCount < 0) {
      payloadInvalid('Knowledge domain is invalid');
    }
  }
}
