import { describe, expect, it } from '@ohos/hypium';
import { BindingTokenGenerator, PeerConnectionPool } from '../main/ets/communication/PeerConnectionPool';
import { PeerDevice } from '../main/ets/model/AppModels';
import { DskDataTransport } from '../main/ets/communication/control/DskDataChannel';

const PEER_B: PeerDevice = { deviceId: 'remote-b', deviceName: 'B', deviceType: 'phone' };
const PEER_C: PeerDevice = { deviceId: 'remote-c', deviceName: 'C', deviceType: 'phone' };

class Hub implements DskDataTransport {
  handler: ((deviceId: string, frame: Object) => void) | undefined;
  sent: Object[] = [];
  onDataMessage(handler: (deviceId: string, frame: Object) => void): void { this.handler = handler; }
  async sendData(_deviceId: string, frame: Object): Promise<void> { this.sent.push(frame); }
}
class FixedTokenGenerator implements BindingTokenGenerator { async generate(): Promise<string> { return 'token'; } }
interface BindPayload { endpointVersion: number; sessionEpoch: string; bindingToken: string; }
interface BindEnvelope { type: string; payload: BindPayload; }
interface DataFrame { channel: string; version: string; frameId: string; index: number; total: number; textLength: number; payload: string; }

export default function peerConnectionPoolTest(): void {
  describe('PeerConnectionPool', () => {
    it('keeps peer cleanup isolated and idempotent', 0, async () => {
      const pool = new PeerConnectionPool(new Hub());
      await pool.refreshPeers([PEER_B, PEER_C]);
      expect(pool.stateOf('remote-b')).assertEqual('DISCONNECTED');
      await pool.close('remote-b');
      expect(pool.stateOf('remote-c')).assertEqual('DISCONNECTED');
      await pool.destroy();
    });

    it('sends DSK DATA_BIND instead of opening a network endpoint', 0, async () => {
      const hub = new Hub();
      const pool = new PeerConnectionPool(hub, undefined, new FixedTokenGenerator());
      await pool.refreshPeers([PEER_B]);
      const binding = pool.beginBinding('remote-b');
      await new Promise<void>((resolve) => setTimeout(resolve, 0));
      expect(hub.sent.length).assertEqual(1);
      const frame = JSON.parse(((hub.sent[0] as DataFrame).payload)) as BindEnvelope;
      expect(frame.payload.bindingToken).assertEqual('token');
      const ackText = '{"type":"DATA_BIND_ACK","payload":{"deviceId":"remote-b","endpointVersion":1,"sessionEpoch":"token","acceptedAtMs":2}}';
      const ack: DataFrame = { channel: 'DATA', version: '1.0', frameId: 'ack', index: 0, total: 1, textLength: ackText.length, payload: ackText };
      hub.handler?.('remote-b', ack);
      expect(await binding).assertTrue();
      expect(pool.stateOf('remote-b')).assertEqual('READY');
      await pool.destroy();
    });
  });
}
