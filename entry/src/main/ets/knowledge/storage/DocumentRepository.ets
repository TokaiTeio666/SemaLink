import { KnowledgeIndexState, KnowledgeModality } from '../../contracts/knowledge/KnowledgeModels';
import { DocumentChunk } from '../model/DocumentChunk';
import { KnowledgeDocument } from '../model/KnowledgeDocument';

export interface DomainCount {
  tag: string;
  documentCount: number;
}

export interface RepositoryStatistics {
  documentCount: number;
  chunkCount: number;
  modalities: KnowledgeModality[];
  domainCounts: DomainCount[];
}

export interface KnowledgeMetadata {
  indexState: KnowledgeIndexState;
  indexVersion: string;
  profileVersion: string;
  updatedAt: number;
}

export interface DocumentRepository {
  saveDocumentWithChunks(document: KnowledgeDocument, chunks: DocumentChunk[]): Promise<void>;
  hasChecksum(checksum: string): Promise<boolean>;
  clearAll(): Promise<void>;
  getStatistics(): Promise<RepositoryStatistics>;
  getMetadata(): Promise<KnowledgeMetadata>;
  setMetadata(metadata: KnowledgeMetadata): Promise<void>;
}
