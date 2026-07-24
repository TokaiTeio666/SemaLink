const MAX_HANDSHAKE_BYTES: number = 16 * 1024;

function utf8Bytes(value: string): number {
  let bytes: number = 0;
  for (let index = 0; index < value.length; index += 1) {
    const code: number = value.charCodeAt(index);
    if (code <= 0x7F) {
      bytes += 1;
    } else if (code <= 0x7FF) {
      bytes += 2;
    } else if (code >= 0xD800 && code <= 0xDBFF && index + 1 < value.length) {
      const next: number = value.charCodeAt(index + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        bytes += 4;
        index += 1;
      } else {
        bytes += 3;
      }
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

export class AgentAuthorizationCoordinator {
  authorize(handshakeData: string, authorizeCall: (data: string) => void): boolean {
    if (handshakeData.length === 0 || utf8Bytes(handshakeData) > MAX_HANDSHAKE_BYTES) {
      return false;
    }
    try {
      authorizeCall(handshakeData);
      return true;
    } catch (_error) {
      return false;
    }
  }
}
