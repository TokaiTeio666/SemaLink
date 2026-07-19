import { relationalStore } from '@kit.ArkData';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeError } from '../../../main/ets/contracts/knowledge/KnowledgeError';
import { DocumentChunk } from '../../../main/ets/knowledge/model/DocumentChunk';
import { KnowledgeDocument } from '../../../main/ets/knowledge/model/KnowledgeDocument';
import { KnowledgeDatabase } from '../../../main/ets/knowledge/storage/KnowledgeDatabase';
import { KnowledgeMetadata } from '../../../main/ets/knowledge/storage/DocumentRepository';
import { RdbDocumentRepository } from '../../../main/ets/knowledge/storage/RdbDocumentRepository';
import {
  countChunks,
  countDocuments,
  readMetadataRows,
  StoredMetadataRows
} from './support/RdbKnowledgeInspection';

const READY_METADATA: KnowledgeMetadata = {
  indexState: 'READY', indexVersion: 'index-ready', profileVersion: 'profile-ready', updatedAt: 123
};
const READY_ROWS: StoredMetadataRows = {
  indexState: 'READY', indexVersion: 'index-ready', profileVersion: 'profile-ready', lastImportedAt: '123'
};

function document(): KnowledgeDocument {
  return {
    documentId: 'transaction-doc', title: 'Transaction', modality: 'text', normalizedText: 'transaction',
    tags: ['database'], checksum: 'transaction-checksum', createdAt: 1, updatedAt: 1,
    privacyLevel: 'PRIVATE_GROUP'
  };
}

function chunk(): DocumentChunk {
  return {
    chunkId: 'transaction-chunk', documentId: 'transaction-doc', chunkIndex: 0,
    text: 'transaction isolation', summary: 'transaction', keywords: ['transaction'],
    startOffset: 0, endOffset: 21, updatedAt: 1
  };
}

async function capturedError(action: () => Promise<void>): Promise<KnowledgeError | undefined> {
  try {
    await action();
  } catch (error) {
    if (error instanceof KnowledgeError) return error;
  }
  return undefined;
}

async function seed(repository: RdbDocumentRepository): Promise<void> {
  await repository.saveDocumentWithChunks(document(), [chunk()]);
  await repository.setMetadata(READY_METADATA);
}

export default function rdbDocumentRepositoryTransactionTest(): void {
  describe('RdbDocumentRepositoryTransaction', () => {
    it('clears data and all metadata in one successful operation', 0, async () => {
      const context = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const storeName = 'semalink_clear_success_' + Date.now().toString() + '.db';
      const database = new KnowledgeDatabase(storeName);
      try {
        await database.initialize(context);
        const repository = new RdbDocumentRepository(database);
        await seed(repository);
        await repository.clearAll();
        expect(await countDocuments(database)).assertEqual(0);
        expect(await countChunks(database)).assertEqual(0);
        const rows = await readMetadataRows(database);
        expect(rows.indexState).assertEqual('EMPTY');
        expect(rows.indexVersion).assertEqual('index-empty');
        expect(rows.profileVersion).assertEqual('profile-empty');
      } finally {
        database.close();
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });

    it('rolls back deletes and metadata when clearAll metadata writing fails and survives restart', 0, async () => {
      const context = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const storeName = 'semalink_clear_rollback_' + Date.now().toString() + '.db';
      let database = new KnowledgeDatabase(storeName);
      try {
        await database.initialize(context);
        const repository = new RdbDocumentRepository(database);
        await seed(repository);
        await database.getStore().executeSql(
          "CREATE TRIGGER fail_clear_metadata BEFORE INSERT ON knowledge_metadata " +
          "WHEN NEW.metadata_key='index_state' BEGIN SELECT RAISE(ABORT, 'test_metadata_failure'); END");
        const failure = await capturedError(async (): Promise<void> => { await repository.clearAll(); });
        expect(failure?.code).assertEqual('E_STORAGE_FAILED');
        expect(await countDocuments(database)).assertEqual(1);
        expect(await countChunks(database)).assertEqual(1);
        expect(JSON.stringify(await readMetadataRows(database))).assertEqual(JSON.stringify(READY_ROWS));
        await database.getStore().executeSql('DROP TRIGGER fail_clear_metadata');
        database.close();
        database = new KnowledgeDatabase(storeName);
        await database.initialize(context);
        expect(await countDocuments(database)).assertEqual(1);
        expect(await countChunks(database)).assertEqual(1);
        expect(JSON.stringify(await readMetadataRows(database))).assertEqual(JSON.stringify(READY_ROWS));
      } finally {
        database.close();
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });

    it('rolls back all four metadata values when the third setMetadata write fails', 0, async () => {
      const context = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const storeName = 'semalink_metadata_rollback_' + Date.now().toString() + '.db';
      let database = new KnowledgeDatabase(storeName);
      try {
        await database.initialize(context);
        const repository = new RdbDocumentRepository(database);
        await repository.setMetadata(READY_METADATA);
        await database.getStore().executeSql(
          "CREATE TRIGGER fail_profile_metadata BEFORE INSERT ON knowledge_metadata " +
          "WHEN NEW.metadata_key='profile_version' BEGIN SELECT RAISE(ABORT, 'test_metadata_failure'); END");
        const failure = await capturedError(async (): Promise<void> => {
          await repository.setMetadata({
            indexState: 'ERROR', indexVersion: 'index-new', profileVersion: 'profile-new', updatedAt: 999
          });
        });
        expect(failure?.code).assertEqual('E_STORAGE_FAILED');
        expect(JSON.stringify(await readMetadataRows(database))).assertEqual(JSON.stringify(READY_ROWS));
        await database.getStore().executeSql('DROP TRIGGER fail_profile_metadata');
        database.close();
        database = new KnowledgeDatabase(storeName);
        await database.initialize(context);
        expect(JSON.stringify(await readMetadataRows(database))).assertEqual(JSON.stringify(READY_ROWS));
      } finally {
        database.close();
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });
  });
}
