export type KnowledgeQueryDisplayStatus = 'IDLE' | 'QUERYING' | 'SUCCESS' | 'EMPTY' | 'ERROR';

export interface DisplayKnowledgeItem {
  title: string;
  relevance: number;
  content: string;
  kind: '摘要' | '命中段落';
  chunkLabel: string;
}

export interface KnowledgeQueryDisplayState {
  status: KnowledgeQueryDisplayStatus;
  summary: string;
  errorText: string;
  items: DisplayKnowledgeItem[];
}

export function initialQueryState(): KnowledgeQueryDisplayState {
  return { status: 'IDLE', summary: '尚未查询', errorText: '', items: [] };
}

export function beginQueryState(previous: KnowledgeQueryDisplayState): KnowledgeQueryDisplayState {
  return { status: 'QUERYING', summary: '正在查询', errorText: '', items: [] };
}

export function succeedQueryState(items: DisplayKnowledgeItem[], retrievalMs: number,
  truncated: boolean): KnowledgeQueryDisplayState {
  if (items.length === 0) {
    return { status: 'EMPTY', summary: retrievalMs.toString() + ' ms · 0 条 · 未找到相关内容', errorText: '', items: [] };
  }
  return {
    status: 'SUCCESS',
    summary: retrievalMs.toString() + ' ms · ' + items.length.toString() + ' 条 · truncated=' + truncated.toString(),
    errorText: '',
    items: items
  };
}

export function failQueryState(previous: KnowledgeQueryDisplayState, code: string,
  message: string): KnowledgeQueryDisplayState {
  const errorText = code + ': ' + message;
  return { status: 'ERROR', summary: '查询失败', errorText: errorText, items: [] };
}
