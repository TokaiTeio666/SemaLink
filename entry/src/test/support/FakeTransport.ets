import { AppError } from '../../main/ets/common/AppError';
import { PeerDevice } from '../../main/ets/model/AppModels';
import { Transport, TransportListener } from '../../main/ets/communication/Transport';

export class FakeTransport implements Transport {
  private listener: TransportListener | null = null;
  public sentMessages: Array<string> = [];
  public connectCalls: number = 0;
  public disconnectCalls: number = 0;
  private connected: boolean = false;

  setListener(listener: TransportListener): void {
    this.listener = listener;
  }

  async connect(peer: PeerDevice): Promise<void> {
    this.connectCalls += 1;
    this.connected = true;
  }

  accept(wantParam: Record<string, Object>): boolean {
    return true;
  }

  async send(text: string): Promise<void> {
    this.sentMessages.push(text);
  }

  async disconnect(): Promise<void> {
    if (this.disconnectCalls > 0) {
      return;
    }
    this.disconnectCalls += 1;
    this.connected = false;
  }

  destroy(): void {
    this.listener = null;
  }

  isConnected(): boolean {
    return this.connected;
  }

  emitConnected(): void {
    this.listener?.onConnected();
  }

  emitMessage(text: string): void {
    this.listener?.onMessage(text);
  }

  emitDisconnected(reason?: number): void {
    this.connected = false;
    this.listener?.onDisconnected(reason);
  }

  emitError(error: AppError): void {
    this.listener?.onError(error);
  }
}
