import { describe, expect, it } from '@ohos/hypium';
import { CrossDeviceProtocolCodec } from
  '../main/ets/crossdevice/protocol/CrossDeviceProtocolCodec';

function throws(action: () => void): boolean {
  try {
    action();
    return false;
  } catch (_) {
    return true;
  }
}

export default function crossDeviceProtocolVersionTest(): void {
  describe('CrossDeviceProtocolVersion', () => {
    it('rejects unknown protocol versions', 0, () => {
      const codec = new CrossDeviceProtocolCodec();
      const text = '{"protocolVersion":2,"messageType":"PING","messageId":"m",' +
        '"requestId":"r","taskId":"t","senderAppInstanceId":"a","sentAtMs":1,' +
        '"deadlineAtMs":2,"sequence":0,"payload":{}}';
      expect(throws((): void => { codec.decode(text); })).assertTrue();
    });

    it('rejects unknown message types', 0, () => {
      const codec = new CrossDeviceProtocolCodec();
      const text = '{"protocolVersion":1,"messageType":"EXECUTE","messageId":"m",' +
        '"requestId":"r","taskId":"t","senderAppInstanceId":"a","sentAtMs":1,' +
        '"deadlineAtMs":2,"sequence":0,"payload":{}}';
      expect(throws((): void => { codec.decode(text); })).assertTrue();
    });
  });
}
