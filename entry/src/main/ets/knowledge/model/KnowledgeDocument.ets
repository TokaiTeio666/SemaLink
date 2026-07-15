import { KnowledgeModality } from '../../contracts/knowledge/KnowledgeModels';

export interface KnowledgeDocument {
  documentId: string;
  title: string;
  modality: KnowledgeModality;
  normalizedText: string;
  tags: string[];
  checksum: string;
  createdAt: number;
  updatedAt: number;
}
