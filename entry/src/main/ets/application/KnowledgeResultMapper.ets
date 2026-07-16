import { DisplayKnowledgeItem } from './KnowledgeQueryDisplayState';
import { LocalKnowledgeResult } from '../contracts/knowledge/KnowledgeModels';
import {
  L1KnowledgeItem,
  L1KnowledgePayload,
  L2KnowledgeItem,
  L2KnowledgePayload
} from '../contracts/knowledge/KnowledgePayloadSchemas';
import { AppStateStore } from '../state/AppStateStore';

export function displayItemsFromResult(result: LocalKnowledgeResult): DisplayKnowledgeItem[] {
  const displayItems: DisplayKnowledgeItem[] = [];
  if (result.level === 'L1') {
    const payload: L1KnowledgePayload = JSON.parse(result.payloadJson) as L1KnowledgePayload;
    for (const item of payload.items) {
      displayItems.push(mapL1Item(item));
    }
    return displayItems;
  }

  const payload: L2KnowledgePayload = JSON.parse(result.payloadJson) as L2KnowledgePayload;
  for (const item of payload.items) {
    displayItems.push(mapL2Item(item));
  }
  return displayItems;
}

export function publishKnowledgeResult(store: AppStateStore, result: LocalKnowledgeResult): void {
  const items: DisplayKnowledgeItem[] = displayItemsFromResult(result);
  store.update({
    summary: resultSummary(result),
    knowledgeBusy: false,
    knowledgeMessage: resultSummary(result),
    knowledgeQueryStatus: items.length === 0 ? 'EMPTY' : 'SUCCESS',
    knowledgeLevel: result.level,
    knowledgeItems: items,
    knowledgeRetrievalMs: result.retrievalMs,
    knowledgeTruncated: result.truncated,
    knowledgeError: ''
  });
}

export function resultSummary(result: LocalKnowledgeResult): string {
  const truncated: string = result.truncated ? '，结果已按大小限制截断' : '';
  return '命中 ' + result.itemCount.toString() + ' 条，检索耗时 ' +
    result.retrievalMs.toString() + ' ms' + truncated;
}

function mapL1Item(item: L1KnowledgeItem): DisplayKnowledgeItem {
  return {
    title: item.title,
    relevance: item.relevance,
    content: item.summary,
    kind: '摘要',
    chunkLabel: ''
  };
}

function mapL2Item(item: L2KnowledgeItem): DisplayKnowledgeItem {
  return {
    title: item.title,
    relevance: item.relevance,
    content: item.snippet,
    kind: '命中段落',
    chunkLabel: item.chunkId
  };
}
