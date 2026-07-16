import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeError } from '../main/ets/contracts/knowledge/KnowledgeError';
import {
  ADD_DOCUMENT_PRIVACY_LEVEL,
  CREATE_DOCUMENTS_V2,
  KNOWLEDGE_DATABASE_VERSION,
  migrationStatements,
  parseStoredPrivacyLevel
} from '../main/ets/knowledge/storage/KnowledgeDatabaseSchema';

function capturedCode(action: () => void): string {
  try {
    action();
  } catch (error) {
    if (error instanceof KnowledgeError) {
      return error.code;
    }
  }
  return '';
}

export default function knowledgeDatabaseMigrationTest() {
  describe('KnowledgeDatabaseMigration', () => {
    it('defines v2 with a non-null PRIVATE_GROUP privacy column', 0, () => {
      expect(KNOWLEDGE_DATABASE_VERSION).assertEqual(2);
      expect(CREATE_DOCUMENTS_V2).assertContain("privacy_level TEXT NOT NULL DEFAULT 'PRIVATE_GROUP'");
    });

    it('migrates v1 exactly once without dropping data tables', 0, () => {
      const fromV1 = migrationStatements(1, false);
      const recoveredV1 = migrationStatements(1, true);
      const fromV2 = migrationStatements(2, true);
      expect(fromV1.length).assertEqual(1);
      expect(fromV1[0]).assertEqual(ADD_DOCUMENT_PRIVACY_LEVEL);
      expect(fromV1[0].toLowerCase().includes('drop table')).assertFalse();
      expect(recoveredV1.length).assertEqual(0);
      expect(fromV2.length).assertEqual(0);
    });

    it('migrates an existing version zero documents table only when the privacy column is missing', 0, () => {
      const legacyVersionZero = migrationStatements(0, false);
      const freshOrRecoveredVersionZero = migrationStatements(0, true);
      expect(legacyVersionZero.length).assertEqual(1);
      expect(legacyVersionZero[0]).assertEqual(ADD_DOCUMENT_PRIVACY_LEVEL);
      expect(freshOrRecoveredVersionZero.length).assertEqual(0);
    });

    it('rejects a v2 documents schema that is missing the required privacy column', 0, () => {
      expect(capturedCode((): void => { migrationStatements(2, false); })).assertEqual('E_STORAGE_FAILED');
    });

    it('rejects unknown future database versions without downgrade', 0, () => {
      expect(capturedCode((): void => { migrationStatements(3, true); })).assertEqual('E_STORAGE_FAILED');
    });

    it('maps only known stored privacy values and fails safely otherwise', 0, () => {
      expect(parseStoredPrivacyLevel('LOCAL_ONLY')).assertEqual('LOCAL_ONLY');
      expect(parseStoredPrivacyLevel('PRIVATE_GROUP')).assertEqual('PRIVATE_GROUP');
      expect(capturedCode((): void => { parseStoredPrivacyLevel("bad SQL file:///data/private"); }))
        .assertEqual('E_STORAGE_FAILED');
    });
  });
}
