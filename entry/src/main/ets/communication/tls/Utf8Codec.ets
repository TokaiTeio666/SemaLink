export function encodeUtf8(text: string): Uint8Array {
  const output: number[] = [];
  for (let index = 0; index < text.length; index += 1) {
    let code = text.charCodeAt(index);
    if (code >= 0xd800 && code <= 0xdbff && index + 1 < text.length) {
      const low = text.charCodeAt(index + 1);
      if (low >= 0xdc00 && low <= 0xdfff) {
        code = 0x10000 + ((code - 0xd800) << 10) + low - 0xdc00;
        index += 1;
      }
    }
    if (code <= 0x7f) {
      output.push(code);
    } else if (code <= 0x7ff) {
      output.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
    } else if (code <= 0xffff) {
      output.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    } else {
      output.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 0x3f),
        0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    }
  }
  return new Uint8Array(output);
}

export function decodeUtf8(bytes: Uint8Array): string {
  let result = '';
  for (let index = 0; index < bytes.length;) {
    const first = bytes[index];
    let code = 0;
    let width = 0;
    if (first <= 0x7f) { code = first; width = 1; }
    else if (first >= 0xc2 && first <= 0xdf) { code = first & 0x1f; width = 2; }
    else if (first >= 0xe0 && first <= 0xef) { code = first & 0x0f; width = 3; }
    else if (first >= 0xf0 && first <= 0xf4) { code = first & 0x07; width = 4; }
    else { throw new Error('E_TLS_FRAME_INVALID'); }
    if (index + width > bytes.length) throw new Error('E_TLS_FRAME_INVALID');
    for (let offset = 1; offset < width; offset += 1) {
      const next = bytes[index + offset];
      if ((next & 0xc0) !== 0x80) throw new Error('E_TLS_FRAME_INVALID');
      code = (code << 6) | (next & 0x3f);
    }
    if ((width === 2 && code < 0x80) || (width === 3 && code < 0x800) ||
      (width === 4 && (code < 0x10000 || code > 0x10ffff)) ||
      (code >= 0xd800 && code <= 0xdfff)) throw new Error('E_TLS_FRAME_INVALID');
    if (code <= 0xffff) {
      result += String.fromCharCode(code);
    } else {
      const adjusted = code - 0x10000;
      result += String.fromCharCode(0xd800 + (adjusted >> 10), 0xdc00 + (adjusted & 0x3ff));
    }
    index += width;
  }
  return result;
}
