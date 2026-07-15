import { L1KnowledgeItem, L1KnowledgePayload, L2KnowledgeItem, L2KnowledgePayload } from '../../contracts/knowledge/KnowledgePayloadSchemas';
import { utf8ByteLength } from './Utf8Sizer';

export interface BudgetedPayload {
  payloadJson: string;
  itemCount: number;
  truncated: boolean;
}

function fitL1Item(item: L1KnowledgeItem, accepted: L1KnowledgeItem[], budget: number): L1KnowledgeItem | undefined {
  let length = item.summary.length;
  while (length >= 20) {
    const candidate: L1KnowledgeItem = {
      evidenceId: item.evidenceId, documentId: item.documentId, title: item.title,
      summary: item.summary.substring(0, length), tags: item.tags, relevance: item.relevance, updatedAt: item.updatedAt
    };
    const payload: L1KnowledgePayload = { schemaVersion: '1.0', level: 'L1', items: accepted.concat([candidate]) };
    if (utf8ByteLength(JSON.stringify(payload)) <= budget) {
      return candidate;
    }
    length -= 20;
  }
  return undefined;
}

function fitL2Item(item: L2KnowledgeItem, accepted: L2KnowledgeItem[], budget: number): L2KnowledgeItem | undefined {
  let length = item.snippet.length;
  while (length >= 20) {
    const candidate: L2KnowledgeItem = {
      evidenceId: item.evidenceId, documentId: item.documentId, chunkId: item.chunkId, title: item.title,
      snippet: item.snippet.substring(0, length), relevance: item.relevance,
      startOffset: item.startOffset, endOffset: item.endOffset, truncated: true
    };
    const payload: L2KnowledgePayload = { schemaVersion: '1.0', level: 'L2', items: accepted.concat([candidate]) };
    if (utf8ByteLength(JSON.stringify(payload)) <= budget) {
      return candidate;
    }
    length -= 20;
  }
  return undefined;
}

export class PayloadBudgetController {
  budgetL1(items: L1KnowledgeItem[], budget: number): BudgetedPayload {
    const accepted: L1KnowledgeItem[] = [];
    let truncated = false;
    for (const item of items) {
      const payload: L1KnowledgePayload = { schemaVersion: '1.0', level: 'L1', items: accepted.concat([item]) };
      if (utf8ByteLength(JSON.stringify(payload)) <= budget) {
        accepted.push(item);
      } else {
        const fitted = fitL1Item(item, accepted, budget);
        truncated = true;
        if (fitted !== undefined) {
          accepted.push(fitted);
        }
      }
    }
    const result: L1KnowledgePayload = { schemaVersion: '1.0', level: 'L1', items: accepted };
    return { payloadJson: JSON.stringify(result), itemCount: accepted.length, truncated: truncated };
  }

  budgetL2(items: L2KnowledgeItem[], budget: number): BudgetedPayload {
    const accepted: L2KnowledgeItem[] = [];
    let truncated = false;
    for (const item of items) {
      const payload: L2KnowledgePayload = { schemaVersion: '1.0', level: 'L2', items: accepted.concat([item]) };
      if (utf8ByteLength(JSON.stringify(payload)) <= budget) {
        accepted.push(item);
      } else {
        const fitted = fitL2Item(item, accepted, budget);
        truncated = true;
        if (fitted !== undefined) {
          accepted.push(fitted);
        }
      }
    }
    const result: L2KnowledgePayload = { schemaVersion: '1.0', level: 'L2', items: accepted };
    return { payloadJson: JSON.stringify(result), itemCount: accepted.length, truncated: truncated };
  }
}
