export const SEMALINK_CROSS_DEVICE_PROTOCOL_VERSION: number = 1;

export type CrossDeviceProtocolMessageType =
  'HELLO' |
  'PING' |
  'PONG' |
  'PROFILE_DIGEST' |
  'PROFILE_REQUEST' |
  'PROFILE_RESPONSE' |
  'QUERY_REQUEST' |
  'QUERY_RESPONSE' |
  'QUERY_ERROR' |
  'QUERY_CANCEL';

export class CrossDeviceEnvelope {
  readonly protocolVersion: number = SEMALINK_CROSS_DEVICE_PROTOCOL_VERSION;
  readonly messageType: CrossDeviceProtocolMessageType;
  readonly messageId: string;
  readonly requestId: string;
  readonly taskId: string;
  readonly senderAppInstanceId: string;
  readonly sentAtMs: number;
  readonly deadlineAtMs: number;
  readonly sequence: number;
  readonly payload: Object;

  constructor(messageType: CrossDeviceProtocolMessageType, messageId: string,
    requestId: string, taskId: string, senderAppInstanceId: string, sentAtMs: number,
    deadlineAtMs: number, sequence: number, payload: Object) {
    this.messageType = messageType;
    this.messageId = messageId;
    this.requestId = requestId;
    this.taskId = taskId;
    this.senderAppInstanceId = senderAppInstanceId;
    this.sentAtMs = sentAtMs;
    this.deadlineAtMs = deadlineAtMs;
    this.sequence = sequence;
    this.payload = payload;
  }
}
