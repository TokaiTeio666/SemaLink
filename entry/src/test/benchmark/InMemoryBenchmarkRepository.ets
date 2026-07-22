import { KnowledgeModality } from '../../main/ets/contracts/knowledge/KnowledgeModels';
import { DocumentChunk } from '../../main/ets/knowledge/model/DocumentChunk';
import { KnowledgeDocument } from '../../main/ets/knowledge/model/KnowledgeDocument';
import {
  DocumentRepository,
  KnowledgeMetadata,
  RepositoryStatistics,
  DomainCount
} from '../../main/ets/knowledge/storage/DocumentRepository';

export class InMemoryBenchmarkRepository implements DocumentRepository {
  private documents: KnowledgeDocument[];
  private chunks: DocumentChunk[];
  private metadata: KnowledgeMetadata;

  constructor(documents: KnowledgeDocument[], chunks: DocumentChunk[]) {
    this.documents = documents.slice();
    this.chunks = chunks.slice();
    this.metadata = {
      indexState: 'READY', indexVersion: 'benchmark-index-v1',
      profileVersion: 'benchmark-profile-v1', updatedAt: 1783958400000
    };
  }

  async saveDocumentWithChunks(document: KnowledgeDocument, chunks: DocumentChunk[]): Promise<void> {
    this.documents.push(document);
    for (const chunk of chunks) {
      this.chunks.push(chunk);
    }
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
    this.documents = [];
    this.chunks = [];
    this.metadata = {
      indexState: 'EMPTY', indexVersion: 'benchmark-empty',
      profileVersion: 'benchmark-empty', updatedAt: 1783958400000
    };
  }

  async getStatistics(): Promise<RepositoryStatistics> {
    const domainCounts: DomainCount[] = [];
    for (const document of this.documents) {
      for (const tag of document.tags) {
        let found = false;
        for (const count of domainCounts) {
          if (count.tag === tag) {
            count.documentCount += 1;
            found = true;
            break;
          }
        }
        if (!found) {
          domainCounts.push({ tag: tag, documentCount: 1 });
        }
      }
    }
    const modalities: KnowledgeModality[] = this.documents.length === 0 ? [] : ['text'];
    return {
      documentCount: this.documents.length, chunkCount: this.chunks.length,
      modalities: modalities, domainCounts: domainCounts
    };
  }

  async getMetadata(): Promise<KnowledgeMetadata> {
    return this.metadata;
  }

  async setMetadata(metadata: KnowledgeMetadata): Promise<void> {
    this.metadata = metadata;
  }
}
