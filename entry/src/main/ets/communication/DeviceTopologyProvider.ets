import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import { AppError, ErrorStage } from '../common/AppError';
import { PeerDevice } from '../model/AppModels';
import {
  AvailableDeviceInfo,
  mapAvailableDevice,
  uniqueSortedPeers
} from './TrustedDeviceResolver';

export interface DeviceTopologySnapshot {
  localDeviceId: string;
  peers: PeerDevice[];
}

export interface DeviceTopologyProvider {
  start(onChanged: () => void): void;
  snapshot(): Promise<DeviceTopologySnapshot>;
  stop(): void;
}

export interface DeviceTopologyPlatform {
  localNetworkId(): string;
  availableDevices(): Promise<AvailableDeviceInfo[]>;
  onDeviceStateChanged(listener: () => void): void;
  offDeviceStateChanged(listener: () => void): void;
  release(): void;
}

export class HarmonyDeviceTopologyPlatform implements DeviceTopologyPlatform {
  private readonly manager: distributedDeviceManager.DeviceManager;
  private callback: (() => void) | undefined;

  constructor(bundleName: string) {
    this.manager = distributedDeviceManager.createDeviceManager(bundleName);
  }

  localNetworkId(): string {
    return this.manager.getLocalDeviceNetworkId();
  }

  async availableDevices(): Promise<AvailableDeviceInfo[]> {
    const devices = await this.manager.getAvailableDeviceList();
    return devices as AvailableDeviceInfo[];
  }

  onDeviceStateChanged(listener: () => void): void {
    this.callback = listener;
    this.manager.on('deviceStateChange', (): void => listener());
  }

  offDeviceStateChanged(_listener: () => void): void {
    if (this.callback !== undefined) {
      this.manager.off('deviceStateChange');
    }
    this.callback = undefined;
  }

  release(): void {
    try {
      distributedDeviceManager.releaseDeviceManager(this.manager);
    } catch (_) {
      // Cleanup must not mask the lifecycle operation that triggered release.
    }
  }
}

export class HarmonyDeviceTopologyProvider implements DeviceTopologyProvider {
  private readonly platform: DeviceTopologyPlatform;
  private started: boolean = false;
  private stopped: boolean = false;
  private listener: (() => void) | undefined;

  constructor(bundleName: string, platform?: DeviceTopologyPlatform) {
    this.platform = platform ?? new HarmonyDeviceTopologyPlatform(bundleName);
  }

  start(onChanged: () => void): void {
    if (this.started || this.stopped) {
      return;
    }
    this.started = true;
    this.listener = onChanged;
    this.platform.onDeviceStateChanged(onChanged);
  }

  async snapshot(): Promise<DeviceTopologySnapshot> {
    const localDeviceId = this.platform.localNetworkId();
    if (localDeviceId.length === 0) {
      throw new AppError(
        'E_LOCAL_DEVICE_ID_UNAVAILABLE',
        'local network id unavailable',
        ErrorStage.SELECTION,
        true
      );
    }
    const available = await this.platform.availableDevices();
    const peers: PeerDevice[] = [];
    for (const device of available) {
      const peer = mapAvailableDevice(device);
      if (peer !== undefined && peer.deviceId !== localDeviceId) {
        peers.push(peer);
      }
    }
    return { localDeviceId: localDeviceId, peers: uniqueSortedPeers(peers) };
  }

  stop(): void {
    if (this.stopped) {
      return;
    }
    this.stopped = true;
    if (this.listener !== undefined) {
      this.platform.offDeviceStateChanged(this.listener);
      this.listener = undefined;
    }
    this.platform.release();
  }
}
