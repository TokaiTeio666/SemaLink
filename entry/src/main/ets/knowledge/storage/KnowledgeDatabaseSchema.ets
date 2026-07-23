import { KnowledgeError } from '../../contracts/knowledge/KnowledgeError';
import { PrivacyLevel } from '../../contracts/semantic/SemanticModels';

export const KNOWLEDGE_DATABASE_VERSION: number = 3;
export const CREATE_DOCUMENTS_V2: string = 'CREATE TABLE IF NOT EXISTS documents (' +
  'document_id TEXT PRIMARY KEY, title TEXT NOT NULL, modality TEXT NOT NULL, normalized_text TEXT NOT NULL, ' +
  "tags_json TEXT NOT NULL, checksum TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, " +
  "privacy_level TEXT NOT NULL DEFAULT 'PRIVATE_GROUP')";
export const ADD_DOCUMENT_PRIVACY_LEVEL: string =
  "ALTER TABLE documents ADD COLUMN privacy_level TEXT NOT NULL DEFAULT 'PRIVATE_GROUP'";

export const COLLABORATION_SCHEMA_STATEMENTS: string[] = [
  'CREATE TABLE IF NOT EXISTS local_collaboration_identity (' +
    'identity_key TEXT PRIMARY KEY, app_instance_id TEXT NOT NULL, device_alias TEXT NOT NULL, ' +
    'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, revision INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS collaboration_peers (' +
    'peer_key TEXT PRIMARY KEY, device_alias TEXT NOT NULL, trust_state TEXT NOT NULL, ' +
    'online_state TEXT NOT NULL, last_seen_at INTEGER NOT NULL, profile_version TEXT NOT NULL, ' +
    'profile_digest TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS remote_knowledge_profiles (' +
    'peer_key TEXT PRIMARY KEY, profile_version TEXT NOT NULL, profile_digest TEXT NOT NULL, ' +
    'index_state TEXT NOT NULL, knowledge_domains_json TEXT NOT NULL, document_count INTEGER NOT NULL, ' +
    'chunk_count INTEGER NOT NULL, retrieval_modes_json TEXT NOT NULL, supported_levels_json TEXT NOT NULL, ' +
    'updated_at INTEGER NOT NULL, received_at INTEGER NOT NULL, expires_at INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS sharing_policy (' +
    'policy_key TEXT PRIMARY KEY, enabled INTEGER NOT NULL, require_trusted_peer INTEGER NOT NULL, ' +
    'allowed_levels_json TEXT NOT NULL, max_evidence_count INTEGER NOT NULL, max_snippet_chars INTEGER NOT NULL, ' +
    'allowed_domains_json TEXT NOT NULL, denied_domains_json TEXT NOT NULL, updated_at INTEGER NOT NULL, ' +
    'revision INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS remote_access_records (' +
    'record_id TEXT PRIMARY KEY, direction TEXT NOT NULL, peer_key TEXT NOT NULL, task_id TEXT NOT NULL, ' +
    'domain_summary TEXT NOT NULL, requested_level TEXT NOT NULL, evidence_count INTEGER NOT NULL, ' +
    'status TEXT NOT NULL, started_at INTEGER NOT NULL, completed_at INTEGER NOT NULL)'
];

export function migrationStatements(fromVersion: number, privacyColumnExists: boolean): string[] {
  if (fromVersion === 1) {
    return privacyColumnExists ? [] : [ADD_DOCUMENT_PRIVACY_LEVEL];
  }
  if (fromVersion === 0) {
    return privacyColumnExists ? [] : [ADD_DOCUMENT_PRIVACY_LEVEL];
  }
  if (fromVersion === 2 || fromVersion === KNOWLEDGE_DATABASE_VERSION) {
    if (!privacyColumnExists) {
      throw new KnowledgeError('E_STORAGE_FAILED', 'Local knowledge storage schema is invalid', false);
    }
    return [];
  }
  throw new KnowledgeError('E_STORAGE_FAILED', 'Local knowledge storage version is unsupported', false);
}

export function parseStoredPrivacyLevel(value: string): PrivacyLevel {
  if (value === 'LOCAL_ONLY' || value === 'PRIVATE_GROUP') {
    return value;
  }
  throw new KnowledgeError('E_STORAGE_FAILED', 'Stored document privacy level is invalid', false);
}
