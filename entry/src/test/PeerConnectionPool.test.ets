import { describe, expect, it } from '@ohos/hypium';
import {
  BindingTokenGenerator,
  PeerConnectionPool,
  PeerConnectionState
} from '../main/ets/communication/PeerConnectionPool';
import { PeerDevice } from '../main/ets/model/AppModels';
import { DskDataTransport } from '../main/ets/communication/control/DskDataChannel';
import { DataBindPayload } from '../main/ets/communication/control/ControlModels';

const PEER_B: PeerDevice = { deviceId: 'remote-b', deviceName: 'B', deviceType: 'phone' };
const PEER_C: PeerDevice = { deviceId: 'remote-c', deviceName: 'C', deviceType: 'phone' };

class Hub implements DskDataTransport {
  handler: ((deviceId: string, frame: Object) => void) | undefined;
  sent: Object[] = [];
  onDataMessage(handler: (deviceId: string, frame: Object) => void): void { this.handler = handler; }
  async sendData(_deviceId: string, frame: Object): Promise<void> { this.sent.push(frame); }
}
class FixedTokenGenerator implements BindingTokenGenerator { async generate(): Promise<string> { return 'token'; } }
class DelayedTokenGenerator implements BindingTokenGenerator {
  async generate(): Promise<string> {
    await new Promise<void>((resolve) => setTimeout(resolve, 1));
    return 'token';
  }
}
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

    it('publishes binding ready and disconnected state changes', 0, async () => {
      const hub = new Hub();
      const pool = new PeerConnectionPool(hub, undefined, new FixedTokenGenerator());
      const changes: string[] = [];
      pool.onStateChanged((deviceId: string, state: PeerConnectionState): void => {
        changes.push(deviceId + ':' + state);
      });
      await pool.refreshPeers([PEER_B]);
      const binding = pool.beginBinding('remote-b');
      await new Promise<void>((resolve) => setTimeout(resolve, 0));
      const ackText = '{"type":"DATA_BIND_ACK","payload":{"deviceId":"remote-b","endpointVersion":1,"sessionEpoch":"token","acceptedAtMs":2}}';
      const ack: DataFrame = { channel: 'DATA', version: '1.0', frameId: 'ack-state', index: 0, total: 1,
        textLength: ackText.length, payload: ackText };
      hub.handler?.('remote-b', ack);
      expect(await binding).assertTrue();
      await pool.close('remote-b');

      expect(changes.length).assertEqual(3);
      expect(changes[0]).assertEqual('remote-b:BINDING');
      expect(changes[1]).assertEqual('remote-b:READY');
      expect(changes[2]).assertEqual('remote-b:DISCONNECTED');
    });

    it('acceptsAuthenticatedInboundBindingDuringSimultaneousOutboundBinding', 0, async () => {
      const hub = new Hub();
      const pool = new PeerConnectionPool(hub, undefined, new DelayedTokenGenerator());
      await pool.refreshPeers([PEER_B]);
      const outboundBinding = pool.beginBinding('remote-b');
      const inbound: DataBindPayload = {
        deviceId: 'local-a',
        controlSessionId: 'local-a',
        endpointVersion: 1,
        sessionEpoch: 'remote-token',
        bindingToken: 'remote-token'
      };

      expect(await pool.acceptBinding(inbound, 'remote-b')).assertTrue();
      expect(await outboundBinding).assertTrue();
      expect(pool.stateOf('remote-b')).assertEqual('READY');
      await pool.destroy();
    });

    it('rejectsMalformedInboundBindingWithoutChangingState', 0, async () => {
      const pool = new PeerConnectionPool(new Hub());
      await pool.refreshPeers([PEER_B]);
      const malformed = { deviceId: '', controlSessionId: '', endpointVersion: 0,
        sessionEpoch: '', bindingToken: '' } as DataBindPayload;

      expect(await pool.acceptBinding(malformed, 'remote-b')).assertFalse();
      expect(pool.stateOf('remote-b')).assertEqual('DISCONNECTED');
      await pool.destroy();
    });
  });
}
