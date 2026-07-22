import { ImportReport } from '../../contracts/knowledge/KnowledgeModels';
import { KnowledgeError } from '../../contracts/knowledge/KnowledgeError';
import { KnowledgeDocument } from '../model/KnowledgeDocument';
import { DocumentRepository } from '../storage/DocumentRepository';
import { DocumentChunker } from './DocumentChunker';
import { KeywordExtractor } from './KeywordExtractor';
import { UserTextDocument } from './UriTextContentReader';
import { checksumUserText, safeDocumentTitle } from './UserDocumentPolicy';

export class UserDocumentImporter {
  private readonly repository: DocumentRepository;
  private readonly chunker: DocumentChunker;
  private readonly keywordExtractor: KeywordExtractor;

  constructor(repository: DocumentRepository, chunker: DocumentChunker, keywordExtractor: KeywordExtractor) {
    this.repository = repository;
    this.chunker = chunker;
    this.keywordExtractor = keywordExtractor;
  }

  async importDocuments(documents: UserTextDocument[]): Promise<ImportReport> {
    const startedAt: number = Date.now();
    let importedDocuments = 0;
    let skippedDocuments = 0;
    let createdChunks = 0;
    try {
      await this.repository.setMetadata({
        indexState: 'BUILDING', indexVersion: 'index-building',
        profileVersion: 'profile-building', updatedAt: startedAt
      });
      for (const input of documents) {
        const checksum: string = checksumUserText(input.normalizedText);
        if (await this.repository.hasChecksum(checksum)) {
          skippedDocuments += 1;
          continue;
        }
        const now: number = Date.now();
        const title: string = safeDocumentTitle(input.displayName);
        const document: KnowledgeDocument = {
          documentId: 'doc-user-' + checksum,
          title: title,
          modality: 'text',
          normalizedText: input.normalizedText,
          tags: this.keywordExtractor.extract(title, input.normalizedText),
          checksum: checksum,
          createdAt: now,
          updatedAt: now,
          privacyLevel: 'PRIVATE_GROUP'
        };
        const chunks = this.chunker.chunkDocument(document.documentId, document.normalizedText, now);
        await this.repository.saveDocumentWithChunks(document, chunks);
        importedDocuments += 1;
        createdChunks += chunks.length;
      }
      const completedAt: number = Date.now();
      const indexVersion: string = 'index-' + completedAt.toString();
      await this.repository.setMetadata({
        indexState: 'READY', indexVersion: indexVersion,
        profileVersion: 'profile-' + completedAt.toString(), updatedAt: completedAt
      });
      return {
        importedDocuments: importedDocuments,
        skippedDocuments: skippedDocuments,
        failedDocuments: 0,
        createdChunks: createdChunks,
        indexVersion: indexVersion,
        durationMs: completedAt - startedAt
      };
    } catch (error) {
      const failedAt: number = Date.now();
      await this.setErrorMetadataBestEffort(failedAt);
      throw new KnowledgeError('E_RETRIEVAL_FAILED', '无法导入所选文档', true);
    }
  }

  private async setErrorMetadataBestEffort(failedAt: number): Promise<void> {
    try {
      await this.repository.setMetadata({
        indexState: 'ERROR', indexVersion: 'index-error-' + failedAt.toString(),
        profileVersion: 'profile-error-' + failedAt.toString(), updatedAt: failedAt
      });
    } catch (metadataError) {
      // The primary import failure is authoritative; a recovery write failure must not replace or expose it.
      return;
    }
  }
}
