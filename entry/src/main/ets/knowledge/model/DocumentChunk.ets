export interface DocumentChunk {
  chunkId: string;
  documentId: string;
  chunkIndex: number;
  text: string;
  summary: string;
  keywords: string[];
  startOffset: number;
  endOffset: number;
  updatedAt: number;
}
