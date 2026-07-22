import { abilityDelegatorRegistry } from '@kit.TestKit';
import { relationalStore } from '@kit.ArkData';
import { describe, expect, it } from '@ohos/hypium';
import { DocumentChunk } from '../../../main/ets/knowledge/model/DocumentChunk';
import { KnowledgeDocument } from '../../../main/ets/knowledge/model/KnowledgeDocument';
import { RetrievalCandidate } from '../../../main/ets/knowledge/model/RetrievalCandidate';
import { KnowledgeDatabase } from '../../../main/ets/knowledge/storage/KnowledgeDatabase';
import { RdbDocumentRepository } from '../../../main/ets/knowledge/storage/RdbDocumentRepository';
import {
  buildSqlLikeCandidateQuery,
  SqlLikeCandidateQuery
} from '../../../main/ets/knowledge/storage/SqlLikeCandidateQuery';

function document(id: string, privacy: 'LOCAL_ONLY' | 'PRIVATE_GROUP', title: string,
  tags: string[], updatedAt: number): KnowledgeDocument {
  return {
    documentId: id, title: title, modality: 'text', normalizedText: title, tags: tags,
    checksum: 'sum-' + id, createdAt: updatedAt, updatedAt: updatedAt, privacyLevel: privacy
  };
}

function chunk(id: string, documentId: string, text: string, updatedAt: number,
  keywords: string[] = ['transaction', '\u9694\u79BB']): DocumentChunk {
  return {
    chunkId: id, documentId: documentId, chunkIndex: 0, text: text, summary: text,
    keywords: keywords, startOffset: 0, endOffset: text.length, updatedAt: updatedAt
  };
}

export default function rdbCandidateSearchTest() {
  describe('RdbCandidateSearch', () => {
    it('searches and filters in SQL before stable Top-K without injection expansion', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      const storeName = 'semalink_candidate_search_' + Date.now().toString() + '.db';
      try {
        const database = new KnowledgeDatabase(storeName);
        await database.initialize(context);
        const repository = new RdbDocumentRepository(database);
        await repository.saveDocumentWithChunks(
          document('group-tx', 'PRIVATE_GROUP', '\u4E8B\u52A1\u9694\u79BB\u7EA7\u522B', ['database', 'transaction'], 20),
          [chunk('chunk-group', 'group-tx', '\u4E8B\u52A1\u9694\u79BB\u7EA7\u522B HarmonyOS 24', 20)]);
        await repository.saveDocumentWithChunks(
          document('local-tx', 'LOCAL_ONLY', '\u672C\u5730\u4E8B\u52A1\u9694\u79BB', ['database'], 30),
          [chunk('chunk-local', 'local-tx', '\u672C\u5730\u4E8B\u52A1\u9694\u79BB', 30)]);
        await repository.saveDocumentWithChunks(
          document('group-index', 'PRIVATE_GROUP', '\u6570\u636E\u5E93\u7D22\u5F15', ['database', 'index'], 40),
          [chunk('chunk-index', 'group-index', '\u590D\u5408\u7D22\u5F15\u4F18\u5316\u67E5\u8BE2', 40, ['index'])]);
        const summaryOnlyChunk = chunk('chunk-summary-only', 'summary-only', 'neutral body', 50, ['neutral']);
        summaryOnlyChunk.summary = 'summaryonlytoken';
        await repository.saveDocumentWithChunks(
          document('summary-only', 'PRIVATE_GROUP', 'neutral summary document', ['other'], 50),
          [summaryOnlyChunk]);
        await repository.saveDocumentWithChunks(
          document('keyword-only', 'PRIVATE_GROUP', 'neutral keyword document', ['other'], 60),
          [chunk('chunk-keyword-only', 'keyword-only', 'neutral body', 60, ['keywordonlytoken'])]);
        const longDocument = document('long-document', 'PRIVATE_GROUP', 'lightweighttoken', ['long'], 70);
        longDocument.normalizedText = 'normalized-only-secret-' + 'x'.repeat(20000);
        longDocument.checksum = 'checksum-only-secret';
        longDocument.createdAt = 123456;
        await repository.saveDocumentWithChunks(longDocument,
          [chunk('chunk-long-document', 'long-document', 'lightweighttoken short chunk', 70, ['lightweighttoken'])]);

        const diagnosticPlan: SqlLikeCandidateQuery | undefined = buildSqlLikeCandidateQuery({
          queryText: '\u9694\u79BB', topK: 5, privacyLevel: 'PRIVATE_GROUP'
        });
        expect(diagnosticPlan === undefined).assertFalse();
        const diagnosticRows = await database.getStore().querySql(
          diagnosticPlan!.sql, diagnosticPlan!.bindArgs);
        let diagnosticCount = 0;
        try {
          while (diagnosticRows.goToNextRow()) diagnosticCount += 1;
        } finally {
          diagnosticRows.close();
        }
        expect(diagnosticCount).assertEqual(1);

        const privateResults: RetrievalCandidate[] = await repository.searchCandidates({
          queryText: '\u9694\u79BB', topK: 5, privacyLevel: 'PRIVATE_GROUP'
        });
        const localResults: RetrievalCandidate[] = await repository.searchCandidates({
          queryText: '\u9694\u79BB', topK: 5, privacyLevel: 'LOCAL_ONLY'
        });
        const filtered: RetrievalCandidate[] = await repository.searchCandidates({
          queryText: '\u4E8B\u52A1', topK: 1, privacyLevel: 'PRIVATE_GROUP',
          filters: { documentIds: ['group-tx'], tags: ['transaction'], modalities: ['text'], updatedAfter: 10 }
        });
        const filteredOut: RetrievalCandidate[] = await repository.searchCandidates({
          queryText: '\u4E8B\u52A1', topK: 5, privacyLevel: 'PRIVATE_GROUP', filters: { updatedAfter: 25 }
        });
        const documentFilter = await repository.searchCandidates({
          queryText: 'database', topK: 1, privacyLevel: 'PRIVATE_GROUP', filters: { documentIds: ['group-index'] }
        });
        const tagFilter = await repository.searchCandidates({
          queryText: 'transaction', topK: 5, privacyLevel: 'PRIVATE_GROUP', filters: { tags: ['transaction'] }
        });
        const tagFilterMiss = await repository.searchCandidates({
          queryText: 'transaction', topK: 5, privacyLevel: 'PRIVATE_GROUP', filters: { tags: ['missing'] }
        });
        const modalityFilter = await repository.searchCandidates({
          queryText: 'transaction', topK: 5, privacyLevel: 'PRIVATE_GROUP', filters: { modalities: ['text'] }
        });
        const modalityFilterMiss = await repository.searchCandidates({
          queryText: 'transaction', topK: 5, privacyLevel: 'PRIVATE_GROUP', filters: { modalities: ['pdf'] }
        });
        const updatedFilter = await repository.searchCandidates({
          queryText: '\u4E8B\u52A1', topK: 5, privacyLevel: 'PRIVATE_GROUP', filters: { updatedAfter: 10 }
        });
        const mixed: RetrievalCandidate[] = await repository.searchCandidates({
          queryText: 'HarmonyOS 24', topK: 5, privacyLevel: 'PRIVATE_GROUP'
        });
        const injected: RetrievalCandidate[] = await repository.searchCandidates({
          queryText: "' OR 1=1 -- %_", topK: 20, privacyLevel: 'LOCAL_ONLY'
        });
        const injectionInputs: string[] = ["'", 'OR 1=1', '--', '%_', 'MATCH "'];
        for (const injectionInput of injectionInputs) {
          const injectionResult = await repository.searchCandidates({
            queryText: injectionInput, topK: 20, privacyLevel: 'LOCAL_ONLY'
          });
          const actualIds = injectionResult.map((candidate: RetrievalCandidate): string =>
            candidate.document.documentId);
          const expectedIds: string[] = injectionInput === 'OR 1=1' ? ['keyword-only'] : [];
          expect(JSON.stringify(actualIds)).assertEqual(JSON.stringify(expectedIds));
        }
        const summaryOnly = await repository.searchCandidates({
          queryText: 'summaryonlytoken', topK: 5, privacyLevel: 'PRIVATE_GROUP'
        });
        const keywordOnly = await repository.searchCandidates({
          queryText: 'keywordonlytoken', topK: 5, privacyLevel: 'PRIVATE_GROUP'
        });
        const longCandidates = await repository.searchCandidates({
          queryText: 'lightweighttoken', topK: 5, privacyLevel: 'PRIVATE_GROUP'
        });

        expect(privateResults.length).assertEqual(1);
        expect(privateResults[0].document.documentId).assertEqual('group-tx');
        expect(localResults.length).assertEqual(2);
        expect(filtered.length).assertEqual(1);
        expect(filtered[0].document.documentId).assertEqual('group-tx');
        expect(filteredOut.length).assertEqual(0);
        expect(documentFilter.length).assertEqual(1);
        expect(documentFilter[0].document.documentId).assertEqual('group-index');
        expect(tagFilter.length).assertEqual(1);
        expect(tagFilterMiss.length).assertEqual(0);
        expect(modalityFilter.length).assertEqual(1);
        expect(modalityFilterMiss.length).assertEqual(0);
        expect(updatedFilter.length).assertEqual(1);
        expect(mixed.length).assertEqual(1);
        expect(JSON.stringify(injected.map((candidate: RetrievalCandidate): string =>
          candidate.document.documentId))).assertEqual(JSON.stringify(['keyword-only']));
        expect(summaryOnly.length).assertEqual(1);
        expect(summaryOnly[0].document.documentId).assertEqual('summary-only');
        expect(keywordOnly.length).assertEqual(1);
        expect(keywordOnly[0].document.documentId).assertEqual('keyword-only');
        expect(longCandidates.length).assertEqual(1);
        const longProjection = JSON.stringify(longCandidates[0].document);
        expect(longProjection.includes('normalizedText')).assertFalse();
        expect(longProjection.includes('normalized-only-secret')).assertFalse();
        expect(longProjection.includes('checksum')).assertFalse();
        expect(longProjection.includes('createdAt')).assertFalse();
        expect(Number.isFinite(privateResults[0].relevance)).assertTrue();
        expect(privateResults[0].relevance >= 0 && privateResults[0].relevance <= 1).assertTrue();
        expect(JSON.stringify(privateResults)).assertEqual(JSON.stringify(await repository.searchCandidates({
          queryText: '\u9694\u79BB', topK: 5, privacyLevel: 'PRIVATE_GROUP'
        })));
        database.close();
      } finally {
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });
  });
}
