import { KnowledgeModality } from '../../contracts/knowledge/KnowledgeModels';
import { PrivacyLevel } from '../../contracts/semantic/SemanticModels';
import { DocumentChunk } from './DocumentChunk';

export interface RetrievalDocument {
  documentId: string;
  title: string;
  modality: KnowledgeModality;
  tags: string[];
  updatedAt: number;
  privacyLevel: PrivacyLevel;
}

export interface RetrievalCandidate {
  document: RetrievalDocument;
  chunk: DocumentChunk;
  relevance: number;
  matchedPrimaryTerms: string[];
  matchedNgrams: string[];
  exactPhraseMatched: boolean;
}
