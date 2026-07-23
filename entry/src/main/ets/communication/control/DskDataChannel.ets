const MAX_FRAME_BYTES: number = 900;
const MAX_MESSAGE_CHARS: number = 64 * 1024;
const MAX_TOTAL_FRAMES: number = 128;
const MAX_PENDING_PER_DEVICE: number = 8;
const MAX_PENDING_DEVICES: number = 16;
const PENDING_TTL_MS: number = 10 * 1000;

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
    frame.frameId.length > 0 && frame.frameId.length <= 128 &&
    Number.isInteger(frame.index) && Number.isInteger(frame.total) &&
    frame.index >= 0 && frame.total > 0 && frame.total <= MAX_TOTAL_FRAMES &&
    frame.index < frame.total && Number.isInteger(frame.textLength) &&
    frame.textLength >= 0 && frame.textLength <= MAX_MESSAGE_CHARS &&
    typeof frame.payload === 'string' && frame.payload.length <= MAX_FRAME_BYTES &&
    utf8Bytes(frame.payload) <= MAX_FRAME_BYTES;
}

class PendingFrameSet {
  readonly frames: DskDataFrame[] = [];
  readonly total: number;
  readonly textLength: number;
  readonly createdAtMs: number;
  constructor(frame: DskDataFrame, createdAtMs: number) {
    this.total = frame.total;
    this.textLength = frame.textLength;
    this.createdAtMs = createdAtMs;
  }
}

export class DskDataChannel {
  private readonly hub: DskDataTransport;
  private readonly handlers = new Map<string, DskDataHandler>();
  private readonly pending = new Map<string, Map<string, PendingFrameSet>>();
  private readonly completedBeforeHandler = new Map<string, string[]>();

  constructor(hub: DskDataTransport) {
    this.hub = hub;
    this.hub.onDataMessage((deviceId: string, frame: Object): void => this.receive(deviceId, frame));
  }

  onMessage(deviceId: string, handler: (text: string) => void): void {
    this.handlers.set(deviceId, (_id: string, text: string): void => handler(text));
    const pending: string[] | undefined = this.completedBeforeHandler.get(deviceId);
    if (pending !== undefined) {
      this.completedBeforeHandler.delete(deviceId);
      pending.forEach((text: string): void => handler(text));
    }
  }

  async send(deviceId: string, text: string): Promise<void> {
    if (text.length > MAX_MESSAGE_CHARS) {
      throw new Error('DSK_DATA_MESSAGE_TOO_LARGE');
    }
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
    if (chunks.length > MAX_TOTAL_FRAMES) {
      throw new Error('DSK_DATA_MESSAGE_TOO_LARGE');
    }
    for (let index = 0; index < chunks.length; index++) {
      const frame: DskDataFrame = { channel: 'DATA', version: '1.0', frameId: frameId, index: index,
        total: chunks.length, textLength: text.length, payload: chunks[index] };
      await this.hub.sendData(deviceId, frame);
    }
  }

  private receive(deviceId: string, frameObject: Object): void {
    if (!isFrame(frameObject)) return;
    const nowMs: number = Date.now();
    this.removeExpired(nowMs);
    let byFrame = this.pending.get(deviceId);
    if (byFrame === undefined) {
      if (this.pending.size >= MAX_PENDING_DEVICES) return;
      byFrame = new Map<string, PendingFrameSet>();
      this.pending.set(deviceId, byFrame);
    }
    const frame = frameObject as DskDataFrame;
    let pendingSet = byFrame.get(frame.frameId);
    if (pendingSet === undefined) {
      if (byFrame.size >= MAX_PENDING_PER_DEVICE) return;
      pendingSet = new PendingFrameSet(frame, nowMs);
      byFrame.set(frame.frameId, pendingSet);
    }
    if (pendingSet.total !== frame.total ||
      pendingSet.textLength !== frame.textLength) return;
    if (pendingSet.frames.some(
      (item: DskDataFrame): boolean => item.index === frame.index)) return;
    pendingSet.frames.push(frame);
    if (pendingSet.frames.length !== frame.total) return;
    pendingSet.frames.sort(
      (left: DskDataFrame, right: DskDataFrame): number => left.index - right.index);
    const text = pendingSet.frames.map(
      (item: DskDataFrame): string => item.payload).join('');
    byFrame.delete(frame.frameId);
    if (byFrame.size === 0) this.pending.delete(deviceId);
    if (text.length !== frame.textLength) return;
    const handler: DskDataHandler | undefined = this.handlers.get(deviceId);
    if (handler !== undefined) {
      handler(deviceId, text);
    } else {
      let completed: string[] | undefined = this.completedBeforeHandler.get(deviceId);
      if (completed === undefined) {
        if (this.completedBeforeHandler.size >= MAX_PENDING_DEVICES) {
          return;
        }
        completed = [];
        this.completedBeforeHandler.set(deviceId, completed);
      }
      if (completed.length < MAX_PENDING_PER_DEVICE) {
        completed.push(text);
      }
    }
  }

  private removeExpired(nowMs: number): void {
    this.pending.forEach(
      (byFrame: Map<string, PendingFrameSet>, deviceId: string): void => {
        byFrame.forEach((pendingSet: PendingFrameSet, frameId: string): void => {
          if (nowMs - pendingSet.createdAtMs > PENDING_TTL_MS) {
            byFrame.delete(frameId);
          }
        });
        if (byFrame.size === 0) {
          this.pending.delete(deviceId);
        }
      });
  }
}
