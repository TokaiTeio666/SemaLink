import connection from '@ohos.net.connection';

export interface NetworkAddressProvider {
  localIpv4(): Promise<string>;
}

export class NativeNetworkAddressProvider implements NetworkAddressProvider {
  async localIpv4(): Promise<string> {
    let fallback = '';
    let wlanFallback = '';
    let ethFallback = '';
    const nets = await connection.getAllNets();
    for (const net of nets) {
      const properties = await connection.getConnectionProperties(net);
      for (const link of properties.linkAddresses) {
        const address = link.address.address;
        if (!/^(?:\d{1,3}\.){3}\d{1,3}$/.test(address) || address === '127.0.0.1') continue;
        // CHBA is the native device-to-device path and avoids hotspot client isolation.
        if (properties.interfaceName === 'chba0') return address;
        if (properties.interfaceName === 'wlan0') {
          if (wlanFallback.length === 0) wlanFallback = address;
          continue;
        }
        if (properties.interfaceName.indexOf('eth') === 0) {
          if (ethFallback.length === 0) ethFallback = address;
          continue;
        }
        if (fallback.length === 0) fallback = address;
      }
    }
    if (wlanFallback.length > 0) return wlanFallback;
    if (ethFallback.length > 0) return ethFallback;
    if (fallback.length > 0) return fallback;
    throw new Error('E_LOCAL_IPV4_UNAVAILABLE');
  }
}

export class StaticNetworkAddressProvider implements NetworkAddressProvider {
  private readonly address: string;

  constructor(address: string) { this.address = address; }
  async localIpv4(): Promise<string> { return this.address; }
}
