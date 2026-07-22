import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeError } from '../main/ets/contracts/knowledge/KnowledgeError';
import {
  KnowledgeQueryFilters,
  LocalKnowledgeQuery,
  LocalKnowledgeResult,
  KnowledgeProfile
} from '../main/ets/contracts/knowledge/KnowledgeModels';
import {
  KnowledgePayloadValidator,
  validateKnowledgeRequest
} from '../main/ets/contracts/knowledge/KnowledgePayloadValidator';
import { L1KnowledgePayload } from '../main/ets/contracts/knowledge/KnowledgePayloadSchemas';

function validQuery(): LocalKnowledgeQuery {
  return {
    contractVersion: '1.0',
    requestId: 'request-1',
    queryText: '进程和线程有什么区别',
    topK: 5,
    requestedLevel: 'L1',
    maxPayloadBytes: 4096
  };
}

interface RuntimeRequestHolder {
  request?: LocalKnowledgeQuery;
}

function validResult(): LocalKnowledgeResult {
  const payload: L1KnowledgePayload = {
    schemaVersion: '1.0',
    level: 'L1',
    items: [{
      evidenceId: 'ev-doc-1',
      documentId: 'doc-1',
      title: '进程与线程',
      summary: '进程是资源分配单位，线程是调度单位。',
      tags: ['操作系统'],
      relevance: 0.9,
      updatedAt: 1
    }]
  };
  return {
    contractVersion: '1.0',
    requestId: 'request-1',
    level: 'L1',
    itemCount: 1,
    payloadJson: JSON.stringify(payload),
    truncated: false,
    retrievalMs: 1,
    indexVersion: 'index-1',
    generatedAt: 1
  };
}

function expectCode(action: () => void, code: string): void {
  let actual = '';
  try {
    action();
  } catch (error) {
    if (error instanceof KnowledgeError) {
      actual = error.code;
    }
  }
  expect(actual).assertEqual(code);
}

function expectSafeCode(action: () => void, code: string): void {
  let actual = '';
  let message = '';
  try {
    action();
  } catch (error) {
    if (error instanceof KnowledgeError) {
      actual = error.code;
      message = error.message;
    }
  }
  expect(actual).assertEqual(code);
  expect(message.includes('runtime-secret')).assertFalse();
  expect(message.includes('SELECT ')).assertFalse();
  expect(message.includes('\n    at ')).assertFalse();
}

export default function knowledgePayloadValidatorTest() {
  describe('KnowledgePayloadValidator', () => {
    it('accepts request boundary values', 0, () => {
      const low = validQuery();
      low.topK = 1;
      low.maxPayloadBytes = 1024;
      validateKnowledgeRequest(low);
      const high = validQuery();
      high.topK = 20;
      high.maxPayloadBytes = 262144;
      validateKnowledgeRequest(high);
      expect(true).assertTrue();
    });

    it('rejects invalid query boundaries', 0, () => {
      const empty = validQuery();
      empty.queryText = '  ';
      expectCode((): void => validateKnowledgeRequest(empty), 'E_QUERY_INVALID');
      const topK = validQuery();
      topK.topK = 21;
      expectCode((): void => validateKnowledgeRequest(topK), 'E_TOP_K_INVALID');
      const zeroTopK = validQuery();
      zeroTopK.topK = 0;
      expectCode((): void => validateKnowledgeRequest(zeroTopK), 'E_TOP_K_INVALID');
      const nanTopK = validQuery();
      nanTopK.topK = Number.parseInt('not-a-number');
      expectCode((): void => validateKnowledgeRequest(nanTopK), 'E_TOP_K_INVALID');
      const budget = validQuery();
      budget.maxPayloadBytes = 1023;
      expectCode((): void => validateKnowledgeRequest(budget), 'E_PAYLOAD_BUDGET_INVALID');
    });

    it('rejects malformed legacy request roots without leaking runtime errors', 0, () => {
      const holder: RuntimeRequestHolder = {};
      const malformedRequests: LocalKnowledgeQuery[] = [
        JSON.parse('null') as LocalKnowledgeQuery,
        holder.request!,
        JSON.parse('{}') as LocalKnowledgeQuery
      ];
      for (const malformedRequest of malformedRequests) {
        expectSafeCode((): void => validateKnowledgeRequest(malformedRequest), 'E_QUERY_INVALID');
      }
    });

    it('rejects malformed legacy filter containers and arrays safely', 0, () => {
      const malformedFilters: KnowledgeQueryFilters[] = [
        JSON.parse('null') as KnowledgeQueryFilters,
        JSON.parse('[]') as KnowledgeQueryFilters,
        JSON.parse('{"documentIds":"runtime-secret"}') as KnowledgeQueryFilters,
        JSON.parse('{"tags":"runtime-secret"}') as KnowledgeQueryFilters,
        JSON.parse('{"modalities":"runtime-secret"}') as KnowledgeQueryFilters,
        JSON.parse('{"documentIds":[1]}') as KnowledgeQueryFilters,
        JSON.parse('{"tags":[1]}') as KnowledgeQueryFilters,
        JSON.parse('{"modalities":[1]}') as KnowledgeQueryFilters
      ];
      for (const malformedFilter of malformedFilters) {
        const query = validQuery();
        query.filters = malformedFilter;
        expectSafeCode((): void => validateKnowledgeRequest(query), 'E_FILTER_INVALID');
      }
    });

    it('enforces legacy filter count length uniqueness and timestamp bounds', 0, () => {
      const invalidFilters: KnowledgeQueryFilters[] = [];
      const documentIds: string[] = [];
      for (let index = 0; index < 101; index++) documentIds.push('doc-' + index.toString());
      invalidFilters.push({ documentIds: documentIds });
      invalidFilters.push({ documentIds: ['x'.repeat(201)] });
      invalidFilters.push({ documentIds: ['doc-1', 'doc-1'] });
      const tags: string[] = [];
      for (let index = 0; index < 21; index++) tags.push('tag-' + index.toString());
      invalidFilters.push({ tags: tags });
      invalidFilters.push({ tags: ['x'.repeat(65)] });
      invalidFilters.push({ tags: ['tag-1', 'tag-1'] });
      invalidFilters.push({ modalities: ['text', 'pdf', 'image', 'ocr_text', 'text'] });
      invalidFilters.push({ modalities: ['text', 'text'] });
      invalidFilters.push({ updatedAfter: -1 });
      invalidFilters.push({ updatedAfter: 1.5 });
      for (const invalidFilter of invalidFilters) {
        const query = validQuery();
        query.filters = invalidFilter;
        expectCode((): void => validateKnowledgeRequest(query), 'E_FILTER_INVALID');
      }
    });

    it('rejects unsupported version and invalid filters', 0, () => {
      const version = validQuery();
      version.contractVersion = '2.0' as '1.0';
      expectCode((): void => validateKnowledgeRequest(version), 'E_CONTRACT_VERSION_UNSUPPORTED');
      const filters = validQuery();
      filters.filters = { tags: ['  '] };
      expectCode((): void => validateKnowledgeRequest(filters), 'E_FILTER_INVALID');
    });

    it('rejects unsafe storage references and untrimmed filter values', 0, () => {
      const unsafeValues: string[] = [
        ' doc-os', 'doc-os ', ' 操作系统 ', 'file:///private/a', 'file:/private/a',
        'content://provider/id', 'content:provider-id', 'datashare://provider/id',
        'datashare:provider-id', 'http://example.com', 'https://example.com', 'ftp://example.com',
        'data:text/plain,test', 'C:\\private\\a', 'C:/private/a', 'C:private\\a', '/data/private/a',
        '\\\\server\\share\\a', ' file:///private/a '
      ];
      for (const value of unsafeValues) {
        const documentQuery = validQuery();
        documentQuery.filters = { documentIds: [value] };
        expectCode((): void => validateKnowledgeRequest(documentQuery), 'E_FILTER_INVALID');
        const tagQuery = validQuery();
        tagQuery.filters = { tags: [value] };
        expectCode((): void => validateKnowledgeRequest(tagQuery), 'E_FILTER_INVALID');
      }
    });

    it('accepts plain and business-prefixed filter values', 0, () => {
      const query = validQuery();
      query.filters = {
        documentIds: ['doc-os', 'database', 'database:ACID'],
        tags: ['操作系统', 'ACID', 'transaction:isolation']
      };
      validateKnowledgeRequest(query);
      expect(true).assertTrue();
    });

    it('validates a legal L1 result', 0, () => {
      new KnowledgePayloadValidator().validateResult(validQuery(), validResult());
      expect(true).assertTrue();
    });

    it('rejects item count mismatch', 0, () => {
      const result = validResult();
      result.itemCount = 2;
      expectCode((): void => new KnowledgePayloadValidator().validateResult(validQuery(), result), 'E_PAYLOAD_INVALID');
    });

    it('rejects malformed JSON and mismatched level', 0, () => {
      const malformed = validResult();
      malformed.payloadJson = '{';
      expectCode((): void => new KnowledgePayloadValidator().validateResult(validQuery(), malformed),
        'E_PAYLOAD_INVALID');
      const level = validResult();
      level.level = 'L2';
      expectCode((): void => new KnowledgePayloadValidator().validateResult(validQuery(), level),
        'E_PAYLOAD_INVALID');
    });

    it('rejects duplicate evidence and invalid relevance order', 0, () => {
      const payload: L1KnowledgePayload = {
        schemaVersion: '1.0', level: 'L1',
        items: [
          { evidenceId: 'same', documentId: 'a', title: 'A', summary: 'A', tags: [], relevance: 0.4, updatedAt: 1 },
          { evidenceId: 'same', documentId: 'b', title: 'B', summary: 'B', tags: [], relevance: 0.8, updatedAt: 1 }
        ]
      };
      const result = validResult();
      result.itemCount = 2;
      result.payloadJson = JSON.stringify(payload);
      expectCode((): void => new KnowledgePayloadValidator().validateResult(validQuery(), result),
        'E_PAYLOAD_INVALID');
    });

    it('validates keyword-only profile', 0, () => {
      const profile: KnowledgeProfile = {
        contractVersion: '1.0',
        profileVersion: 'profile-1',
        indexState: 'EMPTY',
        knowledgeDomains: [],
        documentCount: 0,
        chunkCount: 0,
        modalities: [],
        retrievalModes: ['keyword'],
        supportedLevels: ['L1', 'L2'],
        indexVersion: 'index-empty',
        embeddingModelVersion: '',
        updatedAt: 0
      };
      new KnowledgePayloadValidator().validateProfile(profile);
      expect(true).assertTrue();
    });
  });
}
