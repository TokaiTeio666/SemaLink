import { DskDataChannel, DskDataTransport } from './control/DskDataChannel';
import { DataBindAckPayload, DataBindPayload } from './control/ControlModels';
import { PeerDevice } from '../model/AppModels';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { Logger } from '../common/Logger';

export type PeerConnectionState = 'DISCONNECTED' | 'CONNECTING' | 'BINDING' | 'READY' | 'FAILED';

interface PeerConnection {
  peer: PeerDevice;
  state: PeerConnectionState;
  endpointVersion: number;
  bindingToken: string;
  sessionEpoch: string;
  expiresAtMs: number;
  bindWaiter: ((accepted: boolean) => void) | undefined;
}

export interface BindingTokenGenerator { generate(): Promise<string>; }
export interface ResponderEndpoint { host: string; port: number; certificateFingerprint: string; }

class NativeBindingTokenGenerator implements BindingTokenGenerator {
  async generate(): Promise<string> {
    const random = cryptoFramework.createRandom();
    const data = await random.generateRandom(16);
    const bytes = new Uint8Array(data.data as ArrayBuffer);
    let token = '';
    for (let index = 0; index < bytes.length; index += 1) token += bytes[index].toString(16).padStart(2, '0');
    if (token.length !== 32) throw new Error('E_BIND_TOKEN_GENERATION');
    return token;
  }
}

interface DataFrameMessage { type: string; payload: Object; }

export class PeerConnectionPool {
  private readonly connections = new Map<string, PeerConnection>();
  private readonly usedTokens = new Set<string>();
  private readonly dataChannel: DskDataChannel;
  private readonly dataHandlers = new Map<string, (text: string) => void>();
  private readonly clock: () => number;
  private readonly tokenGenerator: BindingTokenGenerator;
  private readonly logger = new Logger();

  constructor(hub: DskDataTransport, clock?: () => number, tokenGenerator?: BindingTokenGenerator) {
    this.dataChannel = new DskDataChannel(hub);
    this.clock = clock ?? ((): number => Date.now());
    this.tokenGenerator = tokenGenerator ?? new NativeBindingTokenGenerator();
  }

  async refreshPeers(peers: PeerDevice[]): Promise<void> {
    const keep = new Set<string>();
    for (const peer of peers) {
      keep.add(peer.deviceId);
      if (!this.connections.has(peer.deviceId)) {
        this.dataChannel.onMessage(peer.deviceId, (text: string): void => this.handleDataMessage(peer.deviceId, text));
        this.connections.set(peer.deviceId, { peer: peer, state: 'DISCONNECTED', endpointVersion: 0,
          bindingToken: '', sessionEpoch: '', expiresAtMs: 0, bindWaiter: undefined });
      }
    }
    const existing: string[] = [];
    for (const deviceId of this.connections.keys()) existing.push(deviceId);
    for (const deviceId of existing) if (!keep.has(deviceId)) await this.close(deviceId);
  }

  async beginBinding(deviceId: string): Promise<boolean> {
    const connection = this.require(deviceId);
    if (connection.state !== 'DISCONNECTED' && connection.state !== 'FAILED') return connection.state === 'READY';
    connection.state = 'BINDING';
    connection.endpointVersion += 1;
    connection.bindingToken = await this.tokenGenerator.generate();
    connection.sessionEpoch = connection.bindingToken;
    connection.expiresAtMs = this.clock() + 30000;
    const bind: DataBindPayload = { deviceId: deviceId, controlSessionId: deviceId,
      endpointVersion: connection.endpointVersion, sessionEpoch: connection.sessionEpoch, bindingToken: connection.bindingToken };
    const result = new Promise<boolean>((resolve) => {
      connection.bindWaiter = resolve;
      setTimeout((): void => {
        if (connection.bindWaiter !== undefined) {
          connection.bindWaiter = undefined;
          connection.state = 'FAILED';
          resolve(false);
        }
      }, Math.max(1, connection.expiresAtMs - this.clock()));
    });
    try {
      await this.dataChannel.send(deviceId, JSON.stringify({ type: 'DATA_BIND', payload: bind }));
    } catch (error) {
      connection.bindWaiter = undefined;
      connection.state = 'FAILED';
      const message = error instanceof Error ? error.message : 'DSK data bind send failed';
      throw new Error(message);
    }
    return await result;
  }

  async acceptBinding(payload: DataBindPayload, transportDeviceId?: string): Promise<boolean> {
    // The payload identifies the initiator's target, while the transport session
    // identifies the peer visible to the responder. Use the session key at the
    // receiving side and retain payload.deviceId in the ACK for the initiator.
    const connection = this.connections.get(transportDeviceId ?? payload.deviceId);
    if (connection === undefined) return false;
    if (connection.state !== 'DISCONNECTED' && connection.state !== 'BINDING') return false;
    if (connection.state === 'BINDING' && (connection.endpointVersion !== payload.endpointVersion ||
      connection.bindingToken !== payload.bindingToken || connection.sessionEpoch !== payload.sessionEpoch ||
      connection.expiresAtMs <= this.clock())) {
      connection.state = 'FAILED';
      return false;
    }
    if (this.usedTokens.has(payload.bindingToken)) return false;
    this.usedTokens.add(payload.bindingToken);
    connection.endpointVersion = payload.endpointVersion;
    connection.bindingToken = '';
    connection.sessionEpoch = payload.sessionEpoch;
    connection.state = 'READY';
    return true;
  }

  onDataMessage(deviceId: string, handler: (text: string) => void): void { this.dataHandlers.set(deviceId, handler); }

  async send(deviceId: string, encodedEnvelope: string): Promise<void> {
    const connection = this.require(deviceId);
    if (connection.state !== 'READY') throw new Error('E_PEER_NOT_READY');
    await this.dataChannel.send(deviceId, encodedEnvelope);
  }

  readyDeviceIds(): string[] {
    const result: string[] = [];
    for (const deviceId of this.connections.keys()) if (this.connections.get(deviceId)!.state === 'READY') result.push(deviceId);
    result.sort();
    return result;
  }

  stateOf(deviceId: string): PeerConnectionState { return this.connections.get(deviceId)?.state ?? 'DISCONNECTED'; }

  async close(deviceId: string): Promise<void> {
    const connection = this.connections.get(deviceId);
    if (connection === undefined) return;
    connection.bindWaiter?.(false);
    connection.bindWaiter = undefined;
    this.dataHandlers.delete(deviceId);
    this.connections.delete(deviceId);
  }

  async destroy(): Promise<void> {
    const ids: string[] = [];
    for (const id of this.connections.keys()) ids.push(id);
    for (const id of ids) await this.close(id);
    this.usedTokens.clear();
  }

  private require(deviceId: string): PeerConnection {
    const connection = this.connections.get(deviceId);
    if (connection === undefined) throw new Error('E_PEER_NOT_FOUND');
    return connection;
  }

  private handleDataMessage(deviceId: string, text: string): void {
    let message: DataFrameMessage;
    try { message = JSON.parse(text) as DataFrameMessage; } catch (_) { return; }
    if (message.type === 'DATA_BIND') {
      const payload = message.payload as DataBindPayload;
      this.logger.info('DSK_BIND_RECEIVED', 'transport=' + deviceId.slice(-4) + ' payload=' + payload.deviceId.slice(-4));
      this.acceptBinding(payload, deviceId).then((accepted: boolean): void => {
        this.logger.info(accepted ? 'DSK_BIND_ACCEPTED' : 'DSK_BIND_REJECTED', 'transport=' + deviceId.slice(-4));
        if (!accepted) return;
        const ack: DataFrameMessage = { type: 'DATA_BIND_ACK', payload: {
          deviceId: payload.deviceId, endpointVersion: payload.endpointVersion,
          sessionEpoch: payload.sessionEpoch, acceptedAtMs: this.clock()
        } as DataBindAckPayload };
        this.dataChannel.send(deviceId, JSON.stringify(ack))
          .then((): void => this.logger.info('DSK_BIND_ACK_SENT', 'transport=' + deviceId.slice(-4)))
          .catch((error: Error): void => this.logger.error('DSK_BIND_ACK_FAILED', error.message));
      });
      return;
    }
    if (message.type === 'DATA_BIND_ACK') {
      const payload = message.payload as DataBindAckPayload;
      const connection = this.connections.get(deviceId);
      if (connection === undefined || connection.state !== 'BINDING' || payload.deviceId !== deviceId ||
        payload.endpointVersion !== connection.endpointVersion || payload.sessionEpoch !== connection.sessionEpoch) return;
      connection.state = 'READY';
      connection.bindWaiter?.(true);
      connection.bindWaiter = undefined;
      return;
    }
    this.dataHandlers.get(deviceId)?.(text);
  }
}
