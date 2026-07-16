import { Context } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KnowledgeError } from '../../contracts/knowledge/KnowledgeError';
import {
  CREATE_DOCUMENTS_V2,
  KNOWLEDGE_DATABASE_VERSION,
  migrationStatements
} from './KnowledgeDatabaseSchema';

const DEFAULT_STORE_NAME: string = 'semalink_knowledge.db';
const DATABASE_LOG_DOMAIN: number = 0x534C;
const DATABASE_LOG_TAG: string = 'KnowledgeDatabase';
type InitializationStage = 'OPEN_STORE' | 'READ_VERSION' | 'BEGIN_TRANSACTION' | 'INSPECT_SCHEMA' |
  'CREATE_FRESH_SCHEMA' | 'ALTER_LEGACY_SCHEMA' | 'CREATE_SUPPORT_TABLES' | 'SET_VERSION' | 'COMMIT' |
  'CLOSE_AFTER_FAILURE';
const CREATE_CHUNKS: string = 'CREATE TABLE IF NOT EXISTS document_chunks (' +
  'chunk_id TEXT PRIMARY KEY, document_id TEXT NOT NULL, chunk_index INTEGER NOT NULL, chunk_text TEXT NOT NULL, ' +
  'summary TEXT NOT NULL, keywords_json TEXT NOT NULL, start_offset INTEGER NOT NULL, end_offset INTEGER NOT NULL, ' +
  'updated_at INTEGER NOT NULL)';
const CREATE_METADATA: string = 'CREATE TABLE IF NOT EXISTS knowledge_metadata (' +
  'metadata_key TEXT PRIMARY KEY, metadata_value TEXT NOT NULL)';

function logStage(stage: InitializationStage): void {
  hilog.info(DATABASE_LOG_DOMAIN, DATABASE_LOG_TAG, '%{public}s', stage);
}

function businessErrorCode(error: Object): number {
  const businessError = error as BusinessError;
  return typeof businessError.code === 'number' ? businessError.code : 0;
}

function logStageFailure(stage: InitializationStage, code: number): void {
  hilog.error(DATABASE_LOG_DOMAIN, DATABASE_LOG_TAG, '%{public}s code=%{public}d', stage, code);
}

async function hasPrivacyLevelColumn(store: relationalStore.RdbStore): Promise<boolean> {
  const result = await store.querySql('PRAGMA table_info(documents)');
  try {
    while (result.goToNextRow()) {
      if (result.getString(1) === 'privacy_level') {
        return true;
      }
    }
    return false;
  } finally {
    result.close();
  }
}

async function hasDocumentsTable(store: relationalStore.RdbStore): Promise<boolean> {
  const result = await store.querySql(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='documents'");
  try {
    return result.goToNextRow();
  } finally {
    result.close();
  }
}

function rollbackAfterFailure(store: relationalStore.RdbStore): void {
  try {
    store.rollBack();
  } catch (error) {
    return;
  }
}

export class KnowledgeDatabase {
  private store?: relationalStore.RdbStore;
  private readonly storeName: string;

  constructor(storeName: string = DEFAULT_STORE_NAME) {
    this.storeName = storeName;
  }

  async initialize(context: Context): Promise<void> {
    if (this.store !== undefined) {
      return;
    }
    let openedStore: relationalStore.RdbStore | undefined = undefined;
    let stage: InitializationStage = 'OPEN_STORE';
    let failureCode: number = 0;
    let transactionStarted: boolean = false;
    try {
      const config: relationalStore.StoreConfig = {
        name: this.storeName,
        securityLevel: relationalStore.SecurityLevel.S1
      };
      logStage(stage);
      const store = await relationalStore.getRdbStore(context, config);
      openedStore = store;
      stage = 'READ_VERSION';
      logStage(stage);
      const currentVersion: number = store.version;
      stage = 'INSPECT_SCHEMA';
      logStage(stage);
      const documentsExist: boolean = await hasDocumentsTable(store);
      const privacyColumnExists: boolean = documentsExist ? await hasPrivacyLevelColumn(store) : false;
      if (currentVersion > KNOWLEDGE_DATABASE_VERSION ||
        (currentVersion < 0 && documentsExist) ||
        (currentVersion === KNOWLEDGE_DATABASE_VERSION && !documentsExist)) {
        throw new KnowledgeError('E_STORAGE_FAILED', 'Local knowledge storage version is unsupported', false);
      }
      const statements: string[] = documentsExist ?
        migrationStatements(currentVersion, privacyColumnExists) : [];
      stage = 'BEGIN_TRANSACTION';
      logStage(stage);
      store.beginTransaction();
      transactionStarted = true;
      try {
        if (!documentsExist) {
          stage = 'CREATE_FRESH_SCHEMA';
          logStage(stage);
          await store.executeSql(CREATE_DOCUMENTS_V2);
        }
        if (statements.length > 0) {
          stage = 'ALTER_LEGACY_SCHEMA';
          logStage(stage);
        }
        for (const statement of statements) {
          await store.executeSql(statement);
        }
        stage = 'CREATE_SUPPORT_TABLES';
        logStage(stage);
        await store.executeSql(CREATE_CHUNKS);
        await store.executeSql(CREATE_METADATA);
        await store.executeSql("INSERT OR IGNORE INTO knowledge_metadata(metadata_key, metadata_value) VALUES ('index_state','EMPTY')");
        await store.executeSql("INSERT OR IGNORE INTO knowledge_metadata(metadata_key, metadata_value) VALUES ('index_version','index-empty')");
        await store.executeSql("INSERT OR IGNORE INTO knowledge_metadata(metadata_key, metadata_value) VALUES ('profile_version','profile-empty')");
        await store.executeSql("INSERT OR IGNORE INTO knowledge_metadata(metadata_key, metadata_value) VALUES ('last_imported_at','0')");
        stage = 'SET_VERSION';
        logStage(stage);
        store.version = KNOWLEDGE_DATABASE_VERSION;
        stage = 'COMMIT';
        logStage(stage);
        store.commit();
        transactionStarted = false;
      } catch (schemaError) {
        failureCode = businessErrorCode(schemaError);
        rollbackAfterFailure(store);
        transactionStarted = false;
        throw new KnowledgeError('E_STORAGE_FAILED', 'Unable to initialize local knowledge storage', true);
      }
      this.store = store;
    } catch (error) {
      if (failureCode === 0) {
        failureCode = businessErrorCode(error);
      }
      logStageFailure(stage, failureCode);
      if (transactionStarted && openedStore !== undefined) {
        rollbackAfterFailure(openedStore);
      }
      if (openedStore !== undefined) {
        try {
          stage = 'CLOSE_AFTER_FAILURE';
          logStage(stage);
          openedStore.close();
        } catch (closeError) {
          logStageFailure(stage, businessErrorCode(closeError));
        }
      }
      throw new KnowledgeError('E_STORAGE_FAILED', 'Unable to initialize local knowledge storage', true);
    }
  }

  getStore(): relationalStore.RdbStore {
    if (this.store === undefined) {
      throw new KnowledgeError('E_INDEX_NOT_READY', 'Local knowledge database is not initialized', true);
    }
    return this.store;
  }

  close(): void {
    if (this.store === undefined) {
      return;
    }
    const store = this.store;
    this.store = undefined;
    try {
      store.close();
    } catch (error) {
      throw new KnowledgeError('E_STORAGE_FAILED', 'Unable to close local knowledge storage', true);
    }
  }
}
