export type KnowledgeContractVersion = '1.0';
export type KnowledgePayloadLevel = 'L1' | 'L2';
export type KnowledgeModality = 'text' | 'pdf' | 'image' | 'ocr_text';
export type KnowledgeIndexState = 'EMPTY' | 'BUILDING' | 'READY' | 'ERROR';
export type RetrievalMode = 'keyword' | 'vector' | 'hybrid';

export interface KnowledgeQueryFilters {
  documentIds?: string[];
  tags?: string[];
  modalities?: KnowledgeModality[];
  updatedAfter?: number;
}

export interface LocalKnowledgeQuery {
  contractVersion: KnowledgeContractVersion;
  requestId: string;
  queryText: string;
  topK: number;
  requestedLevel: KnowledgePayloadLevel;
  maxPayloadBytes: number;
  filters?: KnowledgeQueryFilters;
}

export interface LocalKnowledgeResult {
  contractVersion: KnowledgeContractVersion;
  requestId: string;
  level: KnowledgePayloadLevel;
  itemCount: number;
  payloadJson: string;
  truncated: boolean;
  retrievalMs: number;
  indexVersion: string;
  generatedAt: number;
}

export interface KnowledgeDomain {
  tag: string;
  weight: number;
  documentCount: number;
}

export interface KnowledgeProfile {
  contractVersion: KnowledgeContractVersion;
  profileVersion: string;
  indexState: KnowledgeIndexState;
  knowledgeDomains: KnowledgeDomain[];
  documentCount: number;
  chunkCount: number;
  modalities: KnowledgeModality[];
  retrievalModes: RetrievalMode[];
  supportedLevels: KnowledgePayloadLevel[];
  indexVersion: string;
  embeddingModelVersion: string;
  updatedAt: number;
}

export interface ImportReport {
  importedDocuments: number;
  skippedDocuments: number;
  failedDocuments: number;
  createdChunks: number;
  indexVersion: string;
  durationMs: number;
}
