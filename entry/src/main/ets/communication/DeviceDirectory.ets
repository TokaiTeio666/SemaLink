import {
  DeviceProfileAdvertisement,
  DeviceRuntimeSnapshot
} from '../contracts/semantic/SemanticModels';

export const REMOTE_PROFILE_TTL_MS: number = 5 * 60 * 1000;

export interface DeviceRoutingCandidate {
  snapshot: DeviceRuntimeSnapshot;
  profile: DeviceProfileAdvertisement;
}

export type ControlChannelState =
  'DISCONNECTED' |
  'CONNECTING' |
  'READY' |
  'FAILED';

export type DataChannelState =
  'DISCONNECTED' |
  'CONNECTING' |
  'BINDING' |
  'READY' |
  'FAILED';

export interface DirectoryEntry {
  snapshot: DeviceRuntimeSnapshot;
  profile: DeviceProfileAdvertisement;
  controlState: ControlChannelState;
  dataState: DataChannelState;
  endpointVersion: number;
  lastFailureCode: string;
}

function cloneSnapshot(
  snapshot: DeviceRuntimeSnapshot
): DeviceRuntimeSnapshot {
  return {
    deviceId: snapshot.deviceId,
    deviceAlias: snapshot.deviceAlias,
    isLocal: snapshot.isLocal,
    state: snapshot.state,
    profileVersion: snapshot.profileVersion,
    indexVersion: snapshot.indexVersion,
    lastSeenAtMs: snapshot.lastSeenAtMs,
    averageRttMs: snapshot.averageRttMs,
    load: snapshot.load,
    advertisedAtMs: snapshot.advertisedAtMs
  };
}

function cloneProfile(
  profile: DeviceProfileAdvertisement
): DeviceProfileAdvertisement {
  return {
    semanticContractVersion: profile.semanticContractVersion,
    deviceId: profile.deviceId,
    deviceAlias: profile.deviceAlias,
    profileVersion: profile.profileVersion,
    indexVersion: profile.indexVersion,
    indexState: profile.indexState,
    knowledgeDomains: profile.knowledgeDomains.slice(),
    modalities: profile.modalities.slice(),
    retrievalModes: profile.retrievalModes.slice(),
    supportedLevels: profile.supportedLevels.slice(),
    advertisedAtMs: profile.advertisedAtMs,
    ttlMs: profile.ttlMs
  };
}

export class DeviceDirectory {
  private readonly clock: () => number;

  private local: DirectoryEntry | null = null;

  private readonly remotes: Map<string, DirectoryEntry> =
    new Map<string, DirectoryEntry>();

  constructor(clock: () => number = (): number => Date.now()) {
    this.clock = clock;
  }

  setLocal(
    snapshot: DeviceRuntimeSnapshot,
    profile: DeviceProfileAdvertisement
  ): void {
    this.local = {
      snapshot: cloneSnapshot(snapshot),
      profile: cloneProfile(profile),
      controlState: 'READY',
      dataState: 'READY',
      endpointVersion: 0,
      lastFailureCode: ''
    };
  }

  setRemote(profile: DeviceProfileAdvertisement): void {
    this.upsertRemote(profile);
  }

  upsertRemote(profile: DeviceProfileAdvertisement): void {
    const storedProfile: DeviceProfileAdvertisement =
      cloneProfile(profile);

    const previous: DirectoryEntry | undefined =
      this.remotes.get(storedProfile.deviceId);

    const advertisedAtMs: number =
      storedProfile.advertisedAtMs;

    const snapshot: DeviceRuntimeSnapshot = {
      deviceId: storedProfile.deviceId,
      deviceAlias: storedProfile.deviceAlias,
      isLocal: false,
      state: storedProfile.indexState === 'READY'
        ? 'READY'
        : 'BUSY',
      profileVersion: storedProfile.profileVersion,
      indexVersion: storedProfile.indexVersion,
      lastSeenAtMs: advertisedAtMs,
      averageRttMs: 0,
      load: 0,
      advertisedAtMs: advertisedAtMs
    };

    this.remotes.set(storedProfile.deviceId, {
      snapshot: snapshot,
      profile: storedProfile,
      controlState: previous === undefined
        ? 'DISCONNECTED'
        : previous.controlState,
      dataState: previous === undefined
        ? 'DISCONNECTED'
        : previous.dataState,
      endpointVersion: previous === undefined
        ? 0
        : previous.endpointVersion,
      lastFailureCode: previous === undefined
        ? ''
        : previous.lastFailureCode
    });
  }

  clearRemote(): void {
    this.remotes.clear();
  }

  removeRemote(deviceId: string): void {
    this.remotes.delete(deviceId);
  }

  pruneExpired(): string[] {
    const removed: string[] = [];

    for (const deviceId of this.remotes.keys()) {
      const entry: DirectoryEntry | undefined =
        this.remotes.get(deviceId);

      if (entry === undefined) {
        continue;
      }

      if (!this.isRemoteFresh(entry)) {
        this.remotes.delete(deviceId);
        removed.push(deviceId);
      }
    }

    removed.sort();
    return removed;
  }

  snapshot(): DeviceRuntimeSnapshot[] {
    const result: DeviceRuntimeSnapshot[] = [];

    if (this.local !== null) {
      result.push(cloneSnapshot(this.local.snapshot));
    }

    const remotes: DirectoryEntry[] =
      this.sortedRemotes();

    for (const remote of remotes) {
      if (this.isRemoteFresh(remote)) {
        result.push(cloneSnapshot(remote.snapshot));
      }
    }

    return result;
  }

  candidates(): DeviceRoutingCandidate[] {
    const result: DeviceRoutingCandidate[] = [];

    if (this.local !== null) {
      result.push({
        snapshot: cloneSnapshot(this.local.snapshot),
        profile: cloneProfile(this.local.profile)
      });
    }

    for (const remote of this.sortedRemotes()) {
      if (this.isRemoteFresh(remote)) {
        result.push({
          snapshot: cloneSnapshot(remote.snapshot),
          profile: cloneProfile(remote.profile)
        });
      }
    }

    return result;
  }

  private sortedRemotes(): DirectoryEntry[] {
    const result: DirectoryEntry[] = [];

    for (const entry of this.remotes.values()) {
      result.push(entry);
    }

    result.sort(
      (
        left: DirectoryEntry,
        right: DirectoryEntry
      ): number => {
        if (left.snapshot.deviceId <
          right.snapshot.deviceId) {
          return -1;
        }

        if (left.snapshot.deviceId >
          right.snapshot.deviceId) {
          return 1;
        }

        return 0;
      }
    );

    return result;
  }

  private isRemoteFresh(entry: DirectoryEntry): boolean {
    const ttlMs: number =
      entry.profile.ttlMs > 0
        ? entry.profile.ttlMs
        : REMOTE_PROFILE_TTL_MS;

    return this.clock() -
      entry.profile.advertisedAtMs <= ttlMs;
  }
}