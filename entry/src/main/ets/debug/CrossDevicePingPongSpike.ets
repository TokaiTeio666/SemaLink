export const CROSS_DEVICE_SPIKE_PROTOCOL_VERSION: number = 1;

export type CrossDeviceSpikeMessageType = 'PING' | 'PONG';

export class CrossDeviceSpikeMessage {
  protocolVersion: number;
  requestId: string;
  messageType: CrossDeviceSpikeMessageType;

  constructor(requestId: string, messageType: CrossDeviceSpikeMessageType) {
    this.protocolVersion = CROSS_DEVICE_SPIKE_PROTOCOL_VERSION;
    this.requestId = requestId;
    this.messageType = messageType;
  }
}

export class CrossDevicePingPongSpikeCodec {
  createPing(requestId: string): CrossDeviceSpikeMessage {
    return this.create(requestId, 'PING');
  }

  createPong(requestId: string): CrossDeviceSpikeMessage {
    return this.create(requestId, 'PONG');
  }

  encode(message: CrossDeviceSpikeMessage): string {
    return JSON.stringify(message);
  }

  decode(text: string): CrossDeviceSpikeMessage {
    const parsed: Object = JSON.parse(text) as Object;
    if (parsed === null || typeof parsed !== 'object') {
      throw new Error('invalid spike payload');
    }
    const value: Record<string, Object> = parsed as Record<string, Object>;
    if (value['protocolVersion'] !== CROSS_DEVICE_SPIKE_PROTOCOL_VERSION) {
      throw new Error('unsupported spike protocol version');
    }
    const requestId: Object | undefined = value['requestId'];
    if (typeof requestId !== 'string' || requestId.length === 0 || requestId.length > 128) {
      throw new Error('invalid spike requestId');
    }
    const messageType: Object | undefined = value['messageType'];
    if (messageType !== 'PING' && messageType !== 'PONG') {
      throw new Error('unknown spike message type');
    }
    return new CrossDeviceSpikeMessage(
      requestId as string,
      messageType as CrossDeviceSpikeMessageType
    );
  }

  private create(requestId: string, messageType: CrossDeviceSpikeMessageType): CrossDeviceSpikeMessage {
    if (requestId.length === 0 || requestId.length > 128) {
      throw new Error('invalid spike requestId');
    }
    return new CrossDeviceSpikeMessage(requestId, messageType);
  }
}
