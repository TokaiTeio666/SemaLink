import { KnowledgeDocument } from './KnowledgeDocument';
import { DocumentChunk } from './DocumentChunk';

export interface RetrievalCandidate {
  document: KnowledgeDocument;
  chunk: DocumentChunk;
  relevance: number;
  matchedPrimaryTerms: string[];
  matchedNgrams: string[];
  exactPhraseMatched: boolean;
}
