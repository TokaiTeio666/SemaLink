import { describe, expect, it } from '@ohos/hypium';
import { TlsFrameCodec } from '../main/ets/communication/tls/TlsFrameCodec';

export default function tlsFrameCodecTest(): void {
  describe('TlsFrameCodec', () => {
    it('reassembles split and coalesced frames', 0, () => {
      const codec = new TlsFrameCodec();
      const first = codec.encode('first');
      const second = codec.encode('second');
      expect(codec.push(first.slice(0, 3)).length).assertEqual(0);
      const combined = new Uint8Array(first.length - 3 + second.length);
      combined.set(first.slice(3), 0); combined.set(second, first.length - 3);
      const frames = codec.push(combined);
      expect(frames.length).assertEqual(2);
      expect(frames[0]).assertEqual('first');
      expect(frames[1]).assertEqual('second');
    });
    it('rejects zero and oversized lengths', 0, () => {
      const codec = new TlsFrameCodec();
      let zero = '';
      try { codec.push(new Uint8Array([0, 0, 0, 0])); } catch (e) { zero = (e as Error).message; }
      expect(zero).assertEqual('E_TLS_FRAME_INVALID');
      let big = '';
      try { codec.push(new Uint8Array([0, 1, 0, 0])); } catch (e) { big = (e as Error).message; }
      expect(big).assertEqual('E_TLS_FRAME_INVALID');
    });
    it('rejects partial stream on finish', 0, () => {
      const codec = new TlsFrameCodec(); codec.push(new Uint8Array([0, 0]));
      let code = ''; try { codec.finish(); } catch (e) { code = (e as Error).message; }
      expect(code).assertEqual('E_TLS_FRAME_INVALID');
    });
  });
}
