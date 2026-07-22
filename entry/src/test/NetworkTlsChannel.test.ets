import { describe, expect, it } from '@ohos/hypium';
import { NetworkTlsChannel } from '../main/ets/communication/tls/NetworkTlsChannel';
import { DataEndpointOffer } from '../main/ets/communication/control/ControlModels';

const OFFER: DataEndpointOffer = {
  host: '192.168.1.10', port: 4433, certificateFingerprint: 'abc', bindingToken: 'token',
  endpointVersion: 1, expiresAtMs: 2000, dataProtocolVersion: '2.0'
};

export default function networkTlsChannelTest(): void {
  describe('NetworkTlsChannel', () => {
    it('rejects an expired endpoint before opening a socket', 0, async () => {
      const channel = new NetworkTlsChannel(undefined, (): number => 2001);
      let code = '';
      try { await channel.connect('remote-b', OFFER); } catch (error) { code = (error as Error).message; }
      expect(code).assertEqual('E_TLS_ENDPOINT_EXPIRED');
      expect(channel.isReady()).assertEqual(false);
    });
  });
}
