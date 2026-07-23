import { describe, expect, it } from '@ohos/hypium';
import { DskDataChannel, DskDataTransport } from '../main/ets/communication/control/DskDataChannel';

class TestHub implements DskDataTransport {
  handler: ((deviceId: string, frame: Object) => void) | undefined;
  sent: Object[] = [];
  onDataMessage(handler: (deviceId: string, frame: Object) => void): void { this.handler = handler; }
  async sendData(_deviceId: string, frame: Object): Promise<void> { this.sent.push(frame); }
}

export default function dskDataChannelTest(): void {
  describe('DskDataChannel', () => {
    it('splits a large UTF-8 payload into bounded DSK frames and reassembles it', 0, async () => {
      const fakeHub = new TestHub();
      const channel = new DskDataChannel(fakeHub);
      let received = '';
      channel.onMessage('peer', (text: string): void => { received = text; });
      const text = '鸿'.repeat(1000) + '-payload';
      await channel.send('peer', text);
      expect(fakeHub.sent.length > 1).assertTrue();
      for (const frame of fakeHub.sent) {
        expect(JSON.stringify(frame).length <= 1024).assertTrue();
        fakeHub.handler?.('peer', frame);
      }
      expect(received).assertEqual(text);
    });

    it('rejects logical messages above the reassembly limit', 0, async () => {
      const channel = new DskDataChannel(new TestHub());
      let rejected: boolean = false;
      try {
        await channel.send('peer', 'x'.repeat(64 * 1024 + 1));
      } catch (_) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });

    it('replays completed messages received before handler installation in order', 0, async () => {
      const fakeHub = new TestHub();
      const channel = new DskDataChannel(fakeHub);
      await channel.send('peer', 'HELLO');
      await channel.send('peer', 'PROFILE_DIGEST');
      fakeHub.sent.forEach((frame: Object): void => fakeHub.handler?.('peer', frame));

      const received: string[] = [];
      channel.onMessage('peer', (text: string): void => {
        received.push(text);
      });
      expect(JSON.stringify(received)).assertEqual(
        JSON.stringify(['HELLO', 'PROFILE_DIGEST'])
      );
    });
  });
}
