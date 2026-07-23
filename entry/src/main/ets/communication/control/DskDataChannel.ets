const MAX_FRAME_BYTES: number = 900;
const MAX_FRAME_COUNT: number = 64;
const MAX_REASSEMBLED_TEXT_BYTES: number = 256 * 1024;
const FRAME_ASSEMBLY_TTL_MS: number = 10000;

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
  private readonly handlers = new Map<string, Set<(text: string) => void>>();
  private readonly pending = new Map<string, Map<string, DskDataFrame[]>>();
  private readonly pendingAt = new Map<string, Map<string, number>>();

  constructor(hub: DskDataTransport) {
    this.hub = hub;
    this.hub.onDataMessage((deviceId: string, frame: Object): void => this.receive(deviceId, frame));
  }

  onMessage(deviceId: string, handler: (text: string) => void): void {
    const listeners = new Set<(text: string) => void>();
    listeners.add(handler);
    this.handlers.set(deviceId, listeners);
  }

  addMessageListener(deviceId: string, handler: (text: string) => void): void {
    let listeners = this.handlers.get(deviceId);
    if (listeners === undefined) {
      listeners = new Set<(text: string) => void>();
      this.handlers.set(deviceId, listeners);
    }
    listeners.add(handler);
  }

  removeMessageListener(deviceId: string, handler: (text: string) => void): void {
    const listeners = this.handlers.get(deviceId);
    if (listeners === undefined) return;
    listeners.delete(handler);
    if (listeners.size === 0) this.handlers.delete(deviceId);
  }

  pendingFrameCount(deviceId?: string): number {
    if (deviceId !== undefined) return this.pending.get(deviceId)?.size ?? 0;
    let count = 0;
    for (const frames of this.pending.values()) count += frames.size;
    return count;
  }

  clearDevice(deviceId: string): void {
    this.handlers.delete(deviceId);
    this.pending.delete(deviceId);
    this.pendingAt.delete(deviceId);
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
    this.pruneExpired(deviceId);
    if (!isFrame(frameObject)) return;
    const incoming = frameObject as DskDataFrame;
    if (incoming.total > MAX_FRAME_COUNT || incoming.textLength > MAX_REASSEMBLED_TEXT_BYTES) return;
    let byFrame = this.pending.get(deviceId);
    let created = this.pendingAt.get(deviceId);
    if (byFrame === undefined) { byFrame = new Map<string, DskDataFrame[]>(); this.pending.set(deviceId, byFrame); }
    if (created === undefined) { created = new Map<string, number>(); this.pendingAt.set(deviceId, created); }
    const frame = incoming;
    let frames = byFrame.get(frame.frameId);
    if (frames === undefined) { frames = []; byFrame.set(frame.frameId, frames); created.set(frame.frameId, Date.now()); }
    if (frames.length > 0 && frames[0].total !== frame.total) { byFrame.delete(frame.frameId); created.delete(frame.frameId); return; }
    if (frames.some((item: DskDataFrame): boolean => item.index === frame.index)) return;
    frames.push(frame);
    if (frames.length !== frame.total) return;
    frames.sort((left: DskDataFrame, right: DskDataFrame): number => left.index - right.index);
    const text = frames.map((item: DskDataFrame): string => item.payload).join('');
    byFrame.delete(frame.frameId);
    created.delete(frame.frameId);
    if (text.length !== frame.textLength) return;
    for (const handler of this.handlers.get(deviceId) ?? new Set<(text: string) => void>()) handler(text);
  }

  private pruneExpired(deviceId: string): void {
    const byFrame = this.pending.get(deviceId);
    const created = this.pendingAt.get(deviceId);
    if (byFrame === undefined || created === undefined) return;
    const now = Date.now();
    for (const frameId of created.keys()) {
      if (now - (created.get(frameId) ?? now) > FRAME_ASSEMBLY_TTL_MS) {
        created.delete(frameId);
        byFrame.delete(frameId);
      }
    }
  }
}
