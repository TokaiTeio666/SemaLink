import { describe, expect, it } from '@ohos/hypium';
import { NativeTlsResponder, TlsResponderAddress, TlsResponderConnection, TlsResponderListenOptions, TlsResponderServer, TlsResponderServerFactory } from '../main/ets/communication/tls/NativeTlsResponder';
import { InMemoryTlsMaterialProvider } from '../main/ets/communication/tls/TlsMaterialProvider';
import { NetworkAddressProvider } from '../main/ets/communication/tls/NetworkEndpointResolver';

class FakeServer implements TlsResponderServer {
  options: TlsResponderListenOptions | undefined;
  async listen(options: TlsResponderListenOptions): Promise<void> { this.options = options; }
  async close(): Promise<void> { }
  async getLocalAddress(): Promise<TlsResponderAddress> {
    return { address: '192.168.1.20', port: 4433 };
  }
  async getCertificate(): Promise<Uint8Array> { return new Uint8Array([1, 2, 3]); }
  onConnect(_callback: (connection: TlsResponderConnection) => void): void { }
}

class FixedServerFactory implements TlsResponderServerFactory {
  readonly server: FakeServer = new FakeServer();
  create(): TlsResponderServer { return this.server; }
}

class FixedAddressProvider implements NetworkAddressProvider {
  async localIpv4(): Promise<string> { return '192.168.1.20'; }
}

export default function nativeTlsResponderTest(): void {
  describe('NativeTlsResponder', () => {
    it('listens with server material and publishes its local endpoint', 0, async () => {
      const factory = new FixedServerFactory();
      const responder = new NativeTlsResponder(
        new InMemoryTlsMaterialProvider({ ca: 'ca', cert: 'cert', key: 'key' }),
        new FixedAddressProvider(), factory,
        async (data: Uint8Array): Promise<string> => `${data.length}-digest`
      );
      const endpoint = await responder.start();
      expect(endpoint.host).assertEqual('192.168.1.20');
      expect(endpoint.port).assertEqual(4433);
      expect(endpoint.certificateFingerprint).assertEqual('3-digest');
      expect(factory.server.options !== undefined).assertTrue();
      await responder.close();
    });
  });
}
