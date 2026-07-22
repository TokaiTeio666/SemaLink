import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeModality } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { DocumentChunker } from '../main/ets/knowledge/import/DocumentChunker';
import { KeywordExtractor } from '../main/ets/knowledge/import/KeywordExtractor';
import { UserDocumentImporter } from '../main/ets/knowledge/import/UserDocumentImporter';
import { checksumUserText } from '../main/ets/knowledge/import/UserDocumentPolicy';
import { DocumentChunk } from '../main/ets/knowledge/model/DocumentChunk';
import { KnowledgeDocument } from '../main/ets/knowledge/model/KnowledgeDocument';
import {
  DocumentRepository,
  KnowledgeMetadata,
  RepositoryStatistics
} from '../main/ets/knowledge/storage/DocumentRepository';

class CapturingRepository implements DocumentRepository {
  readonly documents: KnowledgeDocument[] = [];
  private metadata: KnowledgeMetadata = {
    indexState: 'EMPTY', indexVersion: 'index-empty', profileVersion: 'profile-empty', updatedAt: 0
  };

  async saveDocumentWithChunks(document: KnowledgeDocument, chunks: DocumentChunk[]): Promise<void> {
    this.documents.push(document);
  }

  async hasChecksum(checksum: string): Promise<boolean> {
    for (const document of this.documents) {
      if (document.checksum === checksum) {
        return true;
      }
    }
    return false;
  }

  async clearAll(): Promise<void> {
    this.documents.length = 0;
  }

  async getStatistics(): Promise<RepositoryStatistics> {
    const modalities: KnowledgeModality[] = this.documents.length === 0 ? [] : ['text'];
    return { documentCount: this.documents.length, chunkCount: 0, modalities: modalities, domainCounts: [] };
  }

  async getMetadata(): Promise<KnowledgeMetadata> {
    return this.metadata;
  }

  async setMetadata(metadata: KnowledgeMetadata): Promise<void> {
    this.metadata = metadata;
  }
}

function localDocument(): KnowledgeDocument {
  return {
    documentId: 'local-only', title: 'Local', modality: 'text', normalizedText: 'local', tags: [],
    checksum: 'local-checksum', createdAt: 1, updatedAt: 1, privacyLevel: 'LOCAL_ONLY'
  };
}

export default function knowledgeImportPrivacyTest() {
  describe('KnowledgeImportPrivacy', () => {
    it('defaults user documents to PRIVATE_GROUP without changing checksum deduplication', 0, async () => {
      const repository = new CapturingRepository();
      const importer = new UserDocumentImporter(repository, new DocumentChunker(), new KeywordExtractor());
      const report = await importer.importDocuments([
        { displayName: 'first.txt', normalizedText: 'same normalized content', byteSize: 23 },
        { displayName: 'second.txt', normalizedText: 'same normalized content', byteSize: 23 }
      ]);

      expect(report.importedDocuments).assertEqual(1);
      expect(report.skippedDocuments).assertEqual(1);
      expect(repository.documents[0].privacyLevel).assertEqual('PRIVATE_GROUP');
      expect(repository.documents[0].checksum).assertEqual(checksumUserText('same normalized content'));
    });

    it('preserves an explicit LOCAL_ONLY fixture through the in-memory repository', 0, async () => {
      const repository = new CapturingRepository();
      await repository.saveDocumentWithChunks(localDocument(), []);
      expect(repository.documents.length).assertEqual(1);
      expect(repository.documents[0].privacyLevel).assertEqual('LOCAL_ONLY');
    });
  });
}
