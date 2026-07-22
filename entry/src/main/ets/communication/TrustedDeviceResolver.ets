import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
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
    try {
      const devices = await this.manager.getAvailableDeviceList();
      const result: Array<PeerDevice> = [];
      const seen: Set<string> = new Set<string>();
      for (const device of devices) {
        const networkId: string = device.networkId ?? '';
        if (networkId.length === 0 || seen.has(networkId)) {
          continue;
        }
        seen.add(networkId);
        const peer: PeerDevice = {
          deviceId: networkId,
          deviceName: device.deviceName,
          deviceType: device.deviceType
        };
        result.push(peer);
      }
      return result;
    } catch (error) {
      const businessError = error as BusinessError;
      throw new AppError(
        'E_DEVICE_LIST_FAILED',
        '获取设备列表失败: ' + businessError.message,
        ErrorStage.SELECTION,
        true,
        businessError.code
      );
    }
  }

  release(): void {
    try {
      distributedDeviceManager.releaseDeviceManager(this.manager);
    } catch (e) {
      // releaseDeviceManager may throw during cleanup; suppress to avoid masking primary errors
    }
  }
}

export class TrustedDeviceResolver {
  private readonly provider: AvailableDeviceProvider;

  constructor(provider: AvailableDeviceProvider) {
    this.provider = provider;
  }

  async resolveAll(): Promise<Array<PeerDevice>> {
    try {
      const devices: Array<PeerDevice> = await this.provider.list();
      const unique: Map<string, PeerDevice> = new Map<string, PeerDevice>();
      for (const device of devices) {
        if (device.deviceId.length > 0 && !unique.has(device.deviceId)) {
          unique.set(device.deviceId, device);
        }
      }
      return Array.from(unique.values()).sort((left: PeerDevice, right: PeerDevice): number =>
        left.deviceId < right.deviceId ? -1 : (left.deviceId > right.deviceId ? 1 : 0));
    } finally {
      this.provider.release();
    }
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
