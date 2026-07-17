import { LocalKnowledgeResult } from '../contracts/knowledge/KnowledgeModels';

export const PROTOCOL_VERSION: string = '1.0';
// abilityConnectionManager.sendMessage rejects payloads above its 4 KiB transport limit.
export const MAX_MESSAGE_BYTES: number = 4 * 1024;
export const MAX_KNOWLEDGE_PAYLOAD_BYTES: number = 3 * 1024;
export const MAX_QUESTION_CHARS: number = 1000;
export const MAX_SUMMARY_CHARS: number = 2000;

export enum MessageType { QUERY = 'QUERY', QUERY_ACK = 'QUERY_ACK', RESULT = 'RESULT', ERROR = 'ERROR' }
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
export type ProtocolPayload = QueryPayload | QueryAckPayload | ResultPayload | ErrorPayload;
export interface ProtocolEnvelope {
  version: string; type: MessageType; messageId: string; sessionId: string;
  requestId: string; sentAt: number; payload: ProtocolPayload;
}
