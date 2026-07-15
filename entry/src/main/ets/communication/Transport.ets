import { AppError } from '../common/AppError';
import { PeerDevice } from '../model/AppModels';

export interface TransportListener {
  onConnected(): void;
  onMessage(text: string): void;
  onDisconnected(reason?: number): void;
  onError(error: AppError): void;
}

export interface Transport {
  setListener(listener: TransportListener): void;
  connect(peer: PeerDevice): Promise<void>;
  accept(wantParam: Record<string, Object>): boolean;
  send(text: string): Promise<void>;
  disconnect(): Promise<void>;
  destroy(): void;
  isConnected(): boolean;
  getPeerDevice(): PeerDevice | null;
}
