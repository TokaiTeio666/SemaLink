import { describe, expect, it } from '@ohos/hypium';
import {
  COLLABORATION_SCHEMA_STATEMENTS,
  KNOWLEDGE_DATABASE_VERSION,
  migrationStatements
} from '../main/ets/knowledge/storage/KnowledgeDatabaseSchema';

export default function knowledgeDatabaseCollaborationMigrationTest(): void {
  describe('KnowledgeDatabaseCollaborationMigration', () => {
    it('raises the schema to version three without dropping knowledge tables', 0, () => {
      expect(KNOWLEDGE_DATABASE_VERSION).assertEqual(3);
      expect(COLLABORATION_SCHEMA_STATEMENTS.length).assertEqual(5);
      const joined: string = COLLABORATION_SCHEMA_STATEMENTS.join(' ').toLowerCase();
      expect(joined.includes('local_collaboration_identity')).assertTrue();
      expect(joined.includes('collaboration_peers')).assertTrue();
      expect(joined.includes('remote_knowledge_profiles')).assertTrue();
      expect(joined.includes('sharing_policy')).assertTrue();
      expect(joined.includes('remote_access_records')).assertTrue();
      expect(joined.includes('drop table')).assertFalse();
    });

    it('treats version two as an additive idempotent migration', 0, () => {
      expect(migrationStatements(2, true).length).assertEqual(0);
      expect(migrationStatements(3, true).length).assertEqual(0);
    });
  });
}
