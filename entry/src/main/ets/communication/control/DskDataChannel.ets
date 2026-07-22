const MAX_FRAME_BYTES: number = 900;

export interface DskDataFrame {
  channel: 'DATA';
  version: '1.0';
  frameId: string;
  index: number;
  total: number;
  textLength: number;
  payload: string;
}

export type DskDataHandler = (deviceId: string, text: string) => void;
export interface DskDataTransport {
  sendData(deviceId: string, frame: Object): Promise<void>;
  onDataMessage(handler: (deviceId: string, frame: Object) => void): void;
}

function utf8Bytes(text: string): number {
  let result = 0;
  for (let i = 0; i < text.length; i++) {
    const code = text.codePointAt(i) ?? 0;
    result += code <= 0x7f ? 1 : (code <= 0x7ff ? 2 : (code <= 0xffff ? 3 : 4));
    if (code > 0xffff) i++;
  }
  return result;
}

function isFrame(value: Object): boolean {
  const frame = value as DskDataFrame;
  return frame.channel === 'DATA' && frame.version === '1.0' && typeof frame.frameId === 'string' &&
    frame.frameId.length > 0 && Number.isInteger(frame.index) && Number.isInteger(frame.total) &&
    frame.index >= 0 && frame.total > 0 && frame.index < frame.total && Number.isInteger(frame.textLength) &&
    frame.textLength >= 0 && typeof frame.payload === 'string';
}

export class DskDataChannel {
  private readonly hub: DskDataTransport;
  private readonly handlers = new Map<string, DskDataHandler>();
  private readonly pending = new Map<string, Map<string, DskDataFrame[]>>();

  constructor(hub: DskDataTransport) {
    this.hub = hub;
    this.hub.onDataMessage((deviceId: string, frame: Object): void => this.receive(deviceId, frame));
  }

  onMessage(deviceId: string, handler: (text: string) => void): void {
    this.handlers.set(deviceId, (_id: string, text: string): void => handler(text));
  }

  async send(deviceId: string, text: string): Promise<void> {
    const frameId = 'dsk-' + Date.now().toString() + '-' + Math.floor(Math.random() * 100000).toString();
    const chunks: string[] = [];
    let current = '';
    for (const character of text) {
      const candidate = current + character;
      if (current.length > 0 && utf8Bytes(JSON.stringify({ channel: 'DATA', version: '1.0', frameId: frameId,
        index: 0, total: 1, textLength: text.length, payload: candidate })) > MAX_FRAME_BYTES) {
        chunks.push(current);
        current = character;
      } else {
        current = candidate;
      }
    }
    if (current.length > 0 || chunks.length === 0) chunks.push(current);
    for (let index = 0; index < chunks.length; index++) {
      const frame: DskDataFrame = { channel: 'DATA', version: '1.0', frameId: frameId, index: index,
        total: chunks.length, textLength: text.length, payload: chunks[index] };
      await this.hub.sendData(deviceId, frame);
    }
  }

  private receive(deviceId: string, frameObject: Object): void {
    if (!isFrame(frameObject)) return;
    let byFrame = this.pending.get(deviceId);
    if (byFrame === undefined) { byFrame = new Map<string, DskDataFrame[]>(); this.pending.set(deviceId, byFrame); }
    const frame = frameObject as DskDataFrame;
    let frames = byFrame.get(frame.frameId);
    if (frames === undefined) { frames = []; byFrame.set(frame.frameId, frames); }
    if (frames.some((item: DskDataFrame): boolean => item.index === frame.index)) return;
    frames.push(frame);
    if (frames.length !== frame.total) return;
    frames.sort((left: DskDataFrame, right: DskDataFrame): number => left.index - right.index);
    const text = frames.map((item: DskDataFrame): string => item.payload).join('');
    byFrame.delete(frame.frameId);
    if (text.length !== frame.textLength) return;
    this.handlers.get(deviceId)?.(deviceId, text);
  }
}
