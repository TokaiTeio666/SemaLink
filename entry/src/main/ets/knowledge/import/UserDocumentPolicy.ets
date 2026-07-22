import { KnowledgeError } from '../../contracts/knowledge/KnowledgeError';
import { normalizeText } from './TextNormalizer';

export const MAX_USER_DOCUMENT_BYTES: number = 2 * 1024 * 1024;
export const MAX_USER_IMPORT_BYTES: number = 10 * 1024 * 1024;
export const MAX_USER_DOCUMENTS: number = 20;

function stableHash(value: string): string {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index++) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16);
}

export function checksumUserText(text: string): string {
  return stableHash(normalizeText(text));
}

export function validateUserDocument(displayName: string, byteSize: number, accumulatedBytes: number): void {
  const normalizedName: string = displayName.toLowerCase();
  if (!normalizedName.endsWith('.txt') && !normalizedName.endsWith('.md') &&
    !normalizedName.endsWith('.markdown')) {
    throw new KnowledgeError('E_FILE_TYPE_UNSUPPORTED', '仅支持 TXT、MD 和 MARKDOWN 文档', true);
  }
  if (!Number.isInteger(byteSize) || byteSize < 0 || byteSize > MAX_USER_DOCUMENT_BYTES) {
    throw new KnowledgeError('E_FILE_TOO_LARGE', '单个文档不能超过 2 MiB', true);
  }
  if (accumulatedBytes + byteSize > MAX_USER_IMPORT_BYTES) {
    throw new KnowledgeError('E_IMPORT_TOTAL_TOO_LARGE', '一次导入总大小不能超过 10 MiB', true);
  }
}

export function validateUserText(text: string): string {
  const normalized: string = normalizeText(text);
  if (normalized.length === 0) {
    throw new KnowledgeError('E_FILE_EMPTY', '不能导入空文档', true);
  }
  return normalized;
}

export function safeDocumentTitle(displayName: string): string {
  let title: string = displayName;
  const slash: number = Math.max(title.lastIndexOf('/'), title.lastIndexOf('\\'));
  if (slash >= 0) {
    title = title.substring(slash + 1);
  }
  const lower: string = title.toLowerCase();
  for (const extension of ['.markdown', '.txt', '.md']) {
    if (lower.endsWith(extension)) {
      title = title.substring(0, title.length - extension.length);
      break;
    }
  }
  const safe: string = title.replace(/[\r\n\t]/g, ' ').trim();
  return safe.length === 0 ? '未命名文档' : safe.substring(0, 120);
}
