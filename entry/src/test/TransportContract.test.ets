import { describe, expect, it } from '@ohos/hypium';
import { AppError } from '../main/ets/common/AppError';
import { TransportListener } from '../main/ets/communication/Transport';
import { FakeTransport } from './support/FakeTransport';

class CaptureListener implements TransportListener {
  receivedText: string = '';

  onConnected(): void {
  }

  onMessage(text: string): void {
    this.receivedText = text;
  }

  onDisconnected(): void {
  }

  onError(error: AppError): void {
  }
}

export default function transportContractTest(): void {
  describe('TransportContract', () => {
    it('deliversMessagesToListener', 0, async () => {
      const transport = new FakeTransport();
      const listener = new CaptureListener();
      transport.setListener(listener);
      transport.emitMessage('hello');
      expect(listener.receivedText).assertEqual('hello');
    });
    it('disconnectIsIdempotent', 0, async () => {
      const transport = new FakeTransport();
      await transport.disconnect();
      await transport.disconnect();
      expect(transport.disconnectCalls).assertEqual(1);
    });
  });
}
