import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeError, KnowledgeErrorCode } from '../main/ets/contracts/knowledge/KnowledgeError';
import { PrivacyLevel, TaskRequestFilters } from '../main/ets/contracts/semantic/SemanticModels';
import { KnowledgeRetrievalRequest } from '../main/ets/knowledge/retrieval/RetrievalEngine';
import {
  buildSqlLikeCandidateQuery,
  MAX_SQL_LIKE_SEARCH_TERMS,
  SqlLikeCandidateQuery
} from '../main/ets/knowledge/storage/SqlLikeCandidateQuery';

function capturedError(request: KnowledgeRetrievalRequest): KnowledgeError | undefined {
  try {
    buildSqlLikeCandidateQuery(request);
    return undefined;
  } catch (error) {
    return error instanceof KnowledgeError ? error : undefined;
  }
}

function expectError(request: KnowledgeRetrievalRequest, code: KnowledgeErrorCode): void {
  const error = capturedError(request);
  expect(error?.code).assertEqual(code);
  const message = error?.message ?? '';
  expect(message.includes('SELECT')).assertFalse();
  expect(message.includes('file://')).assertFalse();
  expect(message.includes('C:\\')).assertFalse();
}

function values(prefix: string, count: number, itemLength: number = 0): string[] {
  const result: string[] = [];
  for (let index = 0; index < count; index++) {
    const suffix = index.toString();
    result.push(itemLength === 0 ? prefix + suffix : (prefix + suffix).padEnd(itemLength, 'x'));
  }
  return result;
}

export default function sqlLikeCandidateQueryTest() {
  describe('SqlLikeCandidateQuery', () => {
    it('binds every user value and keeps deterministic database ordering and limit', 0, () => {
      const queryText = "transaction' OR 1=1 -- %_";
      const documentId = "doc' OR 1=1 --";
      const tag = "db%'_";
      const query: SqlLikeCandidateQuery | undefined = buildSqlLikeCandidateQuery({
        queryText: queryText,
        topK: 5,
        privacyLevel: 'PRIVATE_GROUP',
        filters: { documentIds: [documentId], tags: [tag], modalities: ['text'], updatedAfter: 10 }
      });

      expect(query === undefined).assertFalse();
      expect(query?.sql.includes(queryText)).assertFalse();
      expect(query?.sql.includes(documentId)).assertFalse();
      expect(query?.sql.includes(tag)).assertFalse();
      expect(JSON.stringify(query?.bindArgs).includes(documentId)).assertTrue();
      expect(JSON.stringify(query?.bindArgs).includes(tag)).assertTrue();
      expect(query?.sql.includes('ORDER BY raw_score DESC,document_id ASC,chunk_id ASC')).assertTrue();
      expect(query?.sql.endsWith('LIMIT ?')).assertTrue();
      expect(query?.sql.includes('normalized_text')).assertFalse();
      expect(query?.sql.includes('checksum')).assertFalse();
      expect(query?.sql.includes('created_at')).assertFalse();
    });

    it('caps deterministic terms and rejects empty analysis input', 0, () => {
      const manyTerms = buildSqlLikeCandidateQuery({
        queryText: 'alpha beta gamma delta epsilon zeta eta theta iota kappa lambda',
        topK: 20,
        privacyLevel: 'LOCAL_ONLY'
      });

      expect((manyTerms?.terms.length ?? 0) <= MAX_SQL_LIKE_SEARCH_TERMS).assertTrue();
      expectError({ queryText: '   ', topK: 20, privacyLevel: 'LOCAL_ONLY' }, 'E_QUERY_INVALID');
    });

    it('extracts a two-character Chinese search term without broadening it', 0, () => {
      const query = buildSqlLikeCandidateQuery({
        queryText: '\u9694\u79BB', topK: 5, privacyLevel: 'PRIVATE_GROUP'
      });
      expect(JSON.stringify(query?.terms)).assertEqual(JSON.stringify(['\u9694\u79BB']));
    });

    it('rejects empty oversized query text and invalid privacy before SQL generation', 0, () => {
      expectError(JSON.parse('{}') as KnowledgeRetrievalRequest, 'E_QUERY_INVALID');
      expectError({ queryText: ' ', topK: 1, privacyLevel: 'LOCAL_ONLY' }, 'E_QUERY_INVALID');
      expectError({ queryText: 'x'.repeat(1001), topK: 1, privacyLevel: 'LOCAL_ONLY' }, 'E_QUERY_INVALID');
      expectError({ queryText: 'database', topK: 1, privacyLevel: 'PUBLIC' as PrivacyLevel }, 'E_QUERY_INVALID');
    });

    it('rejects every unsafe topK form instead of normalizing it', 0, () => {
      for (const topK of [0, 21, Number.NaN, 1.5]) {
        expectError({ queryText: 'database', topK: topK, privacyLevel: 'LOCAL_ONLY' }, 'E_TOP_K_INVALID');
      }
    });

    it('rejects oversized duplicate and storage-reference filters', 0, () => {
      const invalidFilters: TaskRequestFilters[] = [
        JSON.parse('null') as TaskRequestFilters,
        JSON.parse('[]') as TaskRequestFilters,
        { documentIds: values('doc-', 101) }, { tags: values('tag-', 21) },
        { modalities: ['text', 'text'] }, { documentIds: ['same', 'same'] }, { tags: ['same', 'same'] },
        { documentIds: ['d'.repeat(201)] }, { tags: ['t'.repeat(65)] }, { tags: [''] },
        { documentIds: ['file:///private/data'] }, { tags: ['C:\\private\\data'] },
        { documentIds: [' /private/data'] }, { tags: [' \\\\server\\share'] },
        { updatedAfter: -1 }
      ];
      for (const filters of invalidFilters) {
        expectError({ queryText: 'database', topK: 1, privacyLevel: 'LOCAL_ONLY', filters: filters },
          'E_FILTER_INVALID');
      }
    });

    it('rejects every dangerous URI path and untrimmed SQL filter value', 0, () => {
      const unsafeValues: string[] = [
        ' doc-os', 'doc-os ', ' 操作系统 ', 'file:///private/a', 'file:/private/a',
        'content://provider/id', 'content:provider-id', 'datashare://provider/id',
        'datashare:provider-id', 'http://example.com', 'https://example.com', 'ftp://example.com',
        'data:text/plain,test', 'C:\\private\\a', 'C:/private/a', 'C:private\\a', '/data/private/a',
        '\\\\server\\share\\a', ' datashare:provider-id '
      ];
      for (const value of unsafeValues) {
        expectError({ queryText: 'database', topK: 1, privacyLevel: 'LOCAL_ONLY',
          filters: { documentIds: [value] } }, 'E_FILTER_INVALID');
        expectError({ queryText: 'database', topK: 1, privacyLevel: 'LOCAL_ONLY',
          filters: { tags: [value] } }, 'E_FILTER_INVALID');
      }
    });

    it('keeps ordinary business prefixes available to SQL filters', 0, () => {
      const query = buildSqlLikeCandidateQuery({
        queryText: 'database', topK: 5, privacyLevel: 'PRIVATE_GROUP',
        filters: {
          documentIds: ['doc-os', 'database:ACID'],
          tags: ['操作系统', 'ACID', 'transaction:isolation']
        }
      });
      expect(query === undefined).assertFalse();
    });

    it('accepts all exact request and filter boundaries', 0, () => {
      const query = buildSqlLikeCandidateQuery({
        queryText: 'q'.repeat(1000), topK: 20, privacyLevel: 'PRIVATE_GROUP',
        filters: {
          documentIds: values('d-', 100, 200), tags: values('t-', 20, 64),
          modalities: ['text', 'pdf', 'image', 'ocr_text'], updatedAfter: 0
        }
      });
      expect(query === undefined).assertFalse();
    });
  });
}
