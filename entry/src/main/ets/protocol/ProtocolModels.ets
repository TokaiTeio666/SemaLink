import { LocalKnowledgeResult } from '../contracts/knowledge/KnowledgeModels';
import {
  DeviceProfileAdvertisement,
  TaskRequest,
  EvidenceUnit,
  TaskSufficiencyResult
} from '../contracts/semantic/SemanticModels';

export const PROTOCOL_VERSION: string = '1.0';
// The deployed DSK runtime rejects sendMessage payloads above 1024 UTF-8 bytes.
export const MAX_MESSAGE_BYTES: number = 1024;
export const MAX_KNOWLEDGE_PAYLOAD_BYTES: number = 3 * 1024;
// The knowledge API requires a payload budget of at least 1 KiB. SessionManager
// falls back to a summary when the complete RESULT envelope cannot fit DSK.
export const MAX_REMOTE_KNOWLEDGE_PAYLOAD_BYTES: number = 1024;
export const EVIDENCE_PAGING_VERSION: number = 1;
export const MAX_EVIDENCE_PAGE_COUNT: number = 64;
export const MAX_QUESTION_CHARS: number = 1000;
export const MAX_SUMMARY_CHARS: number = 2000;
// Keep RESULT envelopes below the observed 1 KiB DSK message limit.
export const MAX_WIRE_SUMMARY_CHARS: number = 600;

export enum MessageType {
  QUERY = 'QUERY',
  QUERY_ACK = 'QUERY_ACK',
  RESULT = 'RESULT',
  ERROR = 'ERROR',
  PROFILE = 'PROFILE',
  TASK = 'TASK',
  TASK_ACK = 'TASK_ACK',
  EVIDENCE = 'EVIDENCE',
  TSF = 'TSF',
  CANCEL = 'CANCEL'
}

export interface QueryPayload { question: string; }
export interface QueryAckPayload { acceptedAt: number; }
export type ResultType = 'SUMMARY' | 'KNOWLEDGE';
export interface ResultPayload {
  summary: string;
  sourceDeviceAlias: string;
  processingMs: number;
  resultType?: ResultType;
  knowledgeResult?: LocalKnowledgeResult;
}
export interface ErrorPayload { code: string; message: string; }
export interface ProfilePayload {
  profile: DeviceProfileAdvertisement;
}
export interface TaskPayload {
  task: TaskRequest;
  round: number;
  evidencePagingVersion?: number;
}
export interface TaskAckPayload {
  taskId: string;
  round: number;
  acceptedAt: number;
  candidateCount: number;
}
export interface EvidencePayload {
  taskId: string;
  round: number;
  pageIndex?: number;
  pageCount?: number;
  evidence: EvidenceUnit[];
}
export interface TsfPayload {
  taskId: string;
  round: number;
  result: TaskSufficiencyResult;
}
export interface CancelPayload {
  taskId: string;
  code: string;
  reason: string;
}
export type ProtocolPayload =
  QueryPayload
  | QueryAckPayload
  | ResultPayload
  | ErrorPayload
  | ProfilePayload
  | TaskPayload
  | TaskAckPayload
  | EvidencePayload
  | TsfPayload
  | CancelPayload;
export interface ProtocolEnvelope {
  version: string; type: MessageType; messageId: string; sessionId: string;
  requestId: string; sentAt: number; payload: ProtocolPayload;
}
