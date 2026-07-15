import { describe, expect, it } from '@ohos/hypium';
import { AvailableDeviceProvider, TrustedDeviceResolver } from '../main/ets/communication/TrustedDeviceResolver';
import { AppError } from '../main/ets/common/AppError';
import { PeerDevice } from '../main/ets/model/AppModels';

class FakeProvider implements AvailableDeviceProvider {
  released: boolean = false;
  private readonly devices: Array<PeerDevice>;

  constructor(devices: Array<PeerDevice>) {
    this.devices = devices;
  }

  list(): Promise<Array<PeerDevice>> { return Promise.resolve(this.devices); }
  release(): void { this.released = true; }
}

export default function trustedDeviceResolverTest(): void {
  describe('TrustedDeviceResolver', () => {
    it('returnsOnlyDevice', 0, async () => {
      const provider = new FakeProvider([{ deviceId: 'd1', deviceName: 'MatePad', deviceType: 'tablet' }]);
      const peer = await new TrustedDeviceResolver(provider).resolveUnique();
      expect(peer.deviceId).assertEqual('d1');
      expect(provider.released).assertTrue();
    });
    it('rejectsNoDevice', 0, async () => {
      let code = '';
      try {
        await new TrustedDeviceResolver(new FakeProvider([])).resolveUnique();
      } catch (error) {
        code = (error as AppError).code;
      }
      expect(code).assertEqual('E_DEVICE_NOT_FOUND');
    });
    it('rejectsMultipleDevices', 0, async () => {
      const devices: Array<PeerDevice> = [
        { deviceId: 'd1', deviceName: 'A', deviceType: 'phone' },
        { deviceId: 'd2', deviceName: 'B', deviceType: 'tablet' }
      ];
      let code = '';
      try {
        await new TrustedDeviceResolver(new FakeProvider(devices)).resolveUnique();
      } catch (error) {
        code = (error as AppError).code;
      }
      expect(code).assertEqual('E_MULTIPLE_DEVICES');
    });
  });
}
