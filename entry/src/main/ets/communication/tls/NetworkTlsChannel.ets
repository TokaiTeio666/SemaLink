import { DataEndpointOffer } from '../control/ControlModels';
import { TlsMaterial, TlsMaterialProvider } from './TlsMaterialProvider';
import { TlsFrameCodec } from './TlsFrameCodec';

export interface TlsSocketLike {
  connect(host: string, port: number, material: TlsMaterial): Promise<void>;
  send(data: ArrayBuffer): Promise<void>;
  close(): Promise<void>;
  peerCertificateFingerprint(): Promise<string>;
  onMessage(callback: (data: Uint8Array) => void): void;
}

export interface TlsSocketFactory {
  create(): TlsSocketLike;
}

export interface TlsChannelDependencies {
  factory: TlsSocketFactory;
  materials: TlsMaterialProvider;
  now: () => number;
}

export class NetworkTlsChannel {
  private readonly dependencies: TlsChannelDependencies | undefined;
  private readonly clock: () => number;
  private socket: TlsSocketLike | undefined;
  private ready: boolean = false;
  private readonly frameCodec = new TlsFrameCodec();
  private messageHandler: ((text: string) => void) | undefined;

  constructor(dependencies?: TlsChannelDependencies, clock?: () => number) {
    this.dependencies = dependencies;
    this.clock = clock ?? dependencies?.now ?? ((): number => Date.now());
  }

  async connect(deviceId: string, offer: DataEndpointOffer): Promise<void> {
    if (deviceId.length === 0) throw new Error('E_TLS_DEVICE_INVALID');
    if (offer.host.length === 0 || offer.port < 1 || offer.port > 65535) throw new Error('E_TLS_ENDPOINT_INVALID');
    if (offer.expiresAtMs <= this.clock()) throw new Error('E_TLS_ENDPOINT_EXPIRED');
    if (this.dependencies === undefined) throw new Error('E_TLS_FACTORY_UNAVAILABLE');
    const socket: TlsSocketLike = this.dependencies.factory.create();
    try {
      await socket.connect(offer.host, offer.port, this.dependencies.materials.getClientMaterial());
      socket.onMessage((data: Uint8Array): void => {
        try {
          for (const text of this.frameCodec.push(data)) this.messageHandler?.(text);
        } catch (_) {
          this.messageHandler = undefined;
        }
      });
      const fingerprint: string = await socket.peerCertificateFingerprint();
      if (fingerprint !== offer.certificateFingerprint) {
        await socket.close();
        throw new Error('E_TLS_FINGERPRINT_MISMATCH');
      }
      this.socket = socket;
      this.ready = true;
    } catch (error) {
      this.ready = false;
      this.socket = undefined;
      throw error as Error;
    }
  }

  async send(data: ArrayBuffer): Promise<void> {
    if (!this.ready || this.socket === undefined) throw new Error('E_TLS_NOT_READY');
    await this.socket.send(data);
  }

  async sendText(text: string): Promise<void> {
    const frame = this.frameCodec.encode(text);
    await this.send(frame.buffer as ArrayBuffer);
  }

  onMessage(handler: (text: string) => void): void { this.messageHandler = handler; }

  async close(): Promise<void> {
    const socket: TlsSocketLike | undefined = this.socket;
    this.socket = undefined;
    this.ready = false;
    if (socket !== undefined) await socket.close();
  }

  isReady(): boolean { return this.ready; }
}
