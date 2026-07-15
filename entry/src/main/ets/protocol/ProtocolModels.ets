export const PROTOCOL_VERSION: string = '1.0';
export const MAX_MESSAGE_BYTES: number = 16 * 1024;
export const MAX_QUESTION_CHARS: number = 1000;
export const MAX_SUMMARY_CHARS: number = 2000;

export enum MessageType { QUERY = 'QUERY', QUERY_ACK = 'QUERY_ACK', RESULT = 'RESULT', ERROR = 'ERROR' }
export interface QueryPayload { question: string; }
export interface QueryAckPayload { acceptedAt: number; }
export interface ResultPayload { summary: string; sourceDeviceAlias: string; processingMs: number; }
export interface ErrorPayload { code: string; message: string; }
export type ProtocolPayload = QueryPayload | QueryAckPayload | ResultPayload | ErrorPayload;
export interface ProtocolEnvelope {
  version: string; type: MessageType; messageId: string; sessionId: string;
  requestId: string; sentAt: number; payload: ProtocolPayload;
}
