import { relationalStore } from '@kit.ArkData';
import { EvidenceLevel } from '../../contracts/semantic/SemanticModels';
import { KnowledgeDatabase } from '../../knowledge/storage/KnowledgeDatabase';
import {
  CollaborationPeer,
  LocalCollaborationIdentity,
  PeerOnlineState,
  PeerTrustState,
  RemoteAccessDirection,
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

const IDENTITY_KEY: string = 'local';
const POLICY_KEY: string = 'default';

function parseStringArray(text: string): string[] {
  const parsed: Object = JSON.parse(text) as Object;
  if (!Array.isArray(parsed)) {
    throw new Error('INVALID_STORED_COLLABORATION_DATA');
  }
  const values: string[] = parsed as string[];
  if (values.some((value: string): boolean => typeof value !== 'string')) {
    throw new Error('INVALID_STORED_COLLABORATION_DATA');
  }
  return values;
}

function parseLevels(text: string): EvidenceLevel[] {
  const values: string[] = parseStringArray(text);
  if (values.some((value: string): boolean => value !== 'L1' && value !== 'L2')) {
    throw new Error('INVALID_STORED_COLLABORATION_DATA');
  }
  return values as EvidenceLevel[];
}

async function transactional(database: KnowledgeDatabase,
  operation: () => Promise<void>): Promise<void> {
  await database.runSerializedTransaction(operation);
}

export class RdbLocalCollaborationIdentityRepository
implements LocalCollaborationIdentityRepository {
  private readonly database: KnowledgeDatabase;
  constructor(database: KnowledgeDatabase) {
    this.database = database;
  }

  async load(): Promise<LocalCollaborationIdentity | undefined> {
    const result = await this.database.getStore().querySql(
      'SELECT app_instance_id,device_alias,created_at,updated_at,revision ' +
      'FROM local_collaboration_identity WHERE identity_key=?',
      [IDENTITY_KEY]
    );
    try {
      if (!result.goToNextRow()) {
        return undefined;
      }
      return new LocalCollaborationIdentity(
        result.getString(0), result.getString(1), result.getLong(2),
        result.getLong(3), result.getLong(4)
      );
    } finally {
      result.close();
    }
  }

  async save(identity: LocalCollaborationIdentity): Promise<void> {
    const store = this.database.getStore();
    await transactional(this.database, async (): Promise<void> => {
      await store.executeSql(
        'INSERT OR REPLACE INTO local_collaboration_identity ' +
        '(identity_key,app_instance_id,device_alias,created_at,updated_at,revision) ' +
        'VALUES (?,?,?,?,?,?)',
        [IDENTITY_KEY, identity.appInstanceId, identity.deviceAlias,
          identity.createdAtMs, identity.updatedAtMs, identity.revision]
      );
    });
  }
}

export class RdbCollaborationPeerRepository implements CollaborationPeerRepository {
  private readonly database: KnowledgeDatabase;
  constructor(database: KnowledgeDatabase) {
    this.database = database;
  }

  async list(): Promise<CollaborationPeer[]> {
    const result = await this.database.getStore().querySql(
      'SELECT peer_key,device_alias,trust_state,online_state,last_seen_at,' +
      'profile_version,profile_digest,created_at,updated_at ' +
      'FROM collaboration_peers ORDER BY peer_key'
    );
    const peers: CollaborationPeer[] = [];
    try {
      while (result.goToNextRow()) {
        peers.push(this.read(result));
      }
      return peers;
    } finally {
      result.close();
    }
  }

  async get(peerKey: string): Promise<CollaborationPeer | undefined> {
    const result = await this.database.getStore().querySql(
      'SELECT peer_key,device_alias,trust_state,online_state,last_seen_at,' +
      'profile_version,profile_digest,created_at,updated_at ' +
      'FROM collaboration_peers WHERE peer_key=?',
      [peerKey]
    );
    try {
      return result.goToNextRow() ? this.read(result) : undefined;
    } finally {
      result.close();
    }
  }

  async save(peer: CollaborationPeer): Promise<void> {
    const store = this.database.getStore();
    await transactional(this.database, async (): Promise<void> => {
      await store.executeSql(
        'INSERT OR REPLACE INTO collaboration_peers ' +
        '(peer_key,device_alias,trust_state,online_state,last_seen_at,profile_version,' +
        'profile_digest,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)',
        [peer.peerKey, peer.deviceAlias, peer.trustState, peer.onlineState,
          peer.lastSeenAtMs, peer.profileVersion, peer.profileDigest,
          peer.createdAtMs, peer.updatedAtMs]
      );
    });
  }

  private read(result: relationalStore.ResultSet): CollaborationPeer {
    return new CollaborationPeer(
      result.getString(0),
      result.getString(1),
      result.getString(2) as PeerTrustState,
      result.getString(3) as PeerOnlineState,
      result.getLong(4),
      result.getString(5),
      result.getString(6),
      result.getLong(7),
      result.getLong(8)
    );
  }
}

export class RdbRemoteKnowledgeProfileRepository
implements RemoteKnowledgeProfileRepository {
  private readonly database: KnowledgeDatabase;
  constructor(database: KnowledgeDatabase) {
    this.database = database;
  }

  async listFresh(nowMs: number): Promise<RemoteKnowledgeProfile[]> {
    const result = await this.database.getStore().querySql(
      'SELECT peer_key,profile_version,profile_digest,index_state,knowledge_domains_json,' +
      'document_count,chunk_count,retrieval_modes_json,supported_levels_json,updated_at,' +
      'received_at,expires_at FROM remote_knowledge_profiles ' +
      'WHERE expires_at>=? ORDER BY peer_key',
      [nowMs]
    );
    const profiles: RemoteKnowledgeProfile[] = [];
    try {
      while (result.goToNextRow()) {
        profiles.push(this.read(result));
      }
      return profiles;
    } finally {
      result.close();
    }
  }

  async get(peerKey: string): Promise<RemoteKnowledgeProfile | undefined> {
    const result = await this.database.getStore().querySql(
      'SELECT peer_key,profile_version,profile_digest,index_state,knowledge_domains_json,' +
      'document_count,chunk_count,retrieval_modes_json,supported_levels_json,updated_at,' +
      'received_at,expires_at FROM remote_knowledge_profiles WHERE peer_key=?',
      [peerKey]
    );
    try {
      return result.goToNextRow() ? this.read(result) : undefined;
    } finally {
      result.close();
    }
  }

  async save(profile: RemoteKnowledgeProfile): Promise<void> {
    const store = this.database.getStore();
    await transactional(this.database, async (): Promise<void> => {
      await store.executeSql(
        'INSERT OR REPLACE INTO remote_knowledge_profiles ' +
        '(peer_key,profile_version,profile_digest,index_state,knowledge_domains_json,' +
        'document_count,chunk_count,retrieval_modes_json,supported_levels_json,updated_at,' +
        'received_at,expires_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
        [profile.peerKey, profile.profileVersion, profile.profileDigest, profile.indexState,
          JSON.stringify(profile.knowledgeDomains), profile.documentCount, profile.chunkCount,
          JSON.stringify(profile.retrievalModes), JSON.stringify(profile.supportedLevels),
          profile.updatedAtMs, profile.receivedAtMs, profile.expiresAtMs]
      );
    });
  }

  async deleteExpired(nowMs: number): Promise<void> {
    const store = this.database.getStore();
    await transactional(this.database, async (): Promise<void> => {
      await store.executeSql(
        'DELETE FROM remote_knowledge_profiles WHERE expires_at<?',
        [nowMs]
      );
    });
  }

  private read(result: relationalStore.ResultSet): RemoteKnowledgeProfile {
    return new RemoteKnowledgeProfile(
      result.getString(0), result.getString(1), result.getString(2),
      result.getString(3) as 'NOT_READY' | 'INDEXING' | 'READY',
      parseStringArray(result.getString(4)), result.getLong(5), result.getLong(6),
      parseStringArray(result.getString(7)), parseLevels(result.getString(8)),
      result.getLong(9), result.getLong(10), result.getLong(11)
    );
  }
}

export class RdbSharingPolicyRepository implements SharingPolicyRepository {
  private readonly database: KnowledgeDatabase;
  private readonly clock: () => number;
  constructor(database: KnowledgeDatabase, clock: () => number = (): number => Date.now()) {
    this.database = database;
    this.clock = clock;
  }

  async load(): Promise<SharingPolicy> {
    const result = await this.database.getStore().querySql(
      'SELECT enabled,require_trusted_peer,allowed_levels_json,max_evidence_count,' +
      'max_snippet_chars,allowed_domains_json,denied_domains_json,updated_at,revision ' +
      'FROM sharing_policy WHERE policy_key=?',
      [POLICY_KEY]
    );
    try {
      if (!result.goToNextRow()) {
        return SharingPolicy.defaults(this.clock());
      }
      return new SharingPolicy(
        result.getLong(0) === 1,
        result.getLong(1) === 1,
        parseLevels(result.getString(2)),
        result.getLong(3),
        result.getLong(4),
        parseStringArray(result.getString(5)),
        parseStringArray(result.getString(6)),
        result.getLong(7),
        result.getLong(8)
      );
    } finally {
      result.close();
    }
  }

  async save(policy: SharingPolicy): Promise<void> {
    const store = this.database.getStore();
    await transactional(this.database, async (): Promise<void> => {
      await store.executeSql(
        'INSERT OR REPLACE INTO sharing_policy ' +
        '(policy_key,enabled,require_trusted_peer,allowed_levels_json,max_evidence_count,' +
        'max_snippet_chars,allowed_domains_json,denied_domains_json,updated_at,revision) ' +
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [POLICY_KEY, policy.enabled ? 1 : 0, policy.requireTrustedPeer ? 1 : 0,
          JSON.stringify(policy.allowedLevels), policy.maxEvidenceCount,
          policy.maxSnippetChars, JSON.stringify(policy.allowedDomains),
          JSON.stringify(policy.deniedDomains), policy.updatedAtMs, policy.revision]
      );
    });
  }
}

export class RdbRemoteAccessRecordRepository implements RemoteAccessRecordRepository {
  private readonly database: KnowledgeDatabase;
  constructor(database: KnowledgeDatabase) {
    this.database = database;
  }

  async listRecent(limit: number): Promise<RemoteAccessRecord[]> {
    const safeLimit: number = Math.max(0, Math.min(128, Math.floor(limit)));
    const result = await this.database.getStore().querySql(
      'SELECT record_id,direction,peer_key,task_id,domain_summary,requested_level,' +
      'evidence_count,status,started_at,completed_at FROM remote_access_records ' +
      'ORDER BY started_at DESC,record_id LIMIT ?',
      [safeLimit]
    );
    const records: RemoteAccessRecord[] = [];
    try {
      while (result.goToNextRow()) {
        records.push(new RemoteAccessRecord(
          result.getString(0),
          result.getString(1) as RemoteAccessDirection,
          result.getString(2),
          result.getString(3),
          result.getString(4),
          result.getString(5) as EvidenceLevel,
          result.getLong(6),
          result.getString(7),
          result.getLong(8),
          result.getLong(9)
        ));
      }
      return records;
    } finally {
      result.close();
    }
  }

  async save(record: RemoteAccessRecord): Promise<void> {
    const store = this.database.getStore();
    await transactional(this.database, async (): Promise<void> => {
      await store.executeSql(
        'INSERT OR REPLACE INTO remote_access_records ' +
        '(record_id,direction,peer_key,task_id,domain_summary,requested_level,' +
        'evidence_count,status,started_at,completed_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
        [record.recordId, record.direction, record.peerKey, record.taskId,
          record.domainSummary, record.requestedLevel, record.evidenceCount,
          record.status, record.startedAtMs, record.completedAtMs]
      );
      await store.executeSql(
        'DELETE FROM remote_access_records WHERE record_id NOT IN ' +
        '(SELECT record_id FROM remote_access_records ORDER BY started_at DESC,record_id LIMIT 128)'
      );
    });
  }
}
