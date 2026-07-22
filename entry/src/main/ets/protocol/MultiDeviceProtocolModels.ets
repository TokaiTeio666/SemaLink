import { EvidenceUnit, TaskRequest, TaskSufficiencyFeedback } from '../contracts/semantic/SemanticModels';

export type DataMessageType =
  | 'DATA_BIND' | 'DATA_BIND_ACK' | 'TASK' | 'TASK_ACK' | 'EVIDENCE_BATCH'
  | 'EVIDENCE_COMPLETE' | 'EVIDENCE_PAGE' | 'EVIDENCE_ACK' | 'TSF' | 'ERROR' | 'CANCEL';

export const RELIABLE_WINDOW_SIZE: number = 4;
export const RELIABLE_ACK_TIMEOUT_MS: number = 1500;
export const RELIABLE_MAX_ATTEMPTS: number = 3;
export const RELIABLE_MAX_PAGES: number = 64;

export interface PeerContext {
  taskId: string;
  peerTaskId: string;
  sessionEpoch: string;
  sequence: number;
}
export interface TaskDataPayload { task: TaskRequest; }
export interface TaskAckDataPayload { taskId: string; peerTaskId: string; round: number; acceptedAtMs: number; }
export interface EvidenceBatchPayload {
  taskId: string; peerTaskId: string; round: 1 | 2; evidence: EvidenceUnit[]; batchDigest: string; encodedBytes: number;
}
export interface EvidenceCompletePayload {
  taskId: string; peerTaskId: string; round: 1 | 2; evidenceCount: number; truncatedByBudget: boolean;
}
export interface TsfDataPayload {
  taskId: string; peerTaskId: string; round: 1 | 2; feedback: TaskSufficiencyFeedback;
}
export interface EvidencePagePayload {
  taskId: string; peerTaskId: string; round: 1 | 2;
  pageIndex: number; pageCount: number; evidence: EvidenceUnit[];
  pageDigest: string; encodedBytes: number;
}
export interface EvidenceAckPayload {
  taskId: string; peerTaskId: string; pageIndex: number; status: 'OK' | 'ERROR';
}
export interface CancelDataPayload { taskId: string; peerTaskId: string; code: string; reason: string; }
export interface ErrorDataPayload { taskId: string; peerTaskId: string; code: string; message: string; }
export type DataPayload = TaskDataPayload | TaskAckDataPayload | EvidenceBatchPayload |
  EvidencePagePayload | EvidenceAckPayload | EvidenceCompletePayload |
  TsfDataPayload | CancelDataPayload | ErrorDataPayload;
export interface DataEnvelope {
  version: '2.0'; type: DataMessageType; messageId: string; sentAtMs: number;
  peer: PeerContext; payload: DataPayload;
}
