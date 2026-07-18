import { AppError, ErrorStage } from '../common/AppError';
import {
  ProtocolEnvelope, ProtocolPayload, MessageType, QueryPayload, QueryAckPayload,
  ResultPayload, ErrorPayload, ProfilePayload, TaskPayload, TaskAckPayload,
  EvidencePayload, TsfPayload, CancelPayload,
  PROTOCOL_VERSION, MAX_MESSAGE_BYTES, MAX_QUESTION_CHARS, MAX_SUMMARY_CHARS
} from './ProtocolModels';
import { LocalKnowledgeResult } from '../contracts/knowledge/KnowledgeModels';
import {
  DeviceProfileAdvertisement,
  EvidenceUnit,
  TaskRequest,
  TaskRequestFilters,
  TaskSufficiencyResult,
  validateTaskRequest
} from '../contracts/semantic/SemanticModels';

const VALID_MESSAGE_TYPES: string[] = [
  'QUERY', 'QUERY_ACK', 'RESULT', 'ERROR',
  'PROFILE', 'TASK', 'TASK_ACK', 'EVIDENCE', 'TSF', 'CANCEL'
];

const SEMANTIC_CONTRACT_VERSION: string = '1.0';
const VALID_EVIDENCE_LEVELS: string[] = ['L1', 'L2'];
const VALID_PRIVACY_LEVELS: string[] = ['LOCAL_ONLY', 'PRIVATE_GROUP'];
const VALID_TSF_FEEDBACKS: string[] = ['ENOUGH', 'NEED_MORE', 'ABORT'];
const VALID_INDEX_STATES: string[] = ['NOT_READY', 'INDEXING', 'READY'];
const VALID_ACCEPTABLE_LEVELS: string[] = ['L1', 'L2'];
const VALID_CAN_ESCALATE_LEVELS: string[] = ['L1', 'L2'];
const VALID_TASK_ROUNDS: number[] = [1, 2];

function countUtf8Bytes(text: string): number {
  let byteCount: number = 0;
  for (let i = 0; i < text.length; i++) {
    const codePoint: number | undefined = text.codePointAt(i);
    if (codePoint === undefined) {
      continue;
    }
    if (codePoint <= 0x7F) {
      byteCount += 1;
    } else if (codePoint <= 0x7FF) {
      byteCount += 2;
    } else if (codePoint <= 0xFFFF) {
      byteCount += 3;
      if (codePoint >= 0xD800 && codePoint <= 0xDBFF) {
        i++; // skip low surrogate
      }
    } else {
      byteCount += 4;
      i++; // skip low surrogate
    }
  }
  return byteCount;
}

function isUnitInterval(value: number): boolean {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1;
}

function isStringArray(value: Object | undefined): boolean {
  if (value === undefined || !Array.isArray(value)) {
    return false;
  }
  const arr: Object[] = value as Object[];
  for (const item of arr) {
    if (typeof item !== 'string') {
      return false;
    }
  }
  return true;
}

function isStringInSet(value: Object | undefined, allowed: string[]): boolean {
  if (typeof value !== 'string') {
    return false;
  }
  for (const candidate of allowed) {
    if (value === candidate) {
      return true;
    }
  }
  return false;
}

function isLevelArrayInSet(value: Object | undefined, allowed: string[]): boolean {
  if (value === undefined || !Array.isArray(value)) {
    return false;
  }
  const arr: Object[] = value as Object[];
  for (const item of arr) {
    if (typeof item !== 'string') {
      return false;
    }
    let found: boolean = false;
    for (const candidate of allowed) {
      if (item === candidate) {
        found = true;
        break;
      }
    }
    if (!found) {
      return false;
    }
  }
  return true;
}

function isNonEmptyString(value: Object | undefined): boolean {
  return typeof value === 'string' && (value as string).length > 0;
}

function isRoundValid(round: Object | undefined): boolean {
  if (typeof round !== 'number' || !Number.isInteger(round)) {
    return false;
  }
  return round === 1 || round === 2;
}

function isRoundValidNumber(round: number): boolean {
  return Number.isInteger(round) && (round === 1 || round === 2);
}

function validateTypedEvidenceUnit(unit: EvidenceUnit): void {
  if (unit.semanticContractVersion !== SEMANTIC_CONTRACT_VERSION) {
    throw new AppError('E_PROTOCOL_INVALID', 'semanticContractVersion 不一致', ErrorStage.PROTOCOL, false);
  }
  if (typeof unit.evidenceId !== 'string' || unit.evidenceId.length === 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'evidenceId 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (typeof unit.evidenceGroupId !== 'string' || unit.evidenceGroupId.length === 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'evidenceGroupId 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (typeof unit.sourceDeviceId !== 'string' || unit.sourceDeviceId.length === 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'sourceDeviceId 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (typeof unit.sourceDocId !== 'string' || unit.sourceDocId.length === 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'sourceDocId 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (unit.level !== 'L1' && unit.level !== 'L2') {
    throw new AppError('E_PROTOCOL_INVALID', 'level 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (typeof unit.title !== 'string' || unit.title.length === 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'title 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (!isUnitInterval(unit.relevance)) {
    throw new AppError('E_PROTOCOL_INVALID', 'relevance 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (!Array.isArray(unit.coveredConcepts)) {
    throw new AppError('E_PROTOCOL_INVALID', 'coveredConcepts 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (!isUnitInterval(unit.estimatedCoverageGain)) {
    throw new AppError('E_PROTOCOL_INVALID', 'estimatedCoverageGain 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (typeof unit.byteCost !== 'number' || unit.byteCost <= 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'byteCost 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (unit.privacyLevel !== 'LOCAL_ONLY' && unit.privacyLevel !== 'PRIVATE_GROUP') {
    throw new AppError('E_PROTOCOL_INVALID', 'privacyLevel 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (!isUnitInterval(unit.privacyCost)) {
    throw new AppError('E_PROTOCOL_INVALID', 'privacyCost 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (!isUnitInterval(unit.energyCost)) {
    throw new AppError('E_PROTOCOL_INVALID', 'energyCost 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (typeof unit.hash !== 'string' || unit.hash.length === 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'hash 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (!Array.isArray(unit.canEscalateTo)) {
    throw new AppError('E_PROTOCOL_INVALID', 'canEscalateTo 字段无效', ErrorStage.PROTOCOL, false);
  }
  for (const level of unit.canEscalateTo) {
    if (level !== 'L1' && level !== 'L2') {
      throw new AppError('E_PROTOCOL_INVALID', 'canEscalateTo 字段无效', ErrorStage.PROTOCOL, false);
    }
  }
}

function validateTypedProfile(profile: DeviceProfileAdvertisement): void {
  if (profile.semanticContractVersion !== SEMANTIC_CONTRACT_VERSION) {
    throw new AppError('E_PROTOCOL_INVALID', 'semanticContractVersion 不一致', ErrorStage.PROTOCOL, false);
  }
  if (typeof profile.deviceId !== 'string' || profile.deviceId.length === 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'deviceId 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (typeof profile.deviceAlias !== 'string' || profile.deviceAlias.length === 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'deviceAlias 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (typeof profile.profileVersion !== 'string' || profile.profileVersion.length === 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'profileVersion 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (typeof profile.indexVersion !== 'string' || profile.indexVersion.length === 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'indexVersion 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (profile.indexState !== 'NOT_READY' && profile.indexState !== 'INDEXING' && profile.indexState !== 'READY') {
    throw new AppError('E_PROTOCOL_INVALID', 'indexState 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (!Array.isArray(profile.knowledgeDomains)) {
    throw new AppError('E_PROTOCOL_INVALID', 'knowledgeDomains 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (!Array.isArray(profile.modalities)) {
    throw new AppError('E_PROTOCOL_INVALID', 'modalities 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (!Array.isArray(profile.retrievalModes)) {
    throw new AppError('E_PROTOCOL_INVALID', 'retrievalModes 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (!Array.isArray(profile.supportedLevels) || profile.supportedLevels.length === 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'supportedLevels 字段无效', ErrorStage.PROTOCOL, false);
  }
  for (const level of profile.supportedLevels) {
    if (level !== 'L1' && level !== 'L2') {
      throw new AppError('E_PROTOCOL_INVALID', 'supportedLevels 字段无效', ErrorStage.PROTOCOL, false);
    }
  }
  if (typeof profile.advertisedAtMs !== 'number' || !Number.isFinite(profile.advertisedAtMs)) {
    throw new AppError('E_PROTOCOL_INVALID', 'advertisedAtMs 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (typeof profile.ttlMs !== 'number' || profile.ttlMs <= 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'ttlMs 字段无效', ErrorStage.PROTOCOL, false);
  }
}

function validateTypedTsfResult(result: TaskSufficiencyResult): void {
  if (result.feedback !== 'ENOUGH' && result.feedback !== 'NEED_MORE' && result.feedback !== 'ABORT') {
    throw new AppError('E_PROTOCOL_INVALID', 'feedback 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (!isUnitInterval(result.coverage)) {
    throw new AppError('E_PROTOCOL_INVALID', 'coverage 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (!isUnitInterval(result.confidence)) {
    throw new AppError('E_PROTOCOL_INVALID', 'confidence 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (!isUnitInterval(result.diversity)) {
    throw new AppError('E_PROTOCOL_INVALID', 'diversity 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (!Array.isArray(result.coveredConcepts)) {
    throw new AppError('E_PROTOCOL_INVALID', 'coveredConcepts 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (!Array.isArray(result.missingConcepts)) {
    throw new AppError('E_PROTOCOL_INVALID', 'missingConcepts 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (!Array.isArray(result.acceptedEvidenceIds)) {
    throw new AppError('E_PROTOCOL_INVALID', 'acceptedEvidenceIds 字段无效', ErrorStage.PROTOCOL, false);
  }
}

function checkRequiredFields(raw: Record<string, Object>): void {
  // ArkTS doesn't support 'in' operator; check each field individually via typeof
  if (raw['version'] === undefined) {
    throw new AppError('E_PROTOCOL_INVALID', '缺少必要字段: version', ErrorStage.PROTOCOL, false);
  }
  if (raw['type'] === undefined) {
    throw new AppError('E_PROTOCOL_INVALID', '缺少必要字段: type', ErrorStage.PROTOCOL, false);
  }
  if (raw['messageId'] === undefined) {
    throw new AppError('E_PROTOCOL_INVALID', '缺少必要字段: messageId', ErrorStage.PROTOCOL, false);
  }
  if (raw['sessionId'] === undefined) {
    throw new AppError('E_PROTOCOL_INVALID', '缺少必要字段: sessionId', ErrorStage.PROTOCOL, false);
  }
  if (raw['requestId'] === undefined) {
    throw new AppError('E_PROTOCOL_INVALID', '缺少必要字段: requestId', ErrorStage.PROTOCOL, false);
  }
  if (raw['sentAt'] === undefined) {
    throw new AppError('E_PROTOCOL_INVALID', '缺少必要字段: sentAt', ErrorStage.PROTOCOL, false);
  }
  if (raw['payload'] === undefined) {
    throw new AppError('E_PROTOCOL_INVALID', '缺少必要字段: payload', ErrorStage.PROTOCOL, false);
  }
}

function requireString(raw: Record<string, Object>, field: string): string {
  if (typeof raw[field] !== 'string') {
    throw new AppError('E_PROTOCOL_INVALID', field + ' 字段无效', ErrorStage.PROTOCOL, false);
  }
  return raw[field] as string;
}

function requireNonEmptyString(raw: Record<string, Object>, field: string): string {
  if (!isNonEmptyString(raw[field])) {
    throw new AppError('E_PROTOCOL_INVALID', field + ' 字段无效', ErrorStage.PROTOCOL, false);
  }
  return raw[field] as string;
}

function requireNumber(raw: Record<string, Object>, field: string): number {
  if (typeof raw[field] !== 'number' || !Number.isFinite(raw[field] as number)) {
    throw new AppError('E_PROTOCOL_INVALID', field + ' 字段无效', ErrorStage.PROTOCOL, false);
  }
  return raw[field] as number;
}

function requireUnitInterval(raw: Record<string, Object>, field: string): number {
  const value: number = requireNumber(raw, field);
  if (!isUnitInterval(value)) {
    throw new AppError('E_PROTOCOL_INVALID', field + ' 字段无效', ErrorStage.PROTOCOL, false);
  }
  return value;
}

function requireStringArray(raw: Record<string, Object>, field: string): string[] {
  if (!isStringArray(raw[field])) {
    throw new AppError('E_PROTOCOL_INVALID', field + ' 字段无效', ErrorStage.PROTOCOL, false);
  }
  return raw[field] as string[];
}

function requireLevelArrayInSet(raw: Record<string, Object>, field: string, allowed: string[]): string[] {
  if (!isLevelArrayInSet(raw[field], allowed)) {
    throw new AppError('E_PROTOCOL_INVALID', field + ' 字段无效', ErrorStage.PROTOCOL, false);
  }
  return raw[field] as string[];
}

function requireStringInSet(raw: Record<string, Object>, field: string, allowed: string[]): string {
  if (!isStringInSet(raw[field], allowed)) {
    throw new AppError('E_PROTOCOL_INVALID', field + ' 字段无效', ErrorStage.PROTOCOL, false);
  }
  return raw[field] as string;
}

function requireRound(raw: Record<string, Object>, field: string): number {
  const value: Object | undefined = raw[field];
  if (typeof value !== 'number' || !Number.isInteger(value) ||
    (value !== 1 && value !== 2)) {
    throw new AppError('E_PROTOCOL_INVALID', field + ' 字段无效', ErrorStage.PROTOCOL, false);
  }
  return value;
}

function optionalString(raw: Record<string, Object>, field: string): string | undefined {
  if (raw[field] === undefined) {
    return undefined;
  }
  if (typeof raw[field] !== 'string') {
    throw new AppError('E_PROTOCOL_INVALID', field + ' 字段无效', ErrorStage.PROTOCOL, false);
  }
  return raw[field] as string;
}

function validateEvidenceUnit(raw: Record<string, Object>): EvidenceUnit {
  const semanticContractVersion: string = requireString(raw, 'semanticContractVersion');
  if (semanticContractVersion !== SEMANTIC_CONTRACT_VERSION) {
    throw new AppError('E_PROTOCOL_INVALID', 'semanticContractVersion 不一致', ErrorStage.PROTOCOL, false);
  }
  const evidenceId: string = requireNonEmptyString(raw, 'evidenceId');
  const evidenceGroupId: string = requireNonEmptyString(raw, 'evidenceGroupId');
  const sourceDeviceId: string = requireNonEmptyString(raw, 'sourceDeviceId');
  const sourceDocId: string = requireNonEmptyString(raw, 'sourceDocId');
  const sourceChunkId: string | undefined = optionalString(raw, 'sourceChunkId');
  const parentEvidenceId: string | undefined = optionalString(raw, 'parentEvidenceId');
  const level: string = requireStringInSet(raw, 'level', VALID_EVIDENCE_LEVELS);
  const title: string = requireNonEmptyString(raw, 'title');
  const summary: string | undefined = optionalString(raw, 'summary');
  const snippet: string | undefined = optionalString(raw, 'snippet');
  const relevance: number = requireUnitInterval(raw, 'relevance');
  const coveredConcepts: string[] = requireStringArray(raw, 'coveredConcepts');
  const estimatedCoverageGain: number = requireUnitInterval(raw, 'estimatedCoverageGain');
  const byteCost: number = requireNumber(raw, 'byteCost');
  if (byteCost <= 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'byteCost 字段无效', ErrorStage.PROTOCOL, false);
  }
  const privacyLevel: string = requireStringInSet(raw, 'privacyLevel', VALID_PRIVACY_LEVELS);
  const privacyCost: number = requireUnitInterval(raw, 'privacyCost');
  const energyCost: number = requireUnitInterval(raw, 'energyCost');
  const hash: string = requireNonEmptyString(raw, 'hash');
  const canEscalateTo: string[] = requireLevelArrayInSet(raw, 'canEscalateTo', VALID_CAN_ESCALATE_LEVELS);
  const evidence: EvidenceUnit = {
    semanticContractVersion: '1.0',
    evidenceId: evidenceId,
    evidenceGroupId: evidenceGroupId,
    sourceDeviceId: sourceDeviceId,
    sourceDocId: sourceDocId,
    level: level as 'L1' | 'L2',
    title: title,
    relevance: relevance,
    coveredConcepts: coveredConcepts,
    estimatedCoverageGain: estimatedCoverageGain,
    byteCost: byteCost,
    privacyLevel: privacyLevel as 'LOCAL_ONLY' | 'PRIVATE_GROUP',
    privacyCost: privacyCost,
    energyCost: energyCost,
    hash: hash,
    canEscalateTo: canEscalateTo as ('L1' | 'L2')[]
  };
  if (sourceChunkId !== undefined) {
    evidence.sourceChunkId = sourceChunkId;
  }
  if (parentEvidenceId !== undefined) {
    evidence.parentEvidenceId = parentEvidenceId;
  }
  if (summary !== undefined) {
    evidence.summary = summary;
  }
  if (snippet !== undefined) {
    evidence.snippet = snippet;
  }
  return evidence;
}

function validateDeviceProfileAdvertisement(raw: Record<string, Object>): DeviceProfileAdvertisement {
  const semanticContractVersion: string = requireString(raw, 'semanticContractVersion');
  if (semanticContractVersion !== SEMANTIC_CONTRACT_VERSION) {
    throw new AppError('E_PROTOCOL_INVALID', 'semanticContractVersion 不一致', ErrorStage.PROTOCOL, false);
  }
  const deviceId: string = requireNonEmptyString(raw, 'deviceId');
  const deviceAlias: string = requireNonEmptyString(raw, 'deviceAlias');
  const profileVersion: string = requireNonEmptyString(raw, 'profileVersion');
  const indexVersion: string = requireNonEmptyString(raw, 'indexVersion');
  const indexState: string = requireStringInSet(raw, 'indexState', VALID_INDEX_STATES);
  const knowledgeDomains: string[] = requireStringArray(raw, 'knowledgeDomains');
  const modalities: string[] = requireStringArray(raw, 'modalities');
  const retrievalModes: string[] = requireStringArray(raw, 'retrievalModes');
  const supportedLevels: string[] = requireLevelArrayInSet(raw, 'supportedLevels', VALID_ACCEPTABLE_LEVELS);
  const advertisedAtMs: number = requireNumber(raw, 'advertisedAtMs');
  const ttlMs: number = requireNumber(raw, 'ttlMs');
  if (ttlMs <= 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'ttlMs 字段无效', ErrorStage.PROTOCOL, false);
  }
  return {
    semanticContractVersion: '1.0',
    deviceId: deviceId,
    deviceAlias: deviceAlias,
    profileVersion: profileVersion,
    indexVersion: indexVersion,
    indexState: indexState as 'NOT_READY' | 'INDEXING' | 'READY',
    knowledgeDomains: knowledgeDomains,
    modalities: modalities,
    retrievalModes: retrievalModes,
    supportedLevels: supportedLevels as ('L1' | 'L2')[],
    advertisedAtMs: advertisedAtMs,
    ttlMs: ttlMs
  };
}

function validateTaskRequestFromRaw(raw: Record<string, Object>): TaskRequest {
  const semanticContractVersion: string = requireString(raw, 'semanticContractVersion');
  if (semanticContractVersion !== SEMANTIC_CONTRACT_VERSION) {
    throw new AppError('E_PROTOCOL_INVALID', 'semanticContractVersion 不一致', ErrorStage.PROTOCOL, false);
  }
  const taskId: string = requireNonEmptyString(raw, 'taskId');
  const queryText: string = requireNonEmptyString(raw, 'queryText');
  const requiredConcepts: string[] = requireStringArray(raw, 'requiredConcepts');
  for (const concept of requiredConcepts) {
    if (concept.trim().length === 0) {
      throw new AppError('E_PROTOCOL_INVALID', 'requiredConcepts 字段无效', ErrorStage.PROTOCOL, false);
    }
  }
  const requiredConfidence: number = requireUnitInterval(raw, 'requiredConfidence');
  const coverageThreshold: number = requireUnitInterval(raw, 'coverageThreshold');
  const latencyBudgetMs: number = requireNumber(raw, 'latencyBudgetMs');
  if (!Number.isInteger(latencyBudgetMs) || latencyBudgetMs <= 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'latencyBudgetMs 字段无效', ErrorStage.PROTOCOL, false);
  }
  const byteBudget: number = requireNumber(raw, 'byteBudget');
  if (!Number.isInteger(byteBudget) || byteBudget <= 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'byteBudget 字段无效', ErrorStage.PROTOCOL, false);
  }
  const privacyLevel: string = requireStringInSet(raw, 'privacyLevel', VALID_PRIVACY_LEVELS);
  const acceptableLevels: string[] = requireLevelArrayInSet(raw, 'acceptableLevels', VALID_ACCEPTABLE_LEVELS);
  if (acceptableLevels.length === 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'acceptableLevels 字段无效', ErrorStage.PROTOCOL, false);
  }
  const task: TaskRequest = {
    semanticContractVersion: '1.0',
    taskId: taskId,
    queryText: queryText,
    requiredConcepts: requiredConcepts,
    requiredConfidence: requiredConfidence,
    coverageThreshold: coverageThreshold,
    latencyBudgetMs: latencyBudgetMs,
    byteBudget: byteBudget,
    privacyLevel: privacyLevel as 'LOCAL_ONLY' | 'PRIVATE_GROUP',
    acceptableLevels: acceptableLevels as ('L1' | 'L2')[]
  };
  // Reuse shared semantic contract validator for additional consistency (e.g. filter validation).
  // It throws KnowledgeError; we rethrow as AppError to keep the codec's error surface uniform.
  try {
    validateTaskRequest(task);
  } catch (_e) {
    throw new AppError('E_PROTOCOL_INVALID', 'task 字段无效', ErrorStage.PROTOCOL, false);
  }
  if (raw['filters'] !== undefined) {
    const filtersRaw: Object | undefined = raw['filters'];
    if (filtersRaw === undefined || typeof filtersRaw !== 'object' ||
      filtersRaw === null || Array.isArray(filtersRaw)) {
      throw new AppError('E_PROTOCOL_INVALID', 'filters 字段无效', ErrorStage.PROTOCOL, false);
    }
    // validateTaskRequest already covers filter validation when present; we accept the filters object as-is.
    task.filters = filtersRaw as TaskRequestFilters;
  }
  return task;
}

function validateTaskSufficiencyResultFromRaw(raw: Record<string, Object>): TaskSufficiencyResult {
  const feedback: string = requireStringInSet(raw, 'feedback', VALID_TSF_FEEDBACKS);
  const coverage: number = requireUnitInterval(raw, 'coverage');
  const confidence: number = requireUnitInterval(raw, 'confidence');
  const diversity: number = requireUnitInterval(raw, 'diversity');
  const coveredConcepts: string[] = requireStringArray(raw, 'coveredConcepts');
  const missingConcepts: string[] = requireStringArray(raw, 'missingConcepts');
  const acceptedEvidenceIds: string[] = requireStringArray(raw, 'acceptedEvidenceIds');
  return {
    feedback: feedback as 'ENOUGH' | 'NEED_MORE' | 'ABORT',
    coverage: coverage,
    confidence: confidence,
    diversity: diversity,
    coveredConcepts: coveredConcepts,
    missingConcepts: missingConcepts,
    acceptedEvidenceIds: acceptedEvidenceIds
  };
}

function validateEvidenceArray(evidenceRaw: Object): EvidenceUnit[] {
  if (!Array.isArray(evidenceRaw)) {
    throw new AppError('E_PROTOCOL_INVALID', 'evidence 字段无效', ErrorStage.PROTOCOL, false);
  }
  const arr: Object[] = evidenceRaw as Object[];
  if (arr.length === 0) {
    throw new AppError('E_PROTOCOL_INVALID', 'evidence 不能为空', ErrorStage.PROTOCOL, false);
  }
  const seenIds: Set<string> = new Set<string>();
  const evidence: EvidenceUnit[] = [];
  for (const item of arr) {
    if (item === undefined || typeof item !== 'object' || item === null || Array.isArray(item)) {
      throw new AppError('E_PROTOCOL_INVALID', 'evidence 项无效', ErrorStage.PROTOCOL, false);
    }
    const unit: EvidenceUnit = validateEvidenceUnit(item as Record<string, Object>);
    if (seenIds.has(unit.evidenceId)) {
      throw new AppError('E_PROTOCOL_INVALID', 'evidenceId 重复', ErrorStage.PROTOCOL, false);
    }
    seenIds.add(unit.evidenceId);
    evidence.push(unit);
  }
  return evidence;
}

export class ProtocolCodec {
  encode(envelope: ProtocolEnvelope): string {
    const text: string = JSON.stringify(envelope);
    if (countUtf8Bytes(text) > MAX_MESSAGE_BYTES) {
      throw new AppError('E_PROTOCOL_INVALID', '消息超过 16 KiB 上限', ErrorStage.PROTOCOL, false);
    }
    return text;
  }

  decode(text: string): ProtocolEnvelope {
    if (countUtf8Bytes(text) > MAX_MESSAGE_BYTES) {
      throw new AppError('E_PROTOCOL_INVALID', '消息超过 16 KiB 上限', ErrorStage.PROTOCOL, false);
    }

    let raw: Record<string, Object>;
    try {
      raw = JSON.parse(text) as Record<string, Object>;
    } catch (_e) {
      throw new AppError('E_PROTOCOL_INVALID', 'JSON 解析失败', ErrorStage.PROTOCOL, false);
    }

    if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
      throw new AppError('E_PROTOCOL_INVALID', '根对象必须为 JSON 对象', ErrorStage.PROTOCOL, false);
    }

    if (raw['version'] !== PROTOCOL_VERSION) {
      throw new AppError('E_PROTOCOL_INVALID', '未知协议版本', ErrorStage.PROTOCOL, false);
    }

    const typeVal: string = raw['type'] as string;
    if (typeof raw['type'] !== 'string' || VALID_MESSAGE_TYPES.indexOf(typeVal) === -1) {
      throw new AppError('E_PROTOCOL_INVALID', '未知消息类型', ErrorStage.PROTOCOL, false);
    }

    checkRequiredFields(raw);

    if (typeof raw['messageId'] !== 'string' || (raw['messageId'] as string).length === 0) {
      throw new AppError('E_PROTOCOL_INVALID', 'messageId 无效', ErrorStage.PROTOCOL, false);
    }
    if (typeof raw['sessionId'] !== 'string' || (raw['sessionId'] as string).length === 0) {
      throw new AppError('E_PROTOCOL_INVALID', 'sessionId 无效', ErrorStage.PROTOCOL, false);
    }
    if (typeof raw['requestId'] !== 'string' || (raw['requestId'] as string).length === 0) {
      throw new AppError('E_PROTOCOL_INVALID', 'requestId 无效', ErrorStage.PROTOCOL, false);
    }
    if (typeof raw['sentAt'] !== 'number') {
      throw new AppError('E_PROTOCOL_INVALID', 'sentAt 无效', ErrorStage.PROTOCOL, false);
    }

    const messageType: MessageType = raw['type'] as MessageType;
    const rawPayload: Record<string, Object> = raw['payload'] as Record<string, Object>;
    if (typeof rawPayload !== 'object' || rawPayload === null || Array.isArray(rawPayload)) {
      throw new AppError('E_PROTOCOL_INVALID', 'payload 无效', ErrorStage.PROTOCOL, false);
    }

    const payload: ProtocolPayload = this.validatePayload(messageType, rawPayload);
    const result: ProtocolEnvelope = {
      version: raw['version'] as string,
      type: messageType,
      messageId: raw['messageId'] as string,
      sessionId: raw['sessionId'] as string,
      requestId: raw['requestId'] as string,
      sentAt: raw['sentAt'] as number,
      payload: payload
    };
    return result;
  }

  private validatePayload(type: MessageType, raw: Record<string, Object>): ProtocolPayload {
    switch (type) {
      case MessageType.QUERY: {
        if (typeof raw['question'] !== 'string') {
          throw new AppError('E_PROTOCOL_INVALID', 'question 字段无效', ErrorStage.PROTOCOL, false);
        }
        const question: string = (raw['question'] as string).trim();
        if (question.length === 0 || question.length > MAX_QUESTION_CHARS) {
          throw new AppError('E_QUERY_INVALID', '问题长度无效', ErrorStage.QUERY, true);
        }
        return { question: question } as QueryPayload;
      }
      case MessageType.QUERY_ACK: {
        if (typeof raw['acceptedAt'] !== 'number') {
          throw new AppError('E_PROTOCOL_INVALID', 'acceptedAt 字段无效', ErrorStage.PROTOCOL, false);
        }
        return { acceptedAt: raw['acceptedAt'] as number } as QueryAckPayload;
      }
      case MessageType.RESULT: {
        if (typeof raw['summary'] !== 'string') {
          throw new AppError('E_PROTOCOL_INVALID', 'summary 字段无效', ErrorStage.PROTOCOL, false);
        }
        if (typeof raw['sourceDeviceAlias'] !== 'string') {
          throw new AppError('E_PROTOCOL_INVALID', 'sourceDeviceAlias 字段无效', ErrorStage.PROTOCOL, false);
        }
        if (typeof raw['processingMs'] !== 'number') {
          throw new AppError('E_PROTOCOL_INVALID', 'processingMs 字段无效', ErrorStage.PROTOCOL, false);
        }
        const summary: string = raw['summary'] as string;
        if (summary.length === 0 || summary.length > MAX_SUMMARY_CHARS) {
          throw new AppError('E_PROTOCOL_INVALID', '摘要长度无效', ErrorStage.PROTOCOL, false);
        }
        const resultPayload: ResultPayload = {
          summary: summary,
          sourceDeviceAlias: raw['sourceDeviceAlias'] as string,
          processingMs: raw['processingMs'] as number
        };
        if (raw['resultType'] !== undefined) {
          if (raw['resultType'] !== 'SUMMARY' && raw['resultType'] !== 'KNOWLEDGE') {
            throw new AppError('E_PROTOCOL_INVALID', 'resultType is invalid', ErrorStage.PROTOCOL, false);
          }
          resultPayload.resultType = raw['resultType'] as 'SUMMARY' | 'KNOWLEDGE';
        }
        if (resultPayload.resultType === 'KNOWLEDGE') {
          resultPayload.knowledgeResult = this.validateKnowledgeResult(raw['knowledgeResult']);
        }
        return resultPayload;
      }
      case MessageType.ERROR: {
        if (typeof raw['code'] !== 'string' || (raw['code'] as string).length === 0) {
          throw new AppError('E_PROTOCOL_INVALID', 'error code 无效', ErrorStage.PROTOCOL, false);
        }
        if (typeof raw['message'] !== 'string' || (raw['message'] as string).length === 0) {
          throw new AppError('E_PROTOCOL_INVALID', 'error message 无效', ErrorStage.PROTOCOL, false);
        }
        return {
          code: raw['code'] as string,
          message: raw['message'] as string
        } as ErrorPayload;
      }
      case MessageType.PROFILE: {
        const profileRaw: Object | undefined = raw['profile'];
        if (profileRaw === undefined || typeof profileRaw !== 'object' ||
          profileRaw === null || Array.isArray(profileRaw)) {
          throw new AppError('E_PROTOCOL_INVALID', 'profile 字段无效', ErrorStage.PROTOCOL, false);
        }
        const profile: DeviceProfileAdvertisement =
          validateDeviceProfileAdvertisement(profileRaw as Record<string, Object>);
        return { profile: profile } as ProfilePayload;
      }
      case MessageType.TASK: {
        const taskRaw: Object | undefined = raw['task'];
        if (taskRaw === undefined || typeof taskRaw !== 'object' ||
          taskRaw === null || Array.isArray(taskRaw)) {
          throw new AppError('E_PROTOCOL_INVALID', 'task 字段无效', ErrorStage.PROTOCOL, false);
        }
        const task: TaskRequest = validateTaskRequestFromRaw(taskRaw as Record<string, Object>);
        const round: number = requireRound(raw, 'round');
        return { task: task, round: round } as TaskPayload;
      }
      case MessageType.TASK_ACK: {
        const taskId: string = requireNonEmptyString(raw, 'taskId');
        const round: number = requireRound(raw, 'round');
        const acceptedAt: number = requireNumber(raw, 'acceptedAt');
        const candidateCount: number = requireNumber(raw, 'candidateCount');
        if (!Number.isInteger(candidateCount) || candidateCount < 0) {
          throw new AppError('E_PROTOCOL_INVALID', 'candidateCount 字段无效', ErrorStage.PROTOCOL, false);
        }
        return {
          taskId: taskId,
          round: round,
          acceptedAt: acceptedAt,
          candidateCount: candidateCount
        } as TaskAckPayload;
      }
      case MessageType.EVIDENCE: {
        const taskId: string = requireNonEmptyString(raw, 'taskId');
        const round: number = requireRound(raw, 'round');
        const evidence: EvidenceUnit[] = validateEvidenceArray(raw['evidence']);
        return {
          taskId: taskId,
          round: round,
          evidence: evidence
        } as EvidencePayload;
      }
      case MessageType.TSF: {
        const taskId: string = requireNonEmptyString(raw, 'taskId');
        const round: number = requireRound(raw, 'round');
        const resultRaw: Object | undefined = raw['result'];
        if (resultRaw === undefined || typeof resultRaw !== 'object' ||
          resultRaw === null || Array.isArray(resultRaw)) {
          throw new AppError('E_PROTOCOL_INVALID', 'result 字段无效', ErrorStage.PROTOCOL, false);
        }
        const result: TaskSufficiencyResult =
          validateTaskSufficiencyResultFromRaw(resultRaw as Record<string, Object>);
        return {
          taskId: taskId,
          round: round,
          result: result
        } as TsfPayload;
      }
      case MessageType.CANCEL: {
        const taskId: string = requireNonEmptyString(raw, 'taskId');
        const code: string = requireNonEmptyString(raw, 'code');
        const reason: string = requireNonEmptyString(raw, 'reason');
        return {
          taskId: taskId,
          code: code,
          reason: reason
        } as CancelPayload;
      }
      default:
        throw new AppError('E_PROTOCOL_INVALID', '未知消息类型', ErrorStage.PROTOCOL, false);
    }
  }

  createQuery(messageId: string, sessionId: string, requestId: string,
    sentAt: number, payload: QueryPayload): ProtocolEnvelope {
    const question: string = payload.question.trim();
    if (question.length === 0 || question.length > MAX_QUESTION_CHARS) {
      throw new AppError('E_QUERY_INVALID', '问题长度无效', ErrorStage.QUERY, true);
    }
    const queryPayload: QueryPayload = { question: question };
    return {
      version: PROTOCOL_VERSION, type: MessageType.QUERY, messageId: messageId, sessionId: sessionId,
      requestId: requestId, sentAt: sentAt, payload: queryPayload
    };
  }

  createAck(messageId: string, sessionId: string, requestId: string,
    sentAt: number, payload: QueryAckPayload): ProtocolEnvelope {
    return {
      version: PROTOCOL_VERSION, type: MessageType.QUERY_ACK, messageId: messageId, sessionId: sessionId,
      requestId: requestId, sentAt: sentAt, payload: payload
    };
  }

  createResult(messageId: string, sessionId: string, requestId: string,
    sentAt: number, payload: ResultPayload): ProtocolEnvelope {
    if (payload.summary.length === 0 || payload.summary.length > MAX_SUMMARY_CHARS) {
      throw new AppError('E_QUERY_INVALID', '摘要长度无效', ErrorStage.QUERY, true);
    }
    if (payload.resultType === 'KNOWLEDGE' &&
      (payload.knowledgeResult === undefined || payload.knowledgeResult.requestId !== requestId)) {
      throw new AppError('E_QUERY_INVALID', 'Knowledge result does not match request', ErrorStage.QUERY, true);
    }
    return {
      version: PROTOCOL_VERSION, type: MessageType.RESULT, messageId: messageId, sessionId: sessionId,
      requestId: requestId, sentAt: sentAt, payload: payload
    };
  }

  createError(messageId: string, sessionId: string, requestId: string,
    sentAt: number, payload: ErrorPayload): ProtocolEnvelope {
    return {
      version: PROTOCOL_VERSION, type: MessageType.ERROR, messageId: messageId, sessionId: sessionId,
      requestId: requestId, sentAt: sentAt, payload: payload
    };
  }

  createProfile(messageId: string, sessionId: string, requestId: string,
    sentAt: number, payload: ProfilePayload): ProtocolEnvelope {
    validateTypedProfile(payload.profile);
    return {
      version: PROTOCOL_VERSION, type: MessageType.PROFILE, messageId: messageId, sessionId: sessionId,
      requestId: requestId, sentAt: sentAt, payload: payload
    };
  }

  createTask(messageId: string, sessionId: string, requestId: string,
    sentAt: number, payload: TaskPayload): ProtocolEnvelope {
    if (!isRoundValidNumber(payload.round)) {
      throw new AppError('E_PROTOCOL_INVALID', 'round 字段无效', ErrorStage.PROTOCOL, false);
    }
    // Delegate to the shared semantic contract validator; it throws KnowledgeError on invalid
    // tasks. We rethrow as AppError to keep the codec's error surface uniform.
    try {
      validateTaskRequest(payload.task);
    } catch (e) {
      throw new AppError('E_PROTOCOL_INVALID', 'task 字段无效', ErrorStage.PROTOCOL, false);
    }
    return {
      version: PROTOCOL_VERSION, type: MessageType.TASK, messageId: messageId, sessionId: sessionId,
      requestId: requestId, sentAt: sentAt, payload: payload
    };
  }

  createTaskAck(messageId: string, sessionId: string, requestId: string,
    sentAt: number, payload: TaskAckPayload): ProtocolEnvelope {
    if (typeof payload.taskId !== 'string' || payload.taskId.length === 0) {
      throw new AppError('E_PROTOCOL_INVALID', 'taskId 字段无效', ErrorStage.PROTOCOL, false);
    }
    if (!isRoundValidNumber(payload.round)) {
      throw new AppError('E_PROTOCOL_INVALID', 'round 字段无效', ErrorStage.PROTOCOL, false);
    }
    if (typeof payload.acceptedAt !== 'number' || !Number.isFinite(payload.acceptedAt)) {
      throw new AppError('E_PROTOCOL_INVALID', 'acceptedAt 字段无效', ErrorStage.PROTOCOL, false);
    }
    if (typeof payload.candidateCount !== 'number' ||
      !Number.isInteger(payload.candidateCount) || payload.candidateCount < 0) {
      throw new AppError('E_PROTOCOL_INVALID', 'candidateCount 字段无效', ErrorStage.PROTOCOL, false);
    }
    return {
      version: PROTOCOL_VERSION, type: MessageType.TASK_ACK, messageId: messageId, sessionId: sessionId,
      requestId: requestId, sentAt: sentAt, payload: payload
    };
  }

  createEvidence(messageId: string, sessionId: string, requestId: string,
    sentAt: number, payload: EvidencePayload): ProtocolEnvelope {
    if (typeof payload.taskId !== 'string' || payload.taskId.length === 0) {
      throw new AppError('E_PROTOCOL_INVALID', 'taskId 字段无效', ErrorStage.PROTOCOL, false);
    }
    if (!isRoundValidNumber(payload.round)) {
      throw new AppError('E_PROTOCOL_INVALID', 'round 字段无效', ErrorStage.PROTOCOL, false);
    }
    if (!Array.isArray(payload.evidence) || payload.evidence.length === 0) {
      throw new AppError('E_PROTOCOL_INVALID', 'evidence 不能为空', ErrorStage.PROTOCOL, false);
    }
    const seenIds: Set<string> = new Set<string>();
    for (const unit of payload.evidence) {
      if (unit === null || typeof unit !== 'object') {
        throw new AppError('E_PROTOCOL_INVALID', 'evidence 项无效', ErrorStage.PROTOCOL, false);
      }
      validateTypedEvidenceUnit(unit);
      if (seenIds.has(unit.evidenceId)) {
        throw new AppError('E_PROTOCOL_INVALID', 'evidenceId 重复', ErrorStage.PROTOCOL, false);
      }
      seenIds.add(unit.evidenceId);
    }
    // P4 EVIDENCE performs a full UTF-8 message size check via encode() before transmission;
    // callers should use codec.encode(envelope) to enforce MAX_MESSAGE_BYTES.
    return {
      version: PROTOCOL_VERSION, type: MessageType.EVIDENCE, messageId: messageId, sessionId: sessionId,
      requestId: requestId, sentAt: sentAt, payload: payload
    };
  }

  createTsf(messageId: string, sessionId: string, requestId: string,
    sentAt: number, payload: TsfPayload): ProtocolEnvelope {
    if (typeof payload.taskId !== 'string' || payload.taskId.length === 0) {
      throw new AppError('E_PROTOCOL_INVALID', 'taskId 字段无效', ErrorStage.PROTOCOL, false);
    }
    if (!isRoundValidNumber(payload.round)) {
      throw new AppError('E_PROTOCOL_INVALID', 'round 字段无效', ErrorStage.PROTOCOL, false);
    }
    validateTypedTsfResult(payload.result);
    return {
      version: PROTOCOL_VERSION, type: MessageType.TSF, messageId: messageId, sessionId: sessionId,
      requestId: requestId, sentAt: sentAt, payload: payload
    };
  }

  createCancel(messageId: string, sessionId: string, requestId: string,
    sentAt: number, payload: CancelPayload): ProtocolEnvelope {
    if (typeof payload.taskId !== 'string' || payload.taskId.length === 0) {
      throw new AppError('E_PROTOCOL_INVALID', 'taskId 字段无效', ErrorStage.PROTOCOL, false);
    }
    if (typeof payload.code !== 'string' || payload.code.length === 0) {
      throw new AppError('E_PROTOCOL_INVALID', 'code 字段无效', ErrorStage.PROTOCOL, false);
    }
    if (typeof payload.reason !== 'string' || payload.reason.length === 0) {
      throw new AppError('E_PROTOCOL_INVALID', 'reason 字段无效', ErrorStage.PROTOCOL, false);
    }
    return {
      version: PROTOCOL_VERSION, type: MessageType.CANCEL, messageId: messageId, sessionId: sessionId,
      requestId: requestId, sentAt: sentAt, payload: payload
    };
  }

  private validateKnowledgeResult(value: Object | undefined): LocalKnowledgeResult {
    if (value === undefined || typeof value !== 'object' || value === null || Array.isArray(value)) {
      throw new AppError('E_PROTOCOL_INVALID', 'knowledgeResult is invalid', ErrorStage.PROTOCOL, false);
    }
    const raw: Record<string, Object> = value as Record<string, Object>;
    if (raw['contractVersion'] !== '1.0' || typeof raw['requestId'] !== 'string' ||
      (raw['level'] !== 'L1' && raw['level'] !== 'L2') || typeof raw['itemCount'] !== 'number' ||
      typeof raw['payloadJson'] !== 'string' || typeof raw['truncated'] !== 'boolean' ||
      typeof raw['retrievalMs'] !== 'number' || typeof raw['indexVersion'] !== 'string' ||
      typeof raw['generatedAt'] !== 'number') {
      throw new AppError('E_PROTOCOL_INVALID', 'knowledgeResult content is invalid', ErrorStage.PROTOCOL, false);
    }
    try {
      JSON.parse(raw['payloadJson'] as string);
    } catch (_error) {
      throw new AppError('E_PROTOCOL_INVALID', 'knowledgeResult payloadJson is invalid', ErrorStage.PROTOCOL, false);
    }
    return {
      contractVersion: '1.0',
      requestId: raw['requestId'] as string,
      level: raw['level'] as 'L1' | 'L2',
      itemCount: raw['itemCount'] as number,
      payloadJson: raw['payloadJson'] as string,
      truncated: raw['truncated'] as boolean,
      retrievalMs: raw['retrievalMs'] as number,
      indexVersion: raw['indexVersion'] as string,
      generatedAt: raw['generatedAt'] as number
    };
  }
}
