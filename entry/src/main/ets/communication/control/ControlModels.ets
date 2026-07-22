import { DeviceProfileAdvertisement } from '../../contracts/semantic/SemanticModels';

export type ControlMessageType = 'PROFILE' | 'DATA_ENDPOINT_OFFER' | 'TASK_CANCEL' | 'CONTROL_CLOSE';
export interface DataEndpointOffer {
  host: string;
  port: number;
  certificateFingerprint: string;
  bindingToken: string;
  endpointVersion: number;
  expiresAtMs: number;
  dataProtocolVersion: '2.0';
}
export interface DataBindPayload {
  deviceId: string;
  controlSessionId: string;
  endpointVersion: number;
  sessionEpoch: string;
  bindingToken: string;
}
export interface DataBindAckPayload {
  deviceId: string;
  endpointVersion: number;
  sessionEpoch: string;
  acceptedAtMs: number;
}
export interface TaskCancelControl { taskId: string; peerTaskIds: string[]; reason: string; }
export interface ControlClose { reason: string; }
export interface ControlEnvelope {
  version: '1.0'; type: ControlMessageType; messageId: string; deviceId: string; sentAtMs: number;
  payload: DeviceProfileAdvertisement | DataEndpointOffer | TaskCancelControl | ControlClose;
}
export type ControlChannelState = 'DISCONNECTED' | 'CONNECTING' | 'READY' | 'FAILED';
