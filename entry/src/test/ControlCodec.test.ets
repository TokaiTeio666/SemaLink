import { describe, expect, it } from '@ohos/hypium';
import { AppError } from '../main/ets/common/AppError';
import { ControlCodec } from '../main/ets/communication/control/ControlCodec';
import { ControlEnvelope, DataEndpointOffer } from '../main/ets/communication/control/ControlModels';

const codec = (): ControlCodec => new ControlCodec();
const close = (messageId: string): ControlEnvelope => ({
  version: '1.0', type: 'CONTROL_CLOSE', messageId: messageId, deviceId: 'remote-a', sentAtMs: 1,
  payload: { reason: 'done' }
});
const offer = (port: number, expiresAtMs: number): ControlEnvelope => {
  const payload: DataEndpointOffer = {
    host: '192.168.1.10', port: port, certificateFingerprint: 'a'.repeat(64), bindingToken: 'token',
    endpointVersion: 1, expiresAtMs: expiresAtMs, dataProtocolVersion: '2.0'
  };
  return { version: '1.0', type: 'DATA_ENDPOINT_OFFER', messageId: 'offer', deviceId: 'remote-a', sentAtMs: 1, payload: payload };
};

export default function controlCodecTest(): void {
  describe('ControlCodec', () => {
    it('rejectsControlDataOnDsk', 0, () => {
      let code = '';
      try {
        const invalidText: string = JSON.stringify(close('x')).replace('CONTROL_CLOSE', 'EVIDENCE_BATCH');
        codec().decode(invalidText);
      } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_CONTROL_INVALID');
    });
    it('rejectsEmptyMessageId', 0, () => {
      let code = '';
      try { codec().encode(close('')); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_CONTROL_INVALID');
    });
    it('rejectsInvalidPort', 0, () => {
      let code = '';
      try { codec().encode(offer(65536, Date.now() + 10000)); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_CONTROL_INVALID');
    });
    it('rejectsExpiredEndpoint', 0, () => {
      let code = '';
      try { codec().encode(offer(443, Date.now() - 1)); } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_CONTROL_INVALID');
    });
  });
}
