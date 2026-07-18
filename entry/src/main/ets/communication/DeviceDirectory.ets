import {
  DeviceProfileAdvertisement,
  DeviceRuntimeSnapshot
} from '../contracts/semantic/SemanticModels';

export const REMOTE_PROFILE_TTL_MS: number = 5 * 60 * 1000;

export interface DeviceRoutingCandidate {
  snapshot: DeviceRuntimeSnapshot;
  profile: DeviceProfileAdvertisement;
}

interface DirectoryEntry {
  snapshot: DeviceRuntimeSnapshot;
  profile: DeviceProfileAdvertisement;
}

export class DeviceDirectory {
  private readonly clock: () => number;
  private local: DirectoryEntry | null = null;
  private remote: DirectoryEntry | null = null;

  constructor(clock: () => number = (): number => Date.now()) {
    this.clock = clock;
  }

  setLocal(snapshot: DeviceRuntimeSnapshot, profile: DeviceProfileAdvertisement): void {
    this.local = { snapshot: snapshot, profile: profile };
  }

  setRemote(profile: DeviceProfileAdvertisement): void {
    const advertisedAtMs: number = profile.advertisedAtMs;
    const snapshot: DeviceRuntimeSnapshot = {
      deviceId: profile.deviceId,
      deviceAlias: profile.deviceAlias,
      isLocal: false,
      state: profile.indexState === 'READY' ? 'READY' : 'BUSY',
      profileVersion: profile.profileVersion,
      indexVersion: profile.indexVersion,
      lastSeenAtMs: advertisedAtMs,
      averageRttMs: 0,
      load: 0,
      advertisedAtMs: advertisedAtMs
    };
    this.remote = { snapshot: snapshot, profile: profile };
  }

  clearRemote(): void {
    this.remote = null;
  }

  snapshot(): DeviceRuntimeSnapshot[] {
    const result: DeviceRuntimeSnapshot[] = [];
    if (this.local !== null) {
      result.push(this.local.snapshot);
    }
    if (this.remote !== null && this.isRemoteFresh(this.remote)) {
      result.push(this.remote.snapshot);
    }
    return result;
  }

  candidates(): DeviceRoutingCandidate[] {
    const result: DeviceRoutingCandidate[] = [];
    if (this.local !== null) {
      result.push({ snapshot: this.local.snapshot, profile: this.local.profile });
    }
    if (this.remote !== null && this.isRemoteFresh(this.remote)) {
      result.push({ snapshot: this.remote.snapshot, profile: this.remote.profile });
    }
    return result;
  }

  private isRemoteFresh(entry: DirectoryEntry): boolean {
    return this.clock() - entry.profile.advertisedAtMs <= REMOTE_PROFILE_TTL_MS;
  }
}
