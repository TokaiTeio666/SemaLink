import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LocalKnowledgeQuery, KnowledgePayloadLevel } from '../../../main/ets/contracts/knowledge/KnowledgeModels';
import { L1KnowledgePayload, L2KnowledgePayload } from '../../../main/ets/contracts/knowledge/KnowledgePayloadSchemas';
import { KnowledgeCompositionRoot } from '../../../main/ets/application/KnowledgeCompositionRoot';

interface DeviceBenchmarkQuery {
  text: string;
  expectedDocumentId: string;
}

const DEVICE_QUERIES: DeviceBenchmarkQuery[] = [
  { text: '进程和线程有什么区别', expectedDocumentId: 'doc-4964aabe' },
  { text: '时间片轮转适合什么类型的系统', expectedDocumentId: 'doc-6ba3ae2e' },
  { text: 'TCP 没有消息边界意味着什么', expectedDocumentId: 'doc-2988ddc9' },
  { text: '数据库事务的 ACID 分别表示什么', expectedDocumentId: 'doc-cb49d01e' },
  { text: 'B+树为什么适合范围查询和排序访问？', expectedDocumentId: 'doc-ef069176' },
  { text: 'Stage 模型中 UIAbility 的作用', expectedDocumentId: 'doc-26f55d0f' }
];

function percentile(values: number[], fraction: number): number {
  const sorted = values.slice().sort((left: number, right: number): number => left - right);
  const index = Math.max(0, Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1));
  return sorted.length === 0 ? 0 : sorted[index];
}

function deviceRequest(id: string, text: string, level: KnowledgePayloadLevel): LocalKnowledgeQuery {
  return {
    contractVersion: '1.0', requestId: id, queryText: text, topK: 5,
    requestedLevel: level, maxPayloadBytes: 4096
  };
}

function containsExpectedDocument(payloadJson: string, level: KnowledgePayloadLevel,
  expectedDocumentId: string): boolean {
  if (level === 'L1') {
    const payload = JSON.parse(payloadJson) as L1KnowledgePayload;
    return payload.items.some((item): boolean => item.documentId === expectedDocumentId);
  }
  const payload = JSON.parse(payloadJson) as L2KnowledgePayload;
  return payload.items.some((item): boolean => item.documentId === expectedDocumentId);
}

export default function deviceLocalRetrievalBenchmarkTest() {
  describe('DeviceLocalRetrievalBenchmark', () => {
    it('measures real ArkData gateway L1 and L2 retrieval', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const components = await KnowledgeCompositionRoot.create(ability.context);
      await components.repository.clearAll();
      try {
        const imported = await components.importer.importBuiltInDocuments();
        expect(imported.importedDocuments).assertEqual(12);
        const l1: number[] = [];
        const l2: number[] = [];
        for (let queryIndex = 0; queryIndex < DEVICE_QUERIES.length; queryIndex++) {
          const query = DEVICE_QUERIES[queryIndex];
          for (let warm = 0; warm < 2; warm++) {
            const warmL1 = await components.gateway.query(deviceRequest(
              'device-warm-l1-' + queryIndex.toString() + '-' + warm.toString(), query.text, 'L1'));
            const warmL2 = await components.gateway.query(deviceRequest(
              'device-warm-l2-' + queryIndex.toString() + '-' + warm.toString(), query.text, 'L2'));
            const warmL1Correct = containsExpectedDocument(warmL1.payloadJson, 'L1', query.expectedDocumentId);
            const warmL2Correct = containsExpectedDocument(warmL2.payloadJson, 'L2', query.expectedDocumentId);
            if (!warmL1Correct || !warmL2Correct) {
              hilog.error(0x0000, 'SemaLinkBench',
                'DEVICE_CORRECTNESS_FAILURE queryIndex=%{public}d expected=%{public}s l1=%{public}s l2=%{public}s',
                queryIndex, query.expectedDocumentId, warmL1Correct.toString(), warmL2Correct.toString());
            }
            expect(warmL1Correct).assertTrue();
            expect(warmL2Correct).assertTrue();
          }
          for (let run = 0; run < 8; run++) {
            const resultL1 = await components.gateway.query(deviceRequest(
              'device-l1-' + queryIndex.toString() + '-' + run.toString(), query.text, 'L1'));
            const resultL2 = await components.gateway.query(deviceRequest(
              'device-l2-' + queryIndex.toString() + '-' + run.toString(), query.text, 'L2'));
            expect(containsExpectedDocument(resultL1.payloadJson, 'L1', query.expectedDocumentId)).assertTrue();
            expect(containsExpectedDocument(resultL2.payloadJson, 'L2', query.expectedDocumentId)).assertTrue();
            l1.push(resultL1.retrievalMs);
            l2.push(resultL2.retrievalMs);
          }
        }
        const l1P50 = percentile(l1, 0.50);
        const l1P95 = percentile(l1, 0.95);
        const l2P50 = percentile(l2, 0.50);
        const l2P95 = percentile(l2, 0.95);
        const statistics = await components.repository.getStatistics();
        hilog.info(0x0000, 'SemaLinkBench',
          'DEVICE_LOCAL_RETRIEVAL documents=%{public}d chunks=%{public}d l1P50=%{public}d l1P95=%{public}d l2P50=%{public}d l2P95=%{public}d',
          statistics.documentCount, statistics.chunkCount, l1P50, l1P95, l2P50, l2P95);
        expect(l1P95 <= 200).assertTrue();
        expect(l2P95 <= 300).assertTrue();
      } finally {
        await components.repository.clearAll();
      }
    });
  });
}
