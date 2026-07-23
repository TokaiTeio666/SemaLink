import { distributedDeviceManager } from '@kit.DistributedServiceKit';

export class SystemVisibleDevice {
  readonly transportReference: string;
  readonly alias: string;
  readonly deviceType: string;

  constructor(transportReference: string, alias: string, deviceType: string) {
    this.transportReference = transportReference;
    this.alias = alias;
    this.deviceType = deviceType;
  }
}

export type SystemDeviceStateListener =
  (device: SystemVisibleDevice, online: boolean) => void;

export class SystemTrustedDeviceSource {
  private readonly manager: distributedDeviceManager.DeviceManager;
  private readonly listeners: Set<SystemDeviceStateListener> =
    new Set<SystemDeviceStateListener>();
  private released: boolean = false;

  constructor(bundleName: string) {
    this.manager = distributedDeviceManager.createDeviceManager(bundleName);
    this.manager.on('deviceStateChange', (change): void => {
      const visible = new SystemVisibleDevice(
        change.device.networkId ?? change.device.deviceId,
        change.device.deviceName,
        change.device.deviceType
      );
      const online: boolean =
        change.action === distributedDeviceManager.DeviceStateChange.AVAILABLE;
      this.listeners.forEach((listener: SystemDeviceStateListener): void => {
        listener(visible, online);
      });
    });
  }

  async listVisible(): Promise<SystemVisibleDevice[]> {
    if (this.released) {
      return [];
    }
    const devices: distributedDeviceManager.DeviceBasicInfo[] =
      await this.manager.getAvailableDeviceList();
    return devices.map((device: distributedDeviceManager.DeviceBasicInfo): SystemVisibleDevice =>
      new SystemVisibleDevice(
        device.networkId ?? device.deviceId,
        device.deviceName,
        device.deviceType
      ));
  }

  subscribe(listener: SystemDeviceStateListener): void {
    this.listeners.add(listener);
  }

  unsubscribe(listener: SystemDeviceStateListener): void {
    this.listeners.delete(listener);
  }

  destroy(): void {
    if (this.released) {
      return;
    }
    this.released = true;
    this.listeners.clear();
    this.manager.off('deviceStateChange');
    distributedDeviceManager.releaseDeviceManager(this.manager);
  }
}
