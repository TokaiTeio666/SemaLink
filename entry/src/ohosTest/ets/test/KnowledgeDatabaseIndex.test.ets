import { relationalStore } from '@kit.ArkData';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeDatabase } from '../../../main/ets/knowledge/storage/KnowledgeDatabase';

const V1_DOCUMENTS: string = 'CREATE TABLE documents (' +
  'document_id TEXT PRIMARY KEY, title TEXT NOT NULL, modality TEXT NOT NULL, normalized_text TEXT NOT NULL, ' +
  'tags_json TEXT NOT NULL, checksum TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)';
const V1_CHUNKS: string = 'CREATE TABLE document_chunks (' +
  'chunk_id TEXT PRIMARY KEY, document_id TEXT NOT NULL, chunk_index INTEGER NOT NULL, chunk_text TEXT NOT NULL, ' +
  'summary TEXT NOT NULL, keywords_json TEXT NOT NULL, start_offset INTEGER NOT NULL, end_offset INTEGER NOT NULL, ' +
  'updated_at INTEGER NOT NULL)';

async function readIndexColumns(store: relationalStore.RdbStore, indexName: string): Promise<string[]> {
  let sql = '';
  if (indexName === 'idx_chunks_document') sql = 'PRAGMA index_info(idx_chunks_document)';
  if (indexName === 'idx_documents_filters') sql = 'PRAGMA index_info(idx_documents_filters)';
  const columns: string[] = [];
  const result = await store.querySql(sql);
  try {
    while (result.goToNextRow()) columns.push(result.getString(2));
    return columns;
  } finally {
    result.close();
  }
}

async function expectSupportIndexes(database: KnowledgeDatabase): Promise<void> {
  expect(JSON.stringify(await readIndexColumns(database.getStore(), 'idx_chunks_document')))
    .assertEqual(JSON.stringify(['document_id', 'chunk_index', 'chunk_id']));
  expect(JSON.stringify(await readIndexColumns(database.getStore(), 'idx_documents_filters')))
    .assertEqual(JSON.stringify(['privacy_level', 'modality', 'updated_at', 'document_id']));
}

export default function knowledgeDatabaseIndexTest(): void {
  describe('KnowledgeDatabaseIndex', () => {
    it('creates exact support indexes for a fresh database', 0, async () => {
      const context = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const storeName = 'semalink_index_fresh_' + Date.now().toString() + '.db';
      const database = new KnowledgeDatabase(storeName);
      try {
        await database.initialize(context);
        await expectSupportIndexes(database);
      } finally {
        database.close();
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });

    it('repairs support indexes when reopening an existing valid v2 database', 0, async () => {
      const context = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const storeName = 'semalink_index_v2_' + Date.now().toString() + '.db';
      const first = new KnowledgeDatabase(storeName);
      const reopened = new KnowledgeDatabase(storeName);
      try {
        await first.initialize(context);
        await first.getStore().executeSql('DROP INDEX idx_chunks_document');
        await first.getStore().executeSql('DROP INDEX idx_documents_filters');
        first.close();
        await reopened.initialize(context);
        await expectSupportIndexes(reopened);
      } finally {
        reopened.close();
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });

    it('creates support indexes after v1 to v2 migration', 0, async () => {
      const context = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const storeName = 'semalink_index_v1_' + Date.now().toString() + '.db';
      const database = new KnowledgeDatabase(storeName);
      try {
        const legacy = await relationalStore.getRdbStore(context, {
          name: storeName, securityLevel: relationalStore.SecurityLevel.S1
        });
        await legacy.executeSql(V1_DOCUMENTS);
        await legacy.executeSql(V1_CHUNKS);
        legacy.version = 1;
        legacy.close();
        await database.initialize(context);
        await expectSupportIndexes(database);
      } finally {
        database.close();
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });

    it('keeps support indexes idempotent across repeated initialize calls', 0, async () => {
      const context = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const storeName = 'semalink_index_repeat_' + Date.now().toString() + '.db';
      const database = new KnowledgeDatabase(storeName);
      try {
        await database.initialize(context);
        await database.initialize(context);
        await expectSupportIndexes(database);
      } finally {
        database.close();
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });
  });
}
