import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeCompositionRoot } from '../../../main/ets/application/KnowledgeCompositionRoot';
import { TaskRequest } from '../../../main/ets/contracts/semantic/SemanticModels';
import { DocumentChunk } from '../../../main/ets/knowledge/model/DocumentChunk';
import { KnowledgeDocument } from '../../../main/ets/knowledge/model/KnowledgeDocument';
import { AppRuntime } from '../../../main/ets/runtime/AppRuntime';
import { FakeTransport } from '../../../test/support/FakeTransport';

function request(taskId: string, privacyLevel: 'LOCAL_ONLY' | 'PRIVATE_GROUP',
  levels: ('L1' | 'L2')[] = ['L1', 'L2']): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: taskId, queryText: '进程和线程有什么区别',
    requiredConcepts: ['进程', '线程'], requiredConfidence: 0.9, coverageThreshold: 0.9,
    latencyBudgetMs: 1, byteBudget: 1, privacyLevel: privacyLevel, acceptableLevels: levels
  };
}

export default function semanticKnowledgeProviderDeviceTest(): void {
  describe('SemanticKnowledgeProviderDevice', () => {
    it('uses one real RDB service for gateway and provider with stable restart evidence', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      let components = await KnowledgeCompositionRoot.create(ability.context, 'device-fixture');
      await components.repository.clearAll();
      try {
        expect(components.gateway === components.service).assertTrue();
        expect(components.provider === components.service).assertTrue();
        const imported = await components.importer.importBuiltInDocuments();
        expect(imported.importedDocuments).assertEqual(12);
        const statistics = await components.repository.getStatistics();
        const profile = await components.provider.getProfile();
        expect(profile.documentCount).assertEqual(statistics.documentCount);
        expect(profile.chunkCount).assertEqual(statistics.chunkCount);
        expect(JSON.stringify(profile.modalities)).assertEqual(JSON.stringify(statistics.modalities));
        expect(profile.indexState).assertEqual('READY');

        const first = await components.provider.searchEvidence(request('device-first', 'PRIVATE_GROUP'));
        expect(first.some((unit): boolean => unit.level === 'L1')).assertTrue();
        expect(first.some((unit): boolean => unit.level === 'L2')).assertTrue();
        expect(first.every((unit): boolean => unit.sourceDeviceId === 'device-fixture')).assertTrue();
        const stableIds = first.map((unit): string => unit.evidenceId + ':' + unit.hash);

        components.database.close();
        components = await KnowledgeCompositionRoot.create(ability.context, 'device-fixture');
        const restarted = await components.provider.searchEvidence(request('device-restart', 'PRIVATE_GROUP'));
        expect(JSON.stringify(restarted.map((unit): string => unit.evidenceId + ':' + unit.hash)))
          .assertEqual(JSON.stringify(stableIds));
      } finally {
        await components.repository.clearAll();
        components.database.close();
      }
    });

    it('returns EMPTY after clear and enforces the real RDB privacy matrix', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const components = await KnowledgeCompositionRoot.create(ability.context);
      await components.repository.clearAll();
      try {
        await components.importer.importBuiltInDocuments();
        const localDocument: KnowledgeDocument = {
          documentId: 'doc-local-device', title: '进程与线程本机笔记', modality: 'text',
          normalizedText: '进程和线程有什么区别，线程共享进程资源。', tags: ['操作系统', '并发'],
          checksum: 'device-local-privacy', createdAt: 1, updatedAt: Date.now(), privacyLevel: 'LOCAL_ONLY'
        };
        const localChunk: DocumentChunk = {
          chunkId: 'chunk-local-device', documentId: localDocument.documentId, chunkIndex: 0,
          text: '进程负责资源隔离，线程负责调度执行。', summary: '进程与线程本机笔记',
          keywords: ['进程', '线程', '调度'], startOffset: 0, endOffset: 20, updatedAt: localDocument.updatedAt
        };
        await components.repository.saveDocumentWithChunks(localDocument, [localChunk]);
        const privateGroup = await components.provider.searchEvidence(
          request('device-private-group', 'PRIVATE_GROUP', ['L2']));
        const localOnly = await components.provider.searchEvidence(
          request('device-local-only', 'LOCAL_ONLY', ['L2']));
        expect(privateGroup.some((unit): boolean => unit.sourceDocId === localDocument.documentId)).assertFalse();
        expect(localOnly.some((unit): boolean => unit.sourceDocId === localDocument.documentId)).assertTrue();
        expect(localOnly.some((unit): boolean => unit.privacyLevel === 'PRIVATE_GROUP')).assertTrue();
        expect(localOnly.some((unit): boolean => unit.privacyLevel === 'LOCAL_ONLY')).assertTrue();

        await components.repository.clearAll();
        const profile = await components.provider.getProfile();
        expect(profile.indexState).assertEqual('EMPTY');
        expect(profile.documentCount).assertEqual(0);
        expect((await components.provider.searchEvidence(request('device-empty', 'LOCAL_ONLY'))).length)
          .assertEqual(0);
      } finally {
        await components.repository.clearAll();
        components.database.close();
      }
    });

    it('initializes and destroys the AppRuntime knowledge provider without duplicate ownership', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const first = new AppRuntime(ability.context, { transport: new FakeTransport() });
      await first.initializeKnowledge();
      await first.initializeKnowledge();
      expect(first.knowledgeGateway as Object).assertEqual(first.knowledgeProvider as Object);
      await first.knowledgeProvider.getProfile();
      first.destroy();
      first.destroy();
      const second = new AppRuntime(ability.context, { transport: new FakeTransport() });
      await second.initializeKnowledge();
      await second.knowledgeProvider.getProfile();
      second.destroy();
      expect(true).assertTrue();
    });
  });
}
