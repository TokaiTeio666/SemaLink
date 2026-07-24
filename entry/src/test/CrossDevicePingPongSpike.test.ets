import { describe, expect, it } from '@ohos/hypium';
import {
  CROSS_DEVICE_SPIKE_PROTOCOL_VERSION,
  CrossDevicePingPongSpikeCodec,
  CrossDeviceSpikeMessage
} from '../main/ets/debug/CrossDevicePingPongSpike';

export default function crossDevicePingPongSpikeTest(): void {
  describe('CrossDevicePingPongSpike', () => {
    it('encodes the minimal versioned PING payload', 0, () => {
      const codec = new CrossDevicePingPongSpikeCodec();

      const decoded: CrossDeviceSpikeMessage =
        codec.decode(codec.encode(codec.createPing('request-1')));

      expect(decoded.protocolVersion).assertEqual(CROSS_DEVICE_SPIKE_PROTOCOL_VERSION);
      expect(decoded.requestId).assertEqual('request-1');
      expect(decoded.messageType).assertEqual('PING');
    });

    it('creates a PONG for the same request without extra fields', 0, () => {
      const codec = new CrossDevicePingPongSpikeCodec();
      const pong: CrossDeviceSpikeMessage = codec.createPong('request-2');
      const keys: string[] = Object.keys(pong).sort();

      expect(keys.join(',')).assertEqual('messageType,protocolVersion,requestId');
      expect(pong.requestId).assertEqual('request-2');
      expect(pong.messageType).assertEqual('PONG');
    });

    it('rejects unknown versions and message types', 0, () => {
      const codec = new CrossDevicePingPongSpikeCodec();
      let versionRejected: boolean = false;
      let typeRejected: boolean = false;

      try {
        codec.decode('{"protocolVersion":2,"requestId":"request-3","messageType":"PING"}');
      } catch (_) {
        versionRejected = true;
      }
      try {
        codec.decode('{"protocolVersion":1,"requestId":"request-4","messageType":"QUERY"}');
      } catch (_) {
        typeRejected = true;
      }

      expect(versionRejected).assertTrue();
      expect(typeRejected).assertTrue();
    });
  });
}
