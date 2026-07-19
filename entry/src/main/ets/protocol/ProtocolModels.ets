import { LocalKnowledgeResult } from '../contracts/knowledge/KnowledgeModels';
import {
  DeviceProfileAdvertisement,
  TaskRequest,
  EvidenceUnit,
  TaskSufficiencyResult
} from '../contracts/semantic/SemanticModels';

export const PROTOCOL_VERSION: string = '1.0';
// abilityConnectionManager.sendMessage rejects payloads above its 4 KiB transport limit.
export const MAX_MESSAGE_BYTES: number = 4 * 1024;
export const MAX_KNOWLEDGE_PAYLOAD_BYTES: number = 3 * 1024;
export const MAX_QUESTION_CHARS: number = 1000;
export const MAX_SUMMARY_CHARS: number = 2000;

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
