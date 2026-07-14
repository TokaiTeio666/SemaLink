import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import { AppError, ErrorStage } from '../common/AppError';
import { PeerDevice } from '../model/AppModels';

export interface AvailableDeviceProvider {
  list(): Promise<Array<PeerDevice>>;
  release(): void;
}

export class DistributedDeviceProvider implements AvailableDeviceProvider {
  private readonly manager: distributedDeviceManager.DeviceManager;

  constructor(bundleName: string) {
    this.manager = distributedDeviceManager.createDeviceManager(bundleName);
  }

  async list(): Promise<Array<PeerDevice>> {
    const devices = await this.manager.getAvailableDeviceList();
    const result: Array<PeerDevice> = [];
    for (const device of devices) {
      const peer: PeerDevice = {
        deviceId: device.deviceId,
        deviceName: device.deviceName,
        deviceType: device.deviceType
      };
      result.push(peer);
    }
    return result;
  }

  release(): void {
    distributedDeviceManager.releaseDeviceManager(this.manager);
  }
}

export class TrustedDeviceResolver {
  private readonly provider: AvailableDeviceProvider;

  constructor(provider: AvailableDeviceProvider) {
    this.provider = provider;
  }

  async resolveUnique(): Promise<PeerDevice> {
    try {
      const devices = await this.provider.list();
      if (devices.length === 0) {
        throw new AppError('E_DEVICE_NOT_FOUND', '未发现可用可信设备', ErrorStage.SELECTION, true);
      }
      if (devices.length > 1) {
        throw new AppError('E_MULTIPLE_DEVICES', '发现多个可信设备，请仅保留目标设备在线', ErrorStage.SELECTION, true);
      }
      return devices[0];
    } finally {
      this.provider.release();
    }
  }
}
