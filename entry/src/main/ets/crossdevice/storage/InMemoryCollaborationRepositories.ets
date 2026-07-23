import {
  CollaborationPeer,
  LocalCollaborationIdentity,
  RemoteAccessRecord,
  RemoteKnowledgeProfile
} from '../model/CollaborationModels';
import { SharingPolicy } from '../model/SharingPolicy';
import {
  CollaborationPeerRepository,
  LocalCollaborationIdentityRepository,
  RemoteAccessRecordRepository,
  RemoteKnowledgeProfileRepository,
  SharingPolicyRepository
} from './CollaborationRepositories';

export class InMemoryLocalCollaborationIdentityRepository
implements LocalCollaborationIdentityRepository {
  private value: LocalCollaborationIdentity | undefined = undefined;

  load(): Promise<LocalCollaborationIdentity | undefined> {
    return Promise.resolve(this.value);
  }

  save(identity: LocalCollaborationIdentity): Promise<void> {
    this.value = identity;
    return Promise.resolve();
  }
}

export class InMemoryCollaborationPeerRepository implements CollaborationPeerRepository {
  private readonly values: Map<string, CollaborationPeer> = new Map<string, CollaborationPeer>();

  list(): Promise<CollaborationPeer[]> {
    const result: CollaborationPeer[] = Array.from(this.values.values());
    result.sort((left: CollaborationPeer, right: CollaborationPeer): number =>
      left.peerKey.localeCompare(right.peerKey));
    return Promise.resolve(result);
  }

  get(peerKey: string): Promise<CollaborationPeer | undefined> {
    return Promise.resolve(this.values.get(peerKey));
  }

  save(peer: CollaborationPeer): Promise<void> {
    this.values.set(peer.peerKey, peer);
    return Promise.resolve();
  }
}

export class InMemoryRemoteKnowledgeProfileRepository
implements RemoteKnowledgeProfileRepository {
  private readonly values: Map<string, RemoteKnowledgeProfile> =
    new Map<string, RemoteKnowledgeProfile>();

  listFresh(nowMs: number): Promise<RemoteKnowledgeProfile[]> {
    const result: RemoteKnowledgeProfile[] = [];
    for (const profile of this.values.values()) {
      if (profile.expiresAtMs >= nowMs) {
        result.push(profile);
      }
    }
    result.sort((left: RemoteKnowledgeProfile, right: RemoteKnowledgeProfile): number =>
      left.peerKey.localeCompare(right.peerKey));
    return Promise.resolve(result);
  }

  get(peerKey: string): Promise<RemoteKnowledgeProfile | undefined> {
    return Promise.resolve(this.values.get(peerKey));
  }

  save(profile: RemoteKnowledgeProfile): Promise<void> {
    this.values.set(profile.peerKey, profile);
    return Promise.resolve();
  }

  deleteExpired(nowMs: number): Promise<void> {
    for (const peerKey of this.values.keys()) {
      const profile: RemoteKnowledgeProfile | undefined = this.values.get(peerKey);
      if (profile !== undefined && profile.expiresAtMs < nowMs) {
        this.values.delete(peerKey);
      }
    }
    return Promise.resolve();
  }
}

export class InMemorySharingPolicyRepository implements SharingPolicyRepository {
  private value: SharingPolicy | undefined = undefined;
  private readonly clock: () => number;

  constructor(clock: () => number = (): number => Date.now()) {
    this.clock = clock;
  }

  load(): Promise<SharingPolicy> {
    return Promise.resolve(this.value ?? SharingPolicy.defaults(this.clock()));
  }

  save(policy: SharingPolicy): Promise<void> {
    this.value = policy;
    return Promise.resolve();
  }
}

export class InMemoryRemoteAccessRecordRepository implements RemoteAccessRecordRepository {
  private readonly values: RemoteAccessRecord[] = [];

  listRecent(limit: number): Promise<RemoteAccessRecord[]> {
    const safeLimit: number = Math.max(0, Math.min(128, limit));
    const sorted: RemoteAccessRecord[] = this.values.slice().sort(
      (left: RemoteAccessRecord, right: RemoteAccessRecord): number =>
        right.startedAtMs - left.startedAtMs || left.recordId.localeCompare(right.recordId)
    );
    return Promise.resolve(sorted.slice(0, safeLimit));
  }

  save(record: RemoteAccessRecord): Promise<void> {
    const existing: number = this.values.findIndex(
      (item: RemoteAccessRecord): boolean => item.recordId === record.recordId
    );
    if (existing >= 0) {
      this.values[existing] = record;
    } else {
      this.values.push(record);
    }
    if (this.values.length > 128) {
      this.values.sort((left: RemoteAccessRecord, right: RemoteAccessRecord): number =>
        right.startedAtMs - left.startedAtMs || left.recordId.localeCompare(right.recordId));
      this.values.splice(128);
    }
    return Promise.resolve();
  }
}

export class InMemoryCollaborationRepositories {
  readonly identity: InMemoryLocalCollaborationIdentityRepository =
    new InMemoryLocalCollaborationIdentityRepository();
  readonly peers: InMemoryCollaborationPeerRepository =
    new InMemoryCollaborationPeerRepository();
  readonly profiles: InMemoryRemoteKnowledgeProfileRepository =
    new InMemoryRemoteKnowledgeProfileRepository();
  readonly sharingPolicy: InMemorySharingPolicyRepository =
    new InMemorySharingPolicyRepository();
  readonly accessRecords: InMemoryRemoteAccessRecordRepository =
    new InMemoryRemoteAccessRecordRepository();
}
