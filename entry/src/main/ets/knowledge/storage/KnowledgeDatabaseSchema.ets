import { KnowledgeError } from '../../contracts/knowledge/KnowledgeError';
import { PrivacyLevel } from '../../contracts/semantic/SemanticModels';

export const KNOWLEDGE_DATABASE_VERSION: number = 2;
export const CREATE_DOCUMENTS_V2: string = 'CREATE TABLE IF NOT EXISTS documents (' +
  'document_id TEXT PRIMARY KEY, title TEXT NOT NULL, modality TEXT NOT NULL, normalized_text TEXT NOT NULL, ' +
  "tags_json TEXT NOT NULL, checksum TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, " +
  "privacy_level TEXT NOT NULL DEFAULT 'PRIVATE_GROUP')";
export const ADD_DOCUMENT_PRIVACY_LEVEL: string =
  "ALTER TABLE documents ADD COLUMN privacy_level TEXT NOT NULL DEFAULT 'PRIVATE_GROUP'";

export function migrationStatements(fromVersion: number, privacyColumnExists: boolean): string[] {
  if (fromVersion === 1) {
    return privacyColumnExists ? [] : [ADD_DOCUMENT_PRIVACY_LEVEL];
  }
  if (fromVersion === 0) {
    return privacyColumnExists ? [] : [ADD_DOCUMENT_PRIVACY_LEVEL];
  }
  if (fromVersion === KNOWLEDGE_DATABASE_VERSION) {
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
