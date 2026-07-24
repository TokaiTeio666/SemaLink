import {
  CollaborationPeer,
  LocalCollaborationIdentity,
  RemoteAccessRecord,
  RemoteKnowledgeProfile
} from '../model/CollaborationModels';
import { SharingPolicy } from '../model/SharingPolicy';

export interface LocalCollaborationIdentityRepository {
  load(): Promise<LocalCollaborationIdentity | undefined>;
  save(identity: LocalCollaborationIdentity): Promise<void>;
}

export interface CollaborationPeerRepository {
  list(): Promise<CollaborationPeer[]>;
  get(peerKey: string): Promise<CollaborationPeer | undefined>;
  save(peer: CollaborationPeer): Promise<void>;
}

export interface RemoteKnowledgeProfileRepository {
  listFresh(nowMs: number): Promise<RemoteKnowledgeProfile[]>;
  get(peerKey: string): Promise<RemoteKnowledgeProfile | undefined>;
  save(profile: RemoteKnowledgeProfile): Promise<void>;
  deleteExpired(nowMs: number): Promise<void>;
}

export interface SharingPolicyRepository {
  load(): Promise<SharingPolicy>;
  save(policy: SharingPolicy): Promise<void>;
}

export interface RemoteAccessRecordRepository {
  listRecent(limit: number): Promise<RemoteAccessRecord[]>;
  save(record: RemoteAccessRecord): Promise<void>;
}
