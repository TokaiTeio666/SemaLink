import { KnowledgeError } from '../knowledge/KnowledgeError';
import { isSafeKnowledgeFilterValue } from '../knowledge/KnowledgeFilterValueValidator';

export const SEMANTIC_CONTRACT_VERSION: '1.0' = '1.0';

export type PrivacyLevel = 'LOCAL_ONLY' | 'PRIVATE_GROUP';
export type EvidenceLevel = 'L1' | 'L2';
export type PayloadLevel = 'L0' | 'L1' | 'L2' | 'L3';
export type TaskPhase =
  | 'PENDING'
  | 'ROUTING'
  | 'AWAITING_L1'
  | 'EVALUATING_L1'
  | 'NEED_MORE'
  | 'AWAITING_L2'
  | 'EVALUATING_L2'
  | 'SUFFICIENT'
  | 'ABORTED'
  | 'FAILED';
export type TaskSufficiencyFeedback = 'ENOUGH' | 'NEED_MORE' | 'ABORT';

export const DEFAULT_REQUIRED_CONFIDENCE: number = 0.80;
export const DEFAULT_COVERAGE_THRESHOLD: number = 0.80;

export interface TaskSufficiencyResult {
  feedback: TaskSufficiencyFeedback;
  coverage: number;
  confidence: number;
  diversity: number;
  coveredConcepts: string[];
  missingConcepts: string[];
  acceptedEvidenceIds: string[];
}

export interface DeviceRuntimeSnapshot {
  deviceId: string;
  deviceAlias: string;
  isLocal: boolean;
  state: 'READY' | 'BUSY' | 'OFFLINE';
  profileVersion: string;
  indexVersion: string;
  lastSeenAtMs: number;
  averageRttMs: number;
  load: number;
  advertisedAtMs: number;
}

export interface DeviceProfileAdvertisement {
  semanticContractVersion: '1.0';
  deviceId: string;
  deviceAlias: string;
  profileVersion: string;
  indexVersion: string;
  indexState: 'NOT_READY' | 'INDEXING' | 'READY';
  knowledgeDomains: string[];
  modalities: string[];
  retrievalModes: string[];
  supportedLevels: EvidenceLevel[];
  advertisedAtMs: number;
  ttlMs: number;
}

export interface TaskRequestFilters {
  documentIds?: string[];
  tags?: string[];
  modalities?: string[];
  updatedAfter?: number;
}

export interface TaskRequest {
  semanticContractVersion: '1.0';
  taskId: string;
  queryText: string;
  requiredConcepts: string[];
  requiredConfidence: number;
  coverageThreshold: number;
  latencyBudgetMs: number;
  byteBudget: number;
  privacyLevel: 'LOCAL_ONLY' | 'PRIVATE_GROUP';
  acceptableLevels: ('L1' | 'L2')[];
  filters?: TaskRequestFilters;
}

export interface EvidenceUnit {
  semanticContractVersion: '1.0';
  evidenceId: string;
  evidenceGroupId: string;
  sourceDeviceId: string;
  sourceDocId: string;
  sourceChunkId?: string;
  parentEvidenceId?: string;
  level: 'L1' | 'L2';
  title: string;
  summary?: string;
  snippet?: string;
  relevance: number;
  coveredConcepts: string[];
  estimatedCoverageGain: number;
  byteCost: number;
  privacyLevel: 'LOCAL_ONLY' | 'PRIVATE_GROUP';
  privacyCost: number;
  energyCost: number;
  hash: string;
  canEscalateTo: ('L1' | 'L2')[];
}

export function validateSemanticContractVersion(version: string): void {
  if (version !== SEMANTIC_CONTRACT_VERSION) {
    throw new KnowledgeError('E_CONTRACT_VERSION_UNSUPPORTED',
      'Semantic contract version is unsupported', false);
  }
}

function validateFilterValues(values: string[] | undefined): void {
  if (values === undefined) {
    return;
  }
  if (!Array.isArray(values)) {
    throw new KnowledgeError('E_FILTER_INVALID', 'Semantic task filter is invalid', false);
  }
  for (const value of values) {
    if (typeof value !== 'string' || !isSafeKnowledgeFilterValue(value)) {
      throw new KnowledgeError('E_FILTER_INVALID', 'Semantic task filter is invalid', false);
    }
  }
}

export function validateTaskRequestFilters(filters: TaskRequestFilters | undefined): void {
  if (filters === undefined) {
    return;
  }
  if (typeof filters !== 'object' || filters === null || Array.isArray(filters)) {
    throw new KnowledgeError('E_FILTER_INVALID', 'Semantic task filter is invalid', false);
  }
  validateFilterValues(filters.documentIds);
  validateFilterValues(filters.tags);
  if (filters.modalities !== undefined) {
    if (!Array.isArray(filters.modalities)) {
      throw new KnowledgeError('E_FILTER_INVALID', 'Semantic task filter is invalid', false);
    }
    for (const modality of filters.modalities) {
      if (typeof modality !== 'string' ||
        (modality !== 'text' && modality !== 'pdf' && modality !== 'image' && modality !== 'ocr_text')) {
        throw new KnowledgeError('E_FILTER_INVALID', 'Semantic task filter is invalid', false);
      }
    }
  }
  if (filters.updatedAfter !== undefined &&
    (!Number.isInteger(filters.updatedAfter) || filters.updatedAfter < 0)) {
    throw new KnowledgeError('E_FILTER_INVALID', 'Semantic task filter is invalid', false);
  }
}

function isUnitInterval(value: number): boolean {
  return Number.isFinite(value) && value >= 0 && value <= 1;
}

function isPositiveInteger(value: number): boolean {
  return Number.isInteger(value) && value > 0;
}

export function validateTaskRequest(task: TaskRequest): void {
  validateSemanticContractVersion(task.semanticContractVersion);
  if (typeof task.taskId !== 'string' || typeof task.queryText !== 'string' ||
    task.taskId.trim().length === 0 || task.queryText.trim().length === 0 ||
    (task.privacyLevel !== 'LOCAL_ONLY' && task.privacyLevel !== 'PRIVATE_GROUP') ||
    !Array.isArray(task.requiredConcepts) ||
    !isUnitInterval(task.requiredConfidence) || !isUnitInterval(task.coverageThreshold) ||
    !isPositiveInteger(task.latencyBudgetMs) || !isPositiveInteger(task.byteBudget)) {
    throw new KnowledgeError('E_QUERY_INVALID', 'Semantic task fields are invalid', false);
  }
  for (const concept of task.requiredConcepts) {
    if (typeof concept !== 'string' || concept.trim().length === 0) {
      throw new KnowledgeError('E_QUERY_INVALID', 'Semantic task fields are invalid', false);
    }
  }
  if (!Array.isArray(task.acceptableLevels) || task.acceptableLevels.length === 0) {
    throw new KnowledgeError('E_QUERY_INVALID', 'Semantic task evidence levels are invalid', false);
  }
  const seen: Set<string> = new Set<string>();
  for (const level of task.acceptableLevels) {
    if (typeof level !== 'string' || (level !== 'L1' && level !== 'L2') || seen.has(level)) {
      throw new KnowledgeError('E_QUERY_INVALID', 'Semantic task evidence levels are invalid', false);
    }
    seen.add(level);
  }
  validateTaskRequestFilters(task.filters);
}
