import { DocumentChunk } from '../model/DocumentChunk';

const TARGET_LENGTH: number = 550;
const MAX_LENGTH: number = 700;
const OVERLAP: number = 50;

function stableHash(value: string): string {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index++) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16);
}

function findBoundary(text: string, start: number, preferredEnd: number): number {
  const maximum = Math.min(start + MAX_LENGTH, text.length);
  const minimum = Math.min(start + 400, maximum);
  let best = -1;
  for (let index = minimum; index <= maximum; index++) {
    const character = text.charAt(index - 1);
    if (character === '\n' || character === '。' || character === '？' || character === '！' ||
      character === '；' || character === '?' || character === '!' || character === ';') {
      best = index;
      if (index >= preferredEnd) {
        break;
      }
    }
  }
  if (best > start) {
    return best;
  }
  return maximum;
}

function summarize(text: string): string {
  if (text.length <= 300) {
    return text;
  }
  let sentenceCount = 0;
  let lastBoundary = -1;
  for (let index = 0; index < 300; index++) {
    const character = text.charAt(index);
    if (character === '。' || character === '？' || character === '！' || character === '?' || character === '!') {
      sentenceCount += 1;
      lastBoundary = index + 1;
      if (sentenceCount === 2) {
        return text.substring(0, lastBoundary);
      }
    }
  }
  return lastBoundary > 0 ? text.substring(0, lastBoundary) : text.substring(0, 300);
}

export class DocumentChunker {
  chunkDocument(documentId: string, normalizedText: string, updatedAt: number): DocumentChunk[] {
    const chunks: DocumentChunk[] = [];
    if (normalizedText.trim().length === 0) {
      return chunks;
    }
    let start = 0;
    let chunkIndex = 0;
    while (start < normalizedText.length) {
      const end = findBoundary(normalizedText, start, start + TARGET_LENGTH);
      const text = normalizedText.substring(start, end).trim();
      if (text.length > 0) {
        chunks.push({
          chunkId: 'chunk-' + stableHash(documentId + ':' + start.toString() + ':' + end.toString() + ':' + text),
          documentId: documentId,
          chunkIndex: chunkIndex,
          text: text,
          summary: summarize(text),
          keywords: [],
          startOffset: start,
          endOffset: end,
          updatedAt: updatedAt
        });
        chunkIndex += 1;
      }
      if (end >= normalizedText.length) {
        break;
      }
      const next = end - OVERLAP;
      start = next > start ? next : end;
    }
    return chunks;
  }
}
