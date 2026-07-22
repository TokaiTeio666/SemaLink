import { AppError } from '../common/AppError';
import { DisplayKnowledgeItem, KnowledgeQueryDisplayStatus } from '../application/KnowledgeQueryDisplayState';
import { KnowledgeIndexState, KnowledgePayloadLevel } from '../contracts/knowledge/KnowledgeModels';
import { CollaborationRecord } from '../collaboration/CollaborationModels';
import { TaskPhase, TaskSufficiencyFeedback } from '../contracts/semantic/SemanticModels';
import { AutomaticQueryProgress } from '../application/AutomaticQueryPolicy';

export type ControlChannelState = 'DISCONNECTED' | 'CONNECTING' | 'READY' | 'FAILED';
export type DataChannelState = 'DISCONNECTED' | 'CONNECTING' | 'BINDING' | 'READY' | 'FAILED';
export type PeerTaskStatus = 'PENDING' | 'ACKED' | 'RECEIVING' | 'COMPLETE' | 'FAILED' | 'CANCELLED';

export enum DeviceRole {
  UNSELECTED = 'UNSELECTED',
  INITIATOR = 'INITIATOR',
  RESPONDER = 'RESPONDER'
}

export enum ConnectionState {
  IDLE = 'IDLE',
  SELECTING_DEVICE = 'SELECTING_DEVICE',
  CONNECTING = 'CONNECTING',
  CONNECTED = 'CONNECTED',
  WAITING_ACK = 'WAITING_ACK',
  WAITING_RESULT = 'WAITING_RESULT',
  DISCONNECTING = 'DISCONNECTING',
  DISCONNECTED = 'DISCONNECTED',
  ERROR = 'ERROR'
}

export interface PeerDevice {
  deviceId: string;
  deviceName: string;
  deviceType: string;
}

export interface PeerStatusSnapshot {
  deviceIdMasked: string;
  deviceName: string;
  controlState: ControlChannelState;
  dataState: DataChannelState;
  taskState: PeerTaskStatus | '';
  allocatedBytes: number;
  evidenceCount: number;
  failureCode: string;
}

export interface AppSnapshot {
  automaticQueryProgress: AutomaticQueryProgress;
  automaticSourceNames: string[];
  automaticExcludedSourceNames: string[];
  peerStatuses: PeerStatusSnapshot[];
  activePeerCount: number;
  evidenceSourceDeviceIds: string[];
  evidenceConflictCount: number;
  finalSufficiency: 'ENOUGH' | 'NEED_MORE' | 'ABORT' | '';
  totalTaskMs: number;
  enteredL2: boolean;
  role: DeviceRole;
  connectionState: ConnectionState;
  question: string;
  summary: string;
  requestId: string;
  roundTripMs: number;
  bytesSent: number;
  bytesReceived: number;
  peerDeviceName: string;
  peerDeviceIdMasked: string;
  knowledgeInitialized: boolean;
  knowledgeBusy: boolean;
  knowledgeIndexState: KnowledgeIndexState;
  knowledgeDocumentCount: number;
  knowledgeChunkCount: number;
  knowledgeMessage: string;
  knowledgeQueryStatus: KnowledgeQueryDisplayStatus;
  knowledgeLevel: KnowledgePayloadLevel;
  knowledgeItems: DisplayKnowledgeItem[];
  knowledgeRetrievalMs: number;
  knowledgeTruncated: boolean;
  knowledgeError: string;
  collaborationRecords: Array<CollaborationRecord>;
  selectedCollaborationRecordId: string;
  taskId: string;
  taskPhase: TaskPhase;
  taskRound: number;
  taskFeedback: TaskSufficiencyFeedback | '';
  taskCoverage: number;
  taskConfidence: number;
  taskMissingConcepts: string[];
  selectedDeviceId: string;
  evidenceBytes: number;
  taskPrivacyLevel: 'LOCAL_ONLY' | 'PRIVATE_GROUP' | '';
  routeScore: number;
  routeSemanticMatch: number;
  routeFilterMatch: number;
  routeFreshness: number;
  routeNormalizedRtt: number;
  routeLoad: number;
  routePrivacyRisk: number;
  firstResultLatencyMs: number;
  completionLatencyMs: number;
  latencySamplesMs: number[];
  protocolBytes: number;
  error?: AppError;
}

export const INITIAL_SNAPSHOT: AppSnapshot = {
  automaticQueryProgress: 'IDLE',
  automaticSourceNames: [],
  automaticExcludedSourceNames: [],
  peerStatuses: [],
  activePeerCount: 0,
  evidenceSourceDeviceIds: [],
  evidenceConflictCount: 0,
  finalSufficiency: '',
  totalTaskMs: 0,
  enteredL2: false,
  role: DeviceRole.UNSELECTED,
  connectionState: ConnectionState.IDLE,
  question: '',
  summary: '',
  requestId: '',
  roundTripMs: 0,
  bytesSent: 0,
  bytesReceived: 0,
  peerDeviceName: '',
  peerDeviceIdMasked: '',
  knowledgeInitialized: false,
  knowledgeBusy: false,
  knowledgeIndexState: 'EMPTY',
  knowledgeDocumentCount: 0,
  knowledgeChunkCount: 0,
  knowledgeMessage: '正在初始化知识库',
  knowledgeQueryStatus: 'IDLE',
  knowledgeLevel: 'L2',
  knowledgeItems: [],
  knowledgeRetrievalMs: 0,
  knowledgeTruncated: false,
  knowledgeError: '',
  collaborationRecords: [],
  selectedCollaborationRecordId: '',
  taskId: '',
  taskPhase: 'PENDING',
  taskRound: 0,
  taskFeedback: '',
  taskCoverage: 0,
  taskConfidence: 0,
  taskMissingConcepts: [],
  selectedDeviceId: '',
  evidenceBytes: 0,
  taskPrivacyLevel: '',
  routeScore: 0,
  routeSemanticMatch: 0,
  routeFilterMatch: 0,
  routeFreshness: 0,
  routeNormalizedRtt: 0,
  routeLoad: 0,
  routePrivacyRisk: 0,
  firstResultLatencyMs: 0,
  completionLatencyMs: 0,
  latencySamplesMs: [],
  protocolBytes: 0
};

export function cloneSnapshot(
  base: AppSnapshot,
  role?: DeviceRole,
  connectionState?: ConnectionState,
  error?: AppError
): AppSnapshot {
  return {
    automaticQueryProgress: base.automaticQueryProgress,
    automaticSourceNames: base.automaticSourceNames,
    automaticExcludedSourceNames: base.automaticExcludedSourceNames,
    peerStatuses: base.peerStatuses,
    activePeerCount: base.activePeerCount,
    evidenceSourceDeviceIds: base.evidenceSourceDeviceIds,
    evidenceConflictCount: base.evidenceConflictCount,
    finalSufficiency: base.finalSufficiency,
    totalTaskMs: base.totalTaskMs,
    enteredL2: base.enteredL2,
    role: role ?? base.role,
    connectionState: connectionState ?? base.connectionState,
    question: base.question,
    summary: base.summary,
    requestId: base.requestId,
    roundTripMs: base.roundTripMs,
    bytesSent: base.bytesSent,
    bytesReceived: base.bytesReceived,
    peerDeviceName: base.peerDeviceName,
    peerDeviceIdMasked: base.peerDeviceIdMasked,
    knowledgeInitialized: base.knowledgeInitialized,
    knowledgeBusy: base.knowledgeBusy,
    knowledgeIndexState: base.knowledgeIndexState,
    knowledgeDocumentCount: base.knowledgeDocumentCount,
    knowledgeChunkCount: base.knowledgeChunkCount,
    knowledgeMessage: base.knowledgeMessage,
    knowledgeQueryStatus: base.knowledgeQueryStatus,
    knowledgeLevel: base.knowledgeLevel,
    knowledgeItems: base.knowledgeItems,
    knowledgeRetrievalMs: base.knowledgeRetrievalMs,
    knowledgeTruncated: base.knowledgeTruncated,
    knowledgeError: base.knowledgeError,
    collaborationRecords: base.collaborationRecords,
    selectedCollaborationRecordId: base.selectedCollaborationRecordId,
    taskId: base.taskId,
    taskPhase: base.taskPhase,
    taskRound: base.taskRound,
    taskFeedback: base.taskFeedback,
    taskCoverage: base.taskCoverage,
    taskConfidence: base.taskConfidence,
    taskMissingConcepts: base.taskMissingConcepts,
    selectedDeviceId: base.selectedDeviceId,
    evidenceBytes: base.evidenceBytes,
    taskPrivacyLevel: base.taskPrivacyLevel,
    routeScore: base.routeScore,
    routeSemanticMatch: base.routeSemanticMatch,
    routeFilterMatch: base.routeFilterMatch,
    routeFreshness: base.routeFreshness,
    routeNormalizedRtt: base.routeNormalizedRtt,
    routeLoad: base.routeLoad,
    routePrivacyRisk: base.routePrivacyRisk,
    firstResultLatencyMs: base.firstResultLatencyMs,
    completionLatencyMs: base.completionLatencyMs,
    latencySamplesMs: base.latencySamplesMs,
    protocolBytes: base.protocolBytes,
    error: error ?? base.error
  };
}

export function maskDeviceId(deviceId: string): string {
  if (deviceId.length === 0) {
    return '';
  }
  if (deviceId.length <= 6) {
    return '***' + deviceId;
  }
  return '***' + deviceId.substring(deviceId.length - 6);
}
