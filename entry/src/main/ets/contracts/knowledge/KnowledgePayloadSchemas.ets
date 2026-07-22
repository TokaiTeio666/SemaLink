export interface L1KnowledgeItem {
  evidenceId: string;
  documentId: string;
  title: string;
  summary: string;
  tags: string[];
  relevance: number;
  updatedAt: number;
}

export interface L1KnowledgePayload {
  schemaVersion: '1.0';
  level: 'L1';
  items: L1KnowledgeItem[];
}

export interface L2KnowledgeItem {
  evidenceId: string;
  documentId: string;
  chunkId: string;
  title: string;
  snippet: string;
  relevance: number;
  startOffset?: number;
  endOffset?: number;
  truncated: boolean;
}

export interface L2KnowledgePayload {
  schemaVersion: '1.0';
  level: 'L2';
  items: L2KnowledgeItem[];
}
