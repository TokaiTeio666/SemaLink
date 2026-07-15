import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeError } from '../main/ets/contracts/knowledge/KnowledgeError';
import {
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

    it('rejects unsupported version and invalid filters', 0, () => {
      const version = validQuery();
      version.contractVersion = '2.0' as '1.0';
      expectCode((): void => validateKnowledgeRequest(version), 'E_CONTRACT_VERSION_UNSUPPORTED');
      const filters = validQuery();
      filters.filters = { tags: ['  '] };
      expectCode((): void => validateKnowledgeRequest(filters), 'E_FILTER_INVALID');
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
