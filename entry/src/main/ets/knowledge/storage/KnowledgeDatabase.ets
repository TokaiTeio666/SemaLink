import { Context } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { KnowledgeError } from '../../contracts/knowledge/KnowledgeError';

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'semalink_knowledge.db',
  securityLevel: relationalStore.SecurityLevel.S1
};

const CREATE_DOCUMENTS: string = 'CREATE TABLE IF NOT EXISTS documents (' +
  'document_id TEXT PRIMARY KEY, title TEXT NOT NULL, modality TEXT NOT NULL, normalized_text TEXT NOT NULL, ' +
  'tags_json TEXT NOT NULL, checksum TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)';
const CREATE_CHUNKS: string = 'CREATE TABLE IF NOT EXISTS document_chunks (' +
  'chunk_id TEXT PRIMARY KEY, document_id TEXT NOT NULL, chunk_index INTEGER NOT NULL, chunk_text TEXT NOT NULL, ' +
  'summary TEXT NOT NULL, keywords_json TEXT NOT NULL, start_offset INTEGER NOT NULL, end_offset INTEGER NOT NULL, ' +
  'updated_at INTEGER NOT NULL)';
const CREATE_METADATA: string = 'CREATE TABLE IF NOT EXISTS knowledge_metadata (' +
  'metadata_key TEXT PRIMARY KEY, metadata_value TEXT NOT NULL)';

export class KnowledgeDatabase {
  private store?: relationalStore.RdbStore;

  async initialize(context: Context): Promise<void> {
    let stage: string = 'open';
    try {
      const store = await relationalStore.getRdbStore(context, STORE_CONFIG);
      stage = 'schema';
      await store.executeSql(CREATE_DOCUMENTS);
      await store.executeSql(CREATE_CHUNKS);
      await store.executeSql(CREATE_METADATA);
      await store.executeSql("INSERT OR IGNORE INTO knowledge_metadata(metadata_key, metadata_value) VALUES ('index_state','EMPTY')");
      await store.executeSql("INSERT OR IGNORE INTO knowledge_metadata(metadata_key, metadata_value) VALUES ('index_version','index-empty')");
      await store.executeSql("INSERT OR IGNORE INTO knowledge_metadata(metadata_key, metadata_value) VALUES ('profile_version','profile-empty')");
      await store.executeSql("INSERT OR IGNORE INTO knowledge_metadata(metadata_key, metadata_value) VALUES ('last_imported_at','0')");
      stage = 'version';
      store.version = 1;
      this.store = store;
    } catch (error) {
      throw new KnowledgeError('E_RETRIEVAL_FAILED',
        'Unable to initialize the local knowledge database at ' + stage, true);
    }
  }

  getStore(): relationalStore.RdbStore {
    if (this.store === undefined) {
      throw new KnowledgeError('E_INDEX_NOT_READY', 'Local knowledge database is not initialized', true);
    }
    return this.store;
  }
}
