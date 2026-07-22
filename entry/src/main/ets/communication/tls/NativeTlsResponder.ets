import socket from '@ohos.net.socket';
import { NetworkAddressProvider } from './NetworkEndpointResolver';
import { Sha256ContentDigester } from './ContentDigest';
import { TlsMaterial, TlsMaterialProvider } from './TlsMaterialProvider';
import { ResponderEndpoint } from '../PeerConnectionPool';

export interface TlsResponderAddress {
  address: string;
  port: number;
}

export interface TlsResponderSecureOptions {
  ca?: string | Array<string>;
  cert?: string | Array<string>;
  key?: string;
}

export interface TlsResponderListenOptions {
  address: TlsResponderAddress;
  secureOptions: TlsResponderSecureOptions;
}

export interface TlsResponderConnection {
  send(data: string | ArrayBuffer): Promise<void>;
  close(): Promise<void>;
  onMessage(callback: (data: Uint8Array) => void): void;
}

export interface TlsResponderServer {
  listen(options: TlsResponderListenOptions): Promise<void>;
  close(): Promise<void>;
  getLocalAddress(): Promise<TlsResponderAddress>;
  getCertificate(): Promise<Uint8Array>;
  onConnect(callback: (connection: TlsResponderConnection) => void): void;
}

export interface TlsResponderServerFactory {
  create(): TlsResponderServer;
}

export type TlsCertificateDigester = (data: Uint8Array) => Promise<string>;

class NativeTlsResponderConnection implements TlsResponderConnection {
  private readonly connection: socket.TLSSocketConnection;

  constructor(connection: socket.TLSSocketConnection) { this.connection = connection; }
  async send(data: string | ArrayBuffer): Promise<void> { await this.connection.send(data); }
  async close(): Promise<void> { await this.connection.close(); }
  onMessage(callback: (data: Uint8Array) => void): void {
    this.connection.on('message', (event: socket.SocketMessageInfo): void => {
      callback(new Uint8Array(event.message as ArrayBuffer));
    });
  }
}

class NativeTlsResponderServer implements TlsResponderServer {
  private readonly server: socket.TLSSocketServer = socket.constructTLSSocketServerInstance();

  async listen(options: TlsResponderListenOptions): Promise<void> {
    await this.server.listen(options as socket.TLSConnectOptions);
  }
  async close(): Promise<void> { await this.server.close(); }
  async getLocalAddress(): Promise<TlsResponderAddress> {
    const address: socket.NetAddress = await this.server.getLocalAddress();
    const port: number | undefined = address.port;
    if (port === undefined) throw new Error('E_TLS_RESPONDER_ADDRESS_UNAVAILABLE');
    return { address: address.address, port: port };
  }
  async getCertificate(): Promise<Uint8Array> {
    const certificate: socket.X509CertRawData = await this.server.getCertificate();
    return new Uint8Array(certificate.data);
  }
  onConnect(callback: (connection: TlsResponderConnection) => void): void {
    this.server.on('connect', (connection: socket.TLSSocketConnection): void => {
      callback(new NativeTlsResponderConnection(connection));
    });
  }
}

class NativeTlsResponderServerFactory implements TlsResponderServerFactory {
  create(): TlsResponderServer { return new NativeTlsResponderServer(); }
}

export class NativeTlsResponder {
  private readonly materials: TlsMaterialProvider;
  private readonly addresses: NetworkAddressProvider;
  private readonly factory: TlsResponderServerFactory;
  private readonly digest: TlsCertificateDigester;
  private server: TlsResponderServer | undefined;
  private connectionHandler: ((connection: TlsResponderConnection) => void) | undefined;

  constructor(
    materials: TlsMaterialProvider,
    addresses: NetworkAddressProvider,
    factory?: TlsResponderServerFactory,
    digest?: TlsCertificateDigester
  ) {
    this.materials = materials;
    this.addresses = addresses;
    this.factory = factory ?? new NativeTlsResponderServerFactory();
    this.digest = digest ?? (async (data: Uint8Array): Promise<string> => new Sha256ContentDigester().digestBytes(data));
  }

  async start(): Promise<ResponderEndpoint> {
    if (this.server !== undefined) throw new Error('E_TLS_RESPONDER_ALREADY_STARTED');
    const server: TlsResponderServer = this.factory.create();
    const material: TlsMaterial = this.materials.getServerMaterial();
    await server.listen({
      address: { address: '0.0.0.0', port: 0 },
      secureOptions: { cert: material.cert, key: material.key }
    });
    server.onConnect((connection: TlsResponderConnection): void => this.connectionHandler?.(connection));
    this.server = server;
    const local: TlsResponderAddress = await server.getLocalAddress();
    const certificate: Uint8Array = await server.getCertificate();
    return {
      host: await this.addresses.localIpv4(),
      port: local.port,
      certificateFingerprint: await this.digest(certificate)
    };
  }

  onConnection(handler: (connection: TlsResponderConnection) => void): void {
    this.connectionHandler = handler;
  }

  async close(): Promise<void> {
    const server: TlsResponderServer | undefined = this.server;
    this.server = undefined;
    this.connectionHandler = undefined;
    if (server !== undefined) await server.close();
  }
}
