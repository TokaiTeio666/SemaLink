import { L1KnowledgeItem } from '../../contracts/knowledge/KnowledgePayloadSchemas';
import { RetrievalCandidate } from '../model/RetrievalCandidate';
import { BudgetedPayload, PayloadBudgetController } from './PayloadBudgetController';

function alreadyIncluded(items: L1KnowledgeItem[], documentId: string): boolean {
  for (const item of items) {
    if (item.documentId === documentId) {
      return true;
    }
  }
  return false;
}

function representativeSentence(text: string): string {
  const maximum: number = Math.min(150, text.length);
  for (let index = 0; index < maximum; index++) {
    const character: string = text.charAt(index);
    if (character === '。' || character === '！' || character === '？' || character === '!' || character === '?') {
      return text.substring(0, index + 1).trim();
    }
  }
  return text.substring(0, maximum).trim();
}

function buildDocumentSummary(candidate: RetrievalCandidate, candidates: RetrievalCandidate[]): string {
  const sentences: string[] = [];
  const first: string = representativeSentence(candidate.chunk.text);
  if (first.length > 0) {
    sentences.push(first);
  }
  for (const related of candidates) {
    if (related.document.documentId !== candidate.document.documentId ||
      related.chunk.chunkId === candidate.chunk.chunkId) {
      continue;
    }
    const sentence: string = representativeSentence(related.chunk.text);
    if (sentence.length > 0 && sentences.indexOf(sentence) < 0) {
      sentences.push(sentence);
      break;
    }
  }
  const combined: string = sentences.join(' ');
  return combined.length > 300 ? combined.substring(0, 300) : combined;
}

export class L1PayloadBuilder {
  build(candidates: RetrievalCandidate[], maxPayloadBytes: number): BudgetedPayload {
    const items: L1KnowledgeItem[] = [];
    for (const candidate of candidates) {
      if (alreadyIncluded(items, candidate.document.documentId)) {
        continue;
      }
      const summary: string = buildDocumentSummary(candidate, candidates);
      items.push({
        evidenceId: 'ev-doc-' + candidate.document.documentId,
        documentId: candidate.document.documentId,
        title: candidate.document.title,
        summary: summary,
        tags: candidate.document.tags,
        relevance: candidate.relevance,
        updatedAt: candidate.document.updatedAt
      });
    }
    return new PayloadBudgetController().budgetL1(items, maxPayloadBytes);
  }
}
