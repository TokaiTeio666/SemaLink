import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeDatabase } from '../../../main/ets/knowledge/storage/KnowledgeDatabase';
import { RdbDocumentRepository } from '../../../main/ets/knowledge/storage/RdbDocumentRepository';
import { DocumentChunker } from '../../../main/ets/knowledge/import/DocumentChunker';
import { KeywordExtractor } from '../../../main/ets/knowledge/import/KeywordExtractor';
import { RawFileDocumentImporter } from '../../../main/ets/knowledge/import/RawFileDocumentImporter';
import { UserDocumentImporter } from '../../../main/ets/knowledge/import/UserDocumentImporter';
import { UserTextDocument } from '../../../main/ets/knowledge/import/UriTextContentReader';

export default function knowledgeDatabaseTest() {
  describe('KnowledgeDatabase', () => {
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
      expect(first.importedDocuments >= 12).assertTrue();
      expect(afterFirst.documentCount >= 12).assertTrue();
      expect(afterFirst.chunkCount > afterFirst.documentCount).assertTrue();

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
  });
}
