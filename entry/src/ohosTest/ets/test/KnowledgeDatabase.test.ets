import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeDatabase } from '../../../main/ets/knowledge/storage/KnowledgeDatabase';
import { RdbDocumentRepository } from '../../../main/ets/knowledge/storage/RdbDocumentRepository';
import { DocumentChunker } from '../../../main/ets/knowledge/import/DocumentChunker';
import { KeywordExtractor } from '../../../main/ets/knowledge/import/KeywordExtractor';
import { RawFileDocumentImporter } from '../../../main/ets/knowledge/import/RawFileDocumentImporter';
import { UserDocumentImporter } from '../../../main/ets/knowledge/import/UserDocumentImporter';
import { UserTextDocument } from '../../../main/ets/knowledge/import/UriTextContentReader';
import { relationalStore } from '@kit.ArkData';
import { KnowledgeDocument } from '../../../main/ets/knowledge/model/KnowledgeDocument';
import { DocumentChunk } from '../../../main/ets/knowledge/model/DocumentChunk';
import { KnowledgeError } from '../../../main/ets/contracts/knowledge/KnowledgeError';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CREATE_DOCUMENTS_V2 } from '../../../main/ets/knowledge/storage/KnowledgeDatabaseSchema';
import { RepositoryStatistics } from '../../../main/ets/knowledge/storage/DocumentRepository';
import { readChunks, readDocuments } from './support/RdbKnowledgeInspection';

const V1_DOCUMENTS: string = 'CREATE TABLE documents (' +
  'document_id TEXT PRIMARY KEY, title TEXT NOT NULL, modality TEXT NOT NULL, normalized_text TEXT NOT NULL, ' +
  'tags_json TEXT NOT NULL, checksum TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)';
const V1_CHUNKS: string = 'CREATE TABLE document_chunks (' +
  'chunk_id TEXT PRIMARY KEY, document_id TEXT NOT NULL, chunk_index INTEGER NOT NULL, chunk_text TEXT NOT NULL, ' +
  'summary TEXT NOT NULL, keywords_json TEXT NOT NULL, start_offset INTEGER NOT NULL, end_offset INTEGER NOT NULL, ' +
  'updated_at INTEGER NOT NULL)';

async function capturedKnowledgeError(action: () => Promise<void>): Promise<KnowledgeError | undefined> {
  try {
    await action();
  } catch (error) {
    if (error instanceof KnowledgeError) {
      return error;
    }
  }
  return undefined;
}

async function documentsTableExists(store: relationalStore.RdbStore): Promise<boolean> {
  const result = await store.querySql(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='documents'");
  try {
    return result.goToNextRow();
  } finally {
    result.close();
  }
}

export default function knowledgeDatabaseTest() {
  describe('KnowledgeDatabase', () => {
    it('records the untouched fresh store version and documents presence', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      const storeName = 'semalink_fresh_store_diagnostic_' + Date.now().toString() + '.db';
      try {
        const store = await relationalStore.getRdbStore(context, {
          name: storeName, securityLevel: relationalStore.SecurityLevel.S1
        });
        const initialVersion = store.version;
        const hasDocuments = await documentsTableExists(store);
        hilog.info(0x534C, 'KnowledgeDatabaseDiagnostic',
          'initialVersion=%{public}d documentsExists=%{public}s',
          initialVersion, hasDocuments ? 'true' : 'false');
        store.close();
        expect(hasDocuments).assertFalse();
      } finally {
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });

    it('initializes a fresh unique store to v3 and reuses the initialized connection', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      const storeName = 'semalink_fresh_initialize_' + Date.now().toString() + '.db';
      try {
        const database = new KnowledgeDatabase(storeName);
        await database.initialize(context);
        const firstStore = database.getStore();
        expect(firstStore.version).assertEqual(3);
        await database.initialize(context);
        expect(database.getStore()).assertEqual(firstStore);
        database.close();
      } finally {
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });

    it('rejects a v2 documents table missing required privacy schema without dropping data', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      const storeName = 'semalink_invalid_v2_schema_' + Date.now().toString() + '.db';
      try {
        const invalid = await relationalStore.getRdbStore(context, {
          name: storeName, securityLevel: relationalStore.SecurityLevel.S1
        });
        await invalid.executeSql(V1_DOCUMENTS);
        await invalid.executeSql("INSERT INTO documents VALUES ('kept-doc','Kept','text','kept','[]','kept-sum',1,1)");
        invalid.version = 2;
        invalid.close();

        const database = new KnowledgeDatabase(storeName);
        const failure = await capturedKnowledgeError(async (): Promise<void> => {
          await database.initialize(context);
        });
        expect(failure?.code).assertEqual('E_STORAGE_FAILED');
        const reopened = await relationalStore.getRdbStore(context, {
          name: storeName, securityLevel: relationalStore.SecurityLevel.S1
        });
        const result = await reopened.querySql('SELECT document_id FROM documents');
        try {
          expect(result.goToNextRow()).assertTrue();
          expect(result.getString(0)).assertEqual('kept-doc');
        } finally {
          result.close();
          reopened.close();
        }
      } finally {
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });

    it('rejects a future database version without downgrade and can retry after correction', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      const storeName = 'semalink_future_version_' + Date.now().toString() + '.db';
      try {
        const future = await relationalStore.getRdbStore(context, {
          name: storeName, securityLevel: relationalStore.SecurityLevel.S1
        });
        await future.executeSql(CREATE_DOCUMENTS_V2);
        future.version = 4;
        future.close();

        const database = new KnowledgeDatabase(storeName);
        const failure = await capturedKnowledgeError(async (): Promise<void> => {
          await database.initialize(context);
        });
        expect(failure?.code).assertEqual('E_STORAGE_FAILED');
        const corrected = await relationalStore.getRdbStore(context, {
          name: storeName, securityLevel: relationalStore.SecurityLevel.S1
        });
        expect(corrected.version).assertEqual(3);
        corrected.version = 3;
        corrected.close();
        await database.initialize(context);
        expect(database.getStore().version).assertEqual(3);
        database.close();
      } finally {
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });

    it('initializes idempotently and clears to EMPTY', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      const database = new KnowledgeDatabase();
      await database.initialize(context);
      await database.initialize(context);
      const repository = new RdbDocumentRepository(database);
      await repository.clearAll();
      const statistics = await repository.getStatistics();
      const metadata = await repository.getMetadata();
      expect(statistics.documentCount).assertEqual(0);
      expect(statistics.chunkCount).assertEqual(0);
      expect(metadata.indexState).assertEqual('EMPTY');
    });

    it('keeps lightweight repository statistics deterministic for empty and tagged documents', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      const storeName = 'semalink_statistics_' + Date.now().toString() + '.db';
      const database = new KnowledgeDatabase(storeName);
      try {
        await database.initialize(context);
        const repository = new RdbDocumentRepository(database);
        const emptyExpected: RepositoryStatistics = {
          documentCount: 0, chunkCount: 0, modalities: [], domainCounts: []
        };
        expect(JSON.stringify(await repository.getStatistics())).assertEqual(JSON.stringify(emptyExpected));
        const first: KnowledgeDocument = {
          documentId: 'a-document', title: 'Database', modality: 'pdf', normalizedText: 'database',
          tags: ['数据库', '数据库', 'ACID'], checksum: 'statistics-a', createdAt: 1, updatedAt: 1,
          privacyLevel: 'PRIVATE_GROUP'
        };
        const firstChunk: DocumentChunk = {
          chunkId: 'a-chunk', documentId: first.documentId, chunkIndex: 0, text: 'database', summary: 'database',
          keywords: ['database'], startOffset: 0, endOffset: 8, updatedAt: 1
        };
        const second: KnowledgeDocument = {
          documentId: 'z-document', title: 'Network', modality: 'text', normalizedText: 'network',
          tags: ['数据库', '网络'], checksum: 'statistics-z', createdAt: 2, updatedAt: 2,
          privacyLevel: 'PRIVATE_GROUP'
        };
        await repository.saveDocumentWithChunks(first, [firstChunk]);
        await repository.saveDocumentWithChunks(second, []);
        const populatedExpected: RepositoryStatistics = {
          documentCount: 2, chunkCount: 1, modalities: ['pdf', 'text'],
          domainCounts: [
            { tag: '数据库', documentCount: 3 },
            { tag: 'ACID', documentCount: 1 },
            { tag: '网络', documentCount: 1 }
          ]
        };
        expect(JSON.stringify(await repository.getStatistics())).assertEqual(JSON.stringify(populatedExpected));
      } finally {
        database.close();
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });

    it('imports long built-in and user documents idempotently and persists until clear', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      const database = new KnowledgeDatabase();
      await database.initialize(context);
      const repository = new RdbDocumentRepository(database);
      await repository.clearAll();

      const builtIn = new RawFileDocumentImporter(context.resourceManager, repository, new DocumentChunker());
      const first = await builtIn.importBuiltInDocuments();
      const afterFirst = await repository.getStatistics();
      const builtInDocuments = await readDocuments(database);
      expect(first.importedDocuments >= 12).assertTrue();
      expect(afterFirst.documentCount >= 12).assertTrue();
      expect(afterFirst.chunkCount > afterFirst.documentCount).assertTrue();
      expect(builtInDocuments.every((document): boolean => document.privacyLevel === 'PRIVATE_GROUP')).assertTrue();

      const second = await builtIn.importBuiltInDocuments();
      expect(second.importedDocuments).assertEqual(0);
      expect(second.skippedDocuments >= 12).assertTrue();

      const userDocument: UserTextDocument = {
        displayName: 'device-persistence-test.txt',
        normalizedText: '持久化测试文档包含唯一关键词星河校验，并验证用户文本经过分块后保存在本机知识库。',
        byteSize: 120
      };
      const userImporter = new UserDocumentImporter(repository, new DocumentChunker(), new KeywordExtractor());
      const userReport = await userImporter.importDocuments([userDocument]);
      expect(userReport.importedDocuments).assertEqual(1);

      const reopenedDatabase = new KnowledgeDatabase();
      await reopenedDatabase.initialize(context);
      const reopenedRepository = new RdbDocumentRepository(reopenedDatabase);
      const persisted = await reopenedRepository.getStatistics();
      expect(persisted.documentCount >= 13).assertTrue();
      await reopenedRepository.clearAll();
      const empty = await reopenedRepository.getStatistics();
      expect(empty.documentCount).assertEqual(0);
      expect(empty.chunkCount).assertEqual(0);
    });

    it('migrates a real v1 store to v3 without losing documents or chunks', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      const storeName = 'semalink_knowledge_v1_migration_' + Date.now().toString() + '.db';
      try {
        const v1 = await relationalStore.getRdbStore(context, {
          name: storeName, securityLevel: relationalStore.SecurityLevel.S1
        });
        await v1.executeSql(V1_DOCUMENTS);
        await v1.executeSql(V1_CHUNKS);
        await v1.executeSql("INSERT INTO documents VALUES ('legacy-doc','Legacy','text','legacy text','[]','legacy-sum',1,1)");
        await v1.executeSql("INSERT INTO document_chunks VALUES ('legacy-chunk','legacy-doc',0,'legacy text','legacy','[]',0,11,1)");
        v1.version = 1;
        v1.close();

        const database = new KnowledgeDatabase(storeName);
        await database.initialize(context);
        await database.initialize(context);
        const repository = new RdbDocumentRepository(database);
        const migratedDocuments = await readDocuments(database);
        const migratedChunks = await readChunks(database);
        expect(migratedDocuments.length).assertEqual(1);
        expect(migratedChunks.length).assertEqual(1);
        expect(migratedDocuments[0].privacyLevel).assertEqual('PRIVATE_GROUP');

        const localDocument: KnowledgeDocument = {
          documentId: 'local-doc', title: 'Local', modality: 'text', normalizedText: 'local text', tags: [],
          checksum: 'local-sum', createdAt: 2, updatedAt: 2, privacyLevel: 'LOCAL_ONLY'
        };
        const localChunk: DocumentChunk = {
          chunkId: 'local-chunk', documentId: 'local-doc', chunkIndex: 0, text: 'local text', summary: 'local',
          keywords: [], startOffset: 0, endOffset: 10, updatedAt: 2
        };
        await repository.saveDocumentWithChunks(localDocument, [localChunk]);
        database.close();

        const reopened = new KnowledgeDatabase(storeName);
        await reopened.initialize(context);
        const reopenedRepository = new RdbDocumentRepository(reopened);
        const persisted = await readDocuments(reopened);
        expect(persisted.length).assertEqual(2);
        expect(persisted[0].documentId).assertEqual('legacy-doc');
        expect(persisted[0].privacyLevel).assertEqual('PRIVATE_GROUP');
        expect(persisted[1].documentId).assertEqual('local-doc');
        expect(persisted[1].privacyLevel).assertEqual('LOCAL_ONLY');
        reopened.close();
      } finally {
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });

    it('recovers when a v1 store already has the privacy column from a partial migration', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      const storeName = 'semalink_knowledge_partial_v1_' + Date.now().toString() + '.db';
      try {
        const partial = await relationalStore.getRdbStore(context, {
          name: storeName, securityLevel: relationalStore.SecurityLevel.S1
        });
        await partial.executeSql(V1_DOCUMENTS.replace('updated_at INTEGER NOT NULL)',
          "updated_at INTEGER NOT NULL, privacy_level TEXT NOT NULL DEFAULT 'PRIVATE_GROUP')"));
        await partial.executeSql(V1_CHUNKS);
        await partial.executeSql("INSERT INTO documents VALUES ('partial-doc','Partial','text','text','[]','partial-sum',1,1,'PRIVATE_GROUP')");
        partial.version = 1;
        partial.close();

        const recovered = new KnowledgeDatabase(storeName);
        await recovered.initialize(context);
        expect(recovered.getStore().version).assertEqual(3);
        const documents = await readDocuments(recovered);
        expect(documents.length).assertEqual(1);
        expect(documents[0].privacyLevel).assertEqual('PRIVATE_GROUP');
        recovered.close();
      } finally {
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });

    it('migrates a version zero legacy documents table without dropping its data', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      const storeName = 'semalink_knowledge_v0_migration_' + Date.now().toString() + '.db';
      try {
        const legacy = await relationalStore.getRdbStore(context, {
          name: storeName, securityLevel: relationalStore.SecurityLevel.S1
        });
        await legacy.executeSql(V1_DOCUMENTS);
        await legacy.executeSql(V1_CHUNKS);
        await legacy.executeSql("INSERT INTO documents VALUES ('v0-doc','Legacy v0','text','legacy','[]','v0-sum',1,1)");
        legacy.close();

        const migrated = new KnowledgeDatabase(storeName);
        await migrated.initialize(context);
        expect(migrated.getStore().version).assertEqual(3);
        const documents = await readDocuments(migrated);
        expect(documents.length).assertEqual(1);
        expect(documents[0].documentId).assertEqual('v0-doc');
        expect(documents[0].privacyLevel).assertEqual('PRIVATE_GROUP');
        migrated.close();
      } finally {
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });

    it('maps RDB save read and clear failures to safe storage errors', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      const storeName = 'semalink_knowledge_storage_errors_' + Date.now().toString() + '.db';
      try {
        const database = new KnowledgeDatabase(storeName);
        await database.initialize(context);
        const repository = new RdbDocumentRepository(database);
        const storedDocument: KnowledgeDocument = {
          documentId: 'duplicate-doc', title: 'Duplicate', modality: 'text', normalizedText: 'text', tags: [],
          checksum: 'duplicate-sum', createdAt: 1, updatedAt: 1, privacyLevel: 'PRIVATE_GROUP'
        };
        const storedChunk: DocumentChunk = {
          chunkId: 'duplicate-chunk', documentId: 'duplicate-doc', chunkIndex: 0, text: 'text', summary: 'text',
          keywords: [], startOffset: 0, endOffset: 4, updatedAt: 1
        };
        await repository.saveDocumentWithChunks(storedDocument, [storedChunk]);
        const saveError = await capturedKnowledgeError(async (): Promise<void> => {
          await repository.saveDocumentWithChunks(storedDocument, [storedChunk]);
        });
        expect(saveError?.code).assertEqual('E_STORAGE_FAILED');
        expect(saveError?.message.includes('duplicate-sum')).assertFalse();

        await database.getStore().executeSql(
          "UPDATE documents SET modality='sql_column' WHERE document_id='duplicate-doc'");
        const readError = await capturedKnowledgeError(async (): Promise<void> => {
          await repository.getStatistics();
        });
        expect(readError?.code).assertEqual('E_STORAGE_FAILED');
        expect(readError?.message.toLowerCase().includes('sql')).assertFalse();

        database.close();
        const clearError = await capturedKnowledgeError(async (): Promise<void> => {
          await repository.clearAll();
        });
        expect(clearError?.code).assertEqual('E_STORAGE_FAILED');
        expect(clearError?.message.includes(storeName)).assertFalse();
      } finally {
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });
  });
}
