import socket from '@ohos.net.socket';
import { TlsMaterial } from './TlsMaterialProvider';
import { Sha256ContentDigester } from './ContentDigest';
import { TlsSocketFactory, TlsSocketLike } from './NetworkTlsChannel';

class NativeTlsSocket implements TlsSocketLike {
  private readonly tls: socket.TLSSocket;

  constructor() { this.tls = socket.constructTLSSocketInstance(); }

  async connect(host: string, port: number, material: TlsMaterial): Promise<void> {
    await this.tls.connect({
      address: { address: host, port: port },
      secureOptions: { ca: material.ca },
      skipRemoteValidation: true
    });
  }

  async send(data: ArrayBuffer): Promise<void> { await this.tls.send(data); }
  async close(): Promise<void> { await this.tls.close(); }

  async peerCertificateFingerprint(): Promise<string> {
    const certificate: socket.X509CertRawData = await this.tls.getRemoteCertificate();
    return await new Sha256ContentDigester().digestBytes(new Uint8Array(certificate.data));
  }

  onMessage(callback: (data: Uint8Array) => void): void {
    this.tls.on('message', (event: socket.SocketMessageInfo): void => {
      callback(new Uint8Array(event.message as ArrayBuffer));
    });
  }
}

export class NativeNetworkTlsSocketFactory implements TlsSocketFactory {
  create(): TlsSocketLike { return new NativeTlsSocket(); }
}
