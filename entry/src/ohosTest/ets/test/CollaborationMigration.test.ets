import { abilityDelegatorRegistry } from '@kit.TestKit';
import { relationalStore } from '@kit.ArkData';
import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeDatabase } from
  '../../../main/ets/knowledge/storage/KnowledgeDatabase';

export default function collaborationMigrationTest(): void {
  describe('CollaborationMigration', () => {
    it('upgrades a valid v2 knowledge store without dropping documents', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      const storeName = 'semalink_collaboration_migration_' + Date.now() + '.db';
      try {
        const legacy = await relationalStore.getRdbStore(context, {
          name: storeName,
          securityLevel: relationalStore.SecurityLevel.S1
        });
        await legacy.executeSql(
          'CREATE TABLE documents (document_id TEXT PRIMARY KEY,title TEXT NOT NULL,' +
          'modality TEXT NOT NULL,normalized_text TEXT NOT NULL,tags_json TEXT NOT NULL,' +
          'checksum TEXT NOT NULL UNIQUE,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,' +
          "privacy_level TEXT NOT NULL DEFAULT 'PRIVATE_GROUP')"
        );
        await legacy.executeSql(
          "INSERT INTO documents VALUES ('kept','Kept','text','body','[]','sum',1,1,'PRIVATE_GROUP')"
        );
        legacy.version = 2;
        legacy.close();
        const database = new KnowledgeDatabase(storeName);
        await database.initialize(context);
        expect(database.getStore().version).assertEqual(3);
        const result = await database.getStore().querySql(
          "SELECT COUNT(*) FROM documents WHERE document_id='kept'"
        );
        try {
          expect(result.goToNextRow()).assertTrue();
          expect(result.getLong(0)).assertEqual(1);
        } finally {
          result.close();
        }
        database.close();
      } finally {
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });
  });
}
