import {
  CrossDeviceEnvelope,
  CrossDeviceProtocolMessageType,
  SEMALINK_CROSS_DEVICE_PROTOCOL_VERSION
} from './CrossDeviceProtocolModels';
import { TaskRequest, validateTaskRequest } from
  '../../contracts/semantic/SemanticModels';

export const CROSS_DEVICE_MAX_LOGICAL_BYTES: number = 64 * 1024;
export const CROSS_DEVICE_MAX_QUERY_CHARS: number = 4096;

const MESSAGE_TYPES: string[] = [
  'HELLO', 'PING', 'PONG', 'PROFILE_DIGEST', 'PROFILE_REQUEST',
  'PROFILE_RESPONSE', 'QUERY_REQUEST', 'QUERY_RESPONSE', 'QUERY_ERROR', 'QUERY_CANCEL'
];

const FORBIDDEN_FIELDS: string[] = [
  'deviceId', 'networkId', 'filePath', 'absolutePath', 'sql', 'databaseId',
  'documentBody', 'documentContent', 'hardwareId', 'documentId', 'documentIds',
  'chunkId', 'sourceDocId', 'sourceChunkId', 'evidenceId', 'evidenceGroupId'
];

export class CrossDeviceProtocolError extends Error {
  readonly code: string;

  constructor(code: string) {
    super(code);
    this.code = code;
  }
}

function invalid(code: string): CrossDeviceProtocolError {
  return new CrossDeviceProtocolError(code);
}

function utf8Length(text: string): number {
  let bytes: number = 0;
  for (let index: number = 0; index < text.length; index++) {
    const point: number = text.codePointAt(index) ?? 0;
    bytes += point <= 0x7f ? 1 : point <= 0x7ff ? 2 : point <= 0xffff ? 3 : 4;
    if (point > 0xffff) {
      index++;
    }
  }
  return bytes;
}

function requireText(value: string, field: string): void {
  if (typeof value !== 'string' || value.length === 0 || value.length > 256) {
    throw invalid('INVALID_' + field.toUpperCase());
  }
}

function validatePrivacy(value: Object): void {
  if (value === null || typeof value !== 'object') {
    return;
  }
  if (Array.isArray(value)) {
    const values: Object[] = value as Object[];
    values.forEach((item: Object): void => validatePrivacy(item));
    return;
  }
  const record: Record<string, Object> = value as Record<string, Object>;
  const keys: string[] = Object.keys(record);
  keys.forEach((key: string): void => {
    if (FORBIDDEN_FIELDS.indexOf(key) >= 0) {
      throw invalid('FORBIDDEN_FIELD');
    }
    validatePrivacy(record[key]);
  });
}

function recordOf(value: Object): Record<string, Object> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw invalid('INVALID_PAYLOAD');
  }
  return value as Record<string, Object>;
}

function requireOnlyKeys(record: Record<string, Object>, allowed: string[]): void {
  if (Object.keys(record).some(
    (key: string): boolean => allowed.indexOf(key) < 0)) {
    throw invalid('UNEXPECTED_FIELD');
  }
}

function requireStringField(record: Record<string, Object>, field: string,
  maximum: number = 256): string {
  const value: Object | undefined = record[field];
  if (typeof value !== 'string' || value.length === 0 || value.length > maximum) {
    throw invalid('INVALID_' + field.toUpperCase());
  }
  return value;
}

function requireStringArray(record: Record<string, Object>, field: string,
  maximum: number): void {
  const value: Object | undefined = record[field];
  if (!Array.isArray(value) || value.length > maximum ||
    (value as Object[]).some((item: Object): boolean =>
      typeof item !== 'string' || item.length > 256)) {
    throw invalid('INVALID_' + field.toUpperCase());
  }
}

function validateRemoteProfile(value: Object): void {
  const profile: Record<string, Object> = recordOf(value);
  requireOnlyKeys(profile, [
    'peerKey', 'profileVersion', 'profileDigest', 'indexState',
    'knowledgeDomains', 'documentCount', 'chunkCount', 'retrievalModes',
    'supportedLevels', 'updatedAtMs', 'receivedAtMs', 'expiresAtMs'
  ]);
  requireStringField(profile, 'peerKey');
  requireStringField(profile, 'profileVersion');
  requireStringField(profile, 'profileDigest');
  const indexState: string = requireStringField(profile, 'indexState');
  if (['NOT_READY', 'INDEXING', 'READY'].indexOf(indexState) < 0) {
    throw invalid('INVALID_PROFILE');
  }
  requireStringArray(profile, 'knowledgeDomains', 20);
  requireStringArray(profile, 'retrievalModes', 16);
  requireStringArray(profile, 'supportedLevels', 2);
  const retrievalModes: Object[] = profile['retrievalModes'] as Object[];
  const supportedLevels: Object[] = profile['supportedLevels'] as Object[];
  if (retrievalModes.some((mode: Object): boolean => mode !== 'keyword') ||
    supportedLevels.some((level: Object): boolean => level !== 'L1' && level !== 'L2')) {
    throw invalid('INVALID_PROFILE');
  }
  ['documentCount', 'chunkCount', 'updatedAtMs', 'receivedAtMs', 'expiresAtMs']
    .forEach((field: string): void => {
      const numberValue: Object | undefined = profile[field];
      if (typeof numberValue !== 'number' ||
        !Number.isInteger(numberValue) || numberValue < 0) {
        throw invalid('INVALID_PROFILE');
      }
    });
}

function validateRemoteEvidenceArray(value: Object | undefined): void {
  if (!Array.isArray(value) || value.length > 5) {
    throw invalid('INVALID_EVIDENCE');
  }
  (value as Object[]).forEach((item: Object): void => {
    const evidence: Record<string, Object> = recordOf(item);
    requireOnlyKeys(evidence, [
      'title', 'summary', 'snippet', 'relevance', 'knowledgeDomain',
      'updatedAtMs', 'level', 'sourceDeviceAlias', 'truncated'
    ]);
    requireStringField(evidence, 'title');
    if (typeof evidence['summary'] !== 'string' ||
      typeof evidence['snippet'] !== 'string' ||
      typeof evidence['knowledgeDomain'] !== 'string' ||
      typeof evidence['sourceDeviceAlias'] !== 'string' ||
      typeof evidence['relevance'] !== 'number' ||
      typeof evidence['updatedAtMs'] !== 'number' ||
      typeof evidence['level'] !== 'string' ||
      typeof evidence['truncated'] !== 'boolean') {
      throw invalid('INVALID_EVIDENCE');
    }
    const relevance: number = evidence['relevance'] as number;
    const updatedAtMs: number = evidence['updatedAtMs'] as number;
    if (!Number.isFinite(relevance) || relevance < 0 || relevance > 1 ||
      !Number.isInteger(updatedAtMs) || updatedAtMs < 0 ||
      (evidence['level'] !== 'L1' && evidence['level'] !== 'L2') ||
      (evidence['summary'] as string).length > 1024 ||
      (evidence['snippet'] as string).length > 512 ||
      (evidence['knowledgeDomain'] as string).length > 128 ||
      (evidence['sourceDeviceAlias'] as string).length > 128) {
      throw invalid('INVALID_EVIDENCE');
    }
  });
}

function validatePayload(messageType: CrossDeviceProtocolMessageType, payload: Object): void {
  const request: Record<string, Object> = recordOf(payload);
  validatePrivacy(payload);
  if (messageType === 'HELLO') {
    requireOnlyKeys(request, ['peerKey', 'deviceAlias']);
    requireStringField(request, 'peerKey');
    requireStringField(request, 'deviceAlias', 128);
    return;
  }
  if (messageType === 'PROFILE_DIGEST') {
    requireOnlyKeys(request, ['profileVersion', 'profileDigest']);
    requireStringField(request, 'profileVersion');
    requireStringField(request, 'profileDigest');
    return;
  }
  if (messageType === 'PROFILE_REQUEST') {
    requireOnlyKeys(request, ['requested']);
    if (request['requested'] !== true) {
      throw invalid('INVALID_PROFILE_REQUEST');
    }
    return;
  }
  if (messageType === 'PROFILE_RESPONSE') {
    requireOnlyKeys(request, ['profile']);
    validateRemoteProfile(request['profile']);
    return;
  }
  if (messageType === 'QUERY_REQUEST') {
    requireOnlyKeys(request, ['query', 'knowledgeDomain']);
    const query: Object | undefined = request['query'];
    if (query === undefined) {
      throw invalid('INVALID_QUERY');
    }
    try {
      validateTaskRequest(query as TaskRequest);
    } catch (_) {
      throw invalid('INVALID_QUERY');
    }
    const task: TaskRequest = query as TaskRequest;
    if (task.queryText.length > CROSS_DEVICE_MAX_QUERY_CHARS) {
      throw invalid('INVALID_QUERY');
    }
    const knowledgeDomain: Object | undefined = request['knowledgeDomain'];
    if (typeof knowledgeDomain !== 'string' || knowledgeDomain.length > 128) {
      throw invalid('INVALID_KNOWLEDGEDOMAIN');
    }
    return;
  }
  if (messageType === 'QUERY_RESPONSE' || messageType === 'QUERY_ERROR') {
    requireOnlyKeys(request, ['status', 'evidence', 'truncated']);
    const status: string = requireStringField(request, 'status', 64);
    if ([
      'OK', 'UNAUTHORIZED', 'SHARING_DISABLED', 'LEVEL_DENIED',
      'DEADLINE_EXCEEDED', 'BUSY', 'CANCELLED', 'INVALID_REQUEST',
      'INTERNAL_ERROR'
    ].indexOf(status) < 0) {
      throw invalid('INVALID_QUERY_RESPONSE');
    }
    validateRemoteEvidenceArray(request['evidence']);
    if (typeof request['truncated'] !== 'boolean') {
      throw invalid('INVALID_QUERY_RESPONSE');
    }
    return;
  }
  if (messageType === 'QUERY_CANCEL') {
    requireOnlyKeys(request, ['taskId']);
    requireStringField(request, 'taskId');
    return;
  }
  if (messageType === 'PING' || messageType === 'PONG') {
    requireOnlyKeys(request, []);
    return;
  }
}

export class CrossDeviceProtocolCodec {
  encode(envelope: CrossDeviceEnvelope): string {
    this.validate(envelope);
    const text: string = JSON.stringify(envelope);
    if (utf8Length(text) > CROSS_DEVICE_MAX_LOGICAL_BYTES) {
      throw invalid('MESSAGE_TOO_LARGE');
    }
    return text;
  }

  decode(text: string, nowMs: number = 0): CrossDeviceEnvelope {
    if (typeof text !== 'string' || utf8Length(text) > CROSS_DEVICE_MAX_LOGICAL_BYTES) {
      throw invalid('MESSAGE_TOO_LARGE');
    }
    let parsed: Object;
    try {
      parsed = JSON.parse(text) as Object;
    } catch (_) {
      throw invalid('INVALID_JSON');
    }
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw invalid('INVALID_ENVELOPE');
    }
    const envelope: CrossDeviceEnvelope = parsed as CrossDeviceEnvelope;
    this.validate(envelope);
    if (nowMs > 0 && envelope.deadlineAtMs < nowMs) {
      throw invalid('DEADLINE_EXCEEDED');
    }
    return envelope;
  }

  private validate(envelope: CrossDeviceEnvelope): void {
    requireOnlyKeys(envelope as Object as Record<string, Object>, [
      'protocolVersion', 'messageType', 'messageId', 'requestId', 'taskId',
      'senderAppInstanceId', 'sentAtMs', 'deadlineAtMs', 'sequence', 'payload'
    ]);
    if (envelope.protocolVersion !== SEMALINK_CROSS_DEVICE_PROTOCOL_VERSION) {
      throw invalid('UNSUPPORTED_VERSION');
    }
    if (MESSAGE_TYPES.indexOf(envelope.messageType) < 0) {
      throw invalid('UNKNOWN_MESSAGE_TYPE');
    }
    requireText(envelope.messageId, 'messageId');
    requireText(envelope.requestId, 'requestId');
    requireText(envelope.taskId, 'taskId');
    requireText(envelope.senderAppInstanceId, 'senderAppInstanceId');
    if (!Number.isInteger(envelope.sentAtMs) || envelope.sentAtMs < 0 ||
      !Number.isInteger(envelope.deadlineAtMs) ||
      envelope.deadlineAtMs < envelope.sentAtMs ||
      !Number.isInteger(envelope.sequence) || envelope.sequence < 0) {
      throw invalid('INVALID_TIMING');
    }
    validatePayload(envelope.messageType, envelope.payload);
    if (envelope.messageType === 'QUERY_REQUEST') {
      const payload: Record<string, Object> =
        envelope.payload as Record<string, Object>;
      const query: TaskRequest = payload['query'] as TaskRequest;
      if (query.taskId !== envelope.taskId) {
        throw invalid('TASK_ID_MISMATCH');
      }
    }
    if (envelope.messageType === 'QUERY_CANCEL') {
      const payload: Record<string, Object> =
        envelope.payload as Record<string, Object>;
      if (payload['taskId'] !== envelope.taskId) {
        throw invalid('TASK_ID_MISMATCH');
      }
    }
  }
}
