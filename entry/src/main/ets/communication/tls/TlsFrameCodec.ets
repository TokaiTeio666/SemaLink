import { AppError, ErrorStage } from '../../common/AppError';
import { decodeUtf8, encodeUtf8 } from './Utf8Codec';

export const MAX_TLS_FRAME_BYTES: number = 64 * 1024;

function frameError(message: string): AppError {
  return new AppError('E_TLS_FRAME_INVALID', message, ErrorStage.PROTOCOL, false);
}

function concat(left: Uint8Array, right: Uint8Array): Uint8Array {
  const result = new Uint8Array(left.length + right.length);
  result.set(left, 0);
  result.set(right, left.length);
  return result;
}

function utf8(text: string): Uint8Array {
  return encodeUtf8(text);
}

export class TlsFrameCodec {
  private pending: Uint8Array = new Uint8Array(0);

  encode(text: string): Uint8Array {
    const bytes = utf8(text);
    if (bytes.length === 0 || bytes.length > MAX_TLS_FRAME_BYTES) {
      throw new Error('E_TLS_FRAME_INVALID');
    }
    const result = new Uint8Array(bytes.length + 4);
    result[0] = (bytes.length >>> 24) & 0xff;
    result[1] = (bytes.length >>> 16) & 0xff;
    result[2] = (bytes.length >>> 8) & 0xff;
    result[3] = bytes.length & 0xff;
    result.set(bytes, 4);
    return result;
  }

  push(chunk: Uint8Array): string[] {
    if (chunk.length > 0) this.pending = concat(this.pending, chunk);
    const frames: string[] = [];
    while (this.pending.length >= 4) {
      const length = this.pending[0] * 0x1000000 + this.pending[1] * 0x10000 + this.pending[2] * 0x100 + this.pending[3];
      if (length === 0 || length > MAX_TLS_FRAME_BYTES) throw new Error('E_TLS_FRAME_INVALID');
      if (this.pending.length < length + 4) break;
      const payload = this.pending.slice(4, length + 4);
      let text: string;
      try {
        text = decodeUtf8(payload);
      } catch (_) {
        throw new Error('E_TLS_FRAME_INVALID');
      }
      if (utf8(text).length !== payload.length) throw new Error('E_TLS_FRAME_INVALID');
      frames.push(text);
      this.pending = this.pending.slice(length + 4);
    }
    return frames;
  }

  finish(): void {
    if (this.pending.length > 0) throw new Error('E_TLS_FRAME_INVALID');
  }
}
