import { AppError, ErrorStage } from '../../main/ets/common/AppError';
import { PeerDevice } from '../../main/ets/model/AppModels';
import { Transport, TransportListener } from '../../main/ets/communication/Transport';

export class FakeTransport implements Transport {
  private listener: TransportListener | null = null;
  public sentMessages: Array<string> = [];
  public connectCalls: number = 0;
  public disconnectCalls: number = 0;
  public destroyed: boolean = false;
  public peerDevice: PeerDevice | null = null;
  private connected: boolean = false;

  setListener(listener: TransportListener): void {
    this.listener = listener;
  }

  async connect(peer: PeerDevice): Promise<void> {
    if (this.destroyed) {
      throw new AppError('E_TRANSPORT_DESTROYED', '传输组件已销毁', ErrorStage.CONNECTION, false);
    }
    this.connectCalls += 1;
    this.peerDevice = peer;
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
    this.destroyed = true;
    this.listener = null;
  }

  isConnected(): boolean {
    return this.connected;
  }

  getPeerDevice(): PeerDevice | null {
    return this.peerDevice;
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
