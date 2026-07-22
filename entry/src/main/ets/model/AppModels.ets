import { AppError } from '../common/AppError';

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
  error?: AppError;
}

export const INITIAL_SNAPSHOT: AppSnapshot = {
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
  peerDeviceIdMasked: ''
};

export function cloneSnapshot(
  base: AppSnapshot,
  role?: DeviceRole,
  connectionState?: ConnectionState,
  error?: AppError
): AppSnapshot {
  return {
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
