import { util } from '@kit.ArkTS';
import { resourceManager } from '@kit.LocalizationKit';
import { KnowledgeError } from '../../contracts/knowledge/KnowledgeError';
import { ImportReport } from '../../contracts/knowledge/KnowledgeModels';
import { KnowledgeDocument } from '../model/KnowledgeDocument';
import { DocumentRepository, KnowledgeMetadata } from '../storage/DocumentRepository';
import { DocumentChunker } from './DocumentChunker';
import { RawFileManifestItem, parseRawFileManifest } from './RawFileManifest';
import { normalizeText } from './TextNormalizer';

function stableHash(value: string): string {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index++) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16);
}

export class RawFileDocumentImporter {
  private readonly resources: resourceManager.ResourceManager;
  private readonly repository: DocumentRepository;
  private readonly chunker: DocumentChunker;

  constructor(
    resources: resourceManager.ResourceManager,
    repository: DocumentRepository,
    chunker: DocumentChunker
  ) {
    this.resources = resources;
    this.repository = repository;
    this.chunker = chunker;
  }

  async importBuiltInDocuments(): Promise<ImportReport> {
    const startedAt = Date.now();
    let importedDocuments = 0;
    let skippedDocuments = 0;
    let createdChunks = 0;
    const building: KnowledgeMetadata = {
      indexState: 'BUILDING', indexVersion: 'index-building', profileVersion: 'profile-building', updatedAt: startedAt
    };
    await this.repository.setMetadata(building);
    try {
      const decoder = new util.TextDecoder('utf-8', { fatal: true, ignoreBOM: false });
      const manifestBytes = await this.resources.getRawFileContent('test_documents/manifest.json');
      const manifest = parseRawFileManifest(decoder.decodeToString(manifestBytes));
      for (const item of manifest.documents) {
        const bytes = await this.resources.getRawFileContent('test_documents/' + item.filename);
        const normalized = normalizeText(decoder.decodeToString(bytes));
        const checksum = stableHash(normalized);
        if (await this.repository.hasChecksum(checksum)) {
          skippedDocuments += 1;
          continue;
        }
        const document = this.createDocument(item, normalized, checksum);
        const chunks = this.chunker.chunkDocument(document.documentId, normalized, document.updatedAt);
        await this.repository.saveDocumentWithChunks(document, chunks);
        importedDocuments += 1;
        createdChunks += chunks.length;
      }
      const completedAt = Date.now();
      const indexVersion = 'index-' + completedAt.toString();
      await this.repository.setMetadata({
        indexState: 'READY', indexVersion: indexVersion,
        profileVersion: 'profile-' + completedAt.toString(), updatedAt: completedAt
      });
      return {
        importedDocuments: importedDocuments, skippedDocuments: skippedDocuments, failedDocuments: 0,
        createdChunks: createdChunks,
        indexVersion: indexVersion, durationMs: completedAt - startedAt
      };
    } catch (error) {
      await this.repository.setMetadata({
        indexState: 'ERROR', indexVersion: 'index-error', profileVersion: 'profile-error', updatedAt: Date.now()
      });
      if (error instanceof KnowledgeError) {
        throw error;
      }
      throw new KnowledgeError('E_RETRIEVAL_FAILED', 'Unable to import built-in knowledge documents', true);
    }
  }

  private createDocument(item: RawFileManifestItem, normalized: string, checksum: string): KnowledgeDocument {
    return {
      documentId: 'doc-' + stableHash(item.filename),
      title: item.title,
      modality: item.modality,
      normalizedText: normalized,
      tags: item.tags,
      checksum: checksum,
      createdAt: item.createdAt,
      updatedAt: item.createdAt
    };
  }
}
