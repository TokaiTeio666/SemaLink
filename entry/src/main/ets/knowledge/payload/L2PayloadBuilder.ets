import { L2KnowledgeItem } from '../../contracts/knowledge/KnowledgePayloadSchemas';
import { RetrievalCandidate } from '../model/RetrievalCandidate';
import { BudgetedPayload, PayloadBudgetController } from './PayloadBudgetController';

export class L2PayloadBuilder {
  build(candidates: RetrievalCandidate[], maxPayloadBytes: number): BudgetedPayload {
    const items: L2KnowledgeItem[] = [];
    let shortenedByItemLimit = false;
    for (const candidate of candidates) {
      const snippet = candidate.chunk.text.length > 1500 ? candidate.chunk.text.substring(0, 1500) : candidate.chunk.text;
      if (candidate.chunk.text.length > 1500) {
        shortenedByItemLimit = true;
      }
      items.push({
        evidenceId: 'ev-' + candidate.chunk.chunkId,
        documentId: candidate.document.documentId,
        chunkId: candidate.chunk.chunkId,
        title: candidate.document.title,
        snippet: snippet,
        relevance: candidate.relevance,
        startOffset: candidate.chunk.startOffset,
        endOffset: candidate.chunk.endOffset,
        truncated: candidate.chunk.text.length > 1500
      });
    }
    const budgeted = new PayloadBudgetController().budgetL2(items, maxPayloadBytes);
    if (shortenedByItemLimit && !budgeted.truncated) {
      return { payloadJson: budgeted.payloadJson, itemCount: budgeted.itemCount, truncated: true };
    }
    return budgeted;
  }
}
