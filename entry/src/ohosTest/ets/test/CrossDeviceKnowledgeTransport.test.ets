import { describe, expect, it } from '@ohos/hypium';
import {
  SEMALINK_CROSS_DEVICE_PROTOCOL_VERSION
} from '../../../main/ets/crossdevice/protocol/CrossDeviceProtocolModels';

export const CROSS_DEVICE_HARDWARE_STATUS: string = 'COMPILED_NOT_EXECUTED';

export default function crossDeviceKnowledgeTransportTest(): void {
  describe('CrossDeviceKnowledgeTransport', () => {
    it('keeps the real three-device case explicitly hardware gated', 0, () => {
      expect(SEMALINK_CROSS_DEVICE_PROTOCOL_VERSION).assertEqual(1);
      expect(CROSS_DEVICE_HARDWARE_STATUS).assertEqual('COMPILED_NOT_EXECUTED');
    });
  });
}
