import { describe, expect, it } from '@ohos/hypium';
import {
  DeviceTopologyPlatform,
  HarmonyDeviceTopologyProvider
} from '../main/ets/communication/DeviceTopologyProvider';
import { AvailableDeviceInfo } from '../main/ets/communication/TrustedDeviceResolver';
import { AppError } from '../main/ets/common/AppError';

class FakeTopologyPlatform implements DeviceTopologyPlatform {
  subscribeCalls: number = 0;
  unsubscribeCalls: number = 0;
  releaseCalls: number = 0;
  private listener: (() => void) | undefined;
  private readonly localId: string;
  private readonly devices: AvailableDeviceInfo[];

  constructor(localId: string, devices: AvailableDeviceInfo[]) {
    this.localId = localId;
    this.devices = devices;
  }

  localNetworkId(): string {
    return this.localId;
  }

  availableDevices(): Promise<AvailableDeviceInfo[]> {
    return Promise.resolve(this.devices);
  }

  onDeviceStateChanged(listener: () => void): void {
    this.subscribeCalls += 1;
    this.listener = listener;
  }

  offDeviceStateChanged(listener: () => void): void {
    if (this.listener === listener) {
      this.listener = undefined;
    }
    this.unsubscribeCalls += 1;
  }

  release(): void {
    this.releaseCalls += 1;
  }

  emitChanged(): void {
    this.listener?.();
  }
}

export default function deviceTopologyProviderTest(): void {
  describe('DeviceTopologyProvider', () => {
    it('returnsLocalNetworkIdAndUniqueSortedPeers', 0, async () => {
      const platform = new FakeTopologyPlatform('local-network', [
        { deviceId: 'legacy-c', networkId: 'remote-c', deviceName: 'C', deviceType: 'phone' },
        { deviceId: 'remote-b', deviceName: 'B', deviceType: 'tablet' },
        { networkId: 'remote-c', deviceName: 'duplicate', deviceType: 'phone' },
        { deviceId: '', deviceName: 'empty', deviceType: 'phone' }
      ]);
      const provider = new HarmonyDeviceTopologyProvider('com.example.semalink', platform);

      const snapshot = await provider.snapshot();

      expect(snapshot.localDeviceId).assertEqual('local-network');
      expect(snapshot.peers.length).assertEqual(2);
      expect(snapshot.peers[0].deviceId).assertEqual('remote-b');
      expect(snapshot.peers[1].deviceId).assertEqual('remote-c');
    });

    it('subscribesOnceAndStopsOnce', 0, () => {
      const platform = new FakeTopologyPlatform('local-network', []);
      const provider = new HarmonyDeviceTopologyProvider('com.example.semalink', platform);
      let changes = 0;

      provider.start((): void => { changes += 1; });
      provider.start((): void => { changes += 10; });
      platform.emitChanged();
      provider.stop();
      provider.stop();
      platform.emitChanged();

      expect(changes).assertEqual(1);
      expect(platform.subscribeCalls).assertEqual(1);
      expect(platform.unsubscribeCalls).assertEqual(1);
      expect(platform.releaseCalls).assertEqual(1);
    });

    it('rejectsAnEmptyLocalNetworkId', 0, async () => {
      const provider = new HarmonyDeviceTopologyProvider(
        'com.example.semalink', new FakeTopologyPlatform('', []));
      let code = '';

      try {
        await provider.snapshot();
      } catch (error) {
        code = (error as AppError).code;
      }

      expect(code).assertEqual('E_LOCAL_DEVICE_ID_UNAVAILABLE');
    });
  });
}
