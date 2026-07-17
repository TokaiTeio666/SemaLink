import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LocalKnowledgeQuery, KnowledgePayloadLevel } from '../../../main/ets/contracts/knowledge/KnowledgeModels';
import { L1KnowledgePayload, L2KnowledgePayload } from '../../../main/ets/contracts/knowledge/KnowledgePayloadSchemas';
import { KnowledgeCompositionRoot } from '../../../main/ets/application/KnowledgeCompositionRoot';
import { RdbDocumentRepository } from '../../../main/ets/knowledge/storage/RdbDocumentRepository';
import {
  ANSWERABLE_BENCHMARK_QUERIES,
  AnswerableBenchmarkQuery,
  BenchmarkSplit,
  NO_ANSWER_BENCHMARK_QUERIES,
  NoAnswerBenchmarkQuery
} from '../../../test/benchmark/LocalRetrievalBenchmarkDataset';

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

function l2DocumentIds(payloadJson: string): string[] {
  const payload = JSON.parse(payloadJson) as L2KnowledgePayload;
  const ids: string[] = [];
  for (const item of payload.items) {
    if (ids.indexOf(item.documentId) < 0) ids.push(item.documentId);
  }
  return ids;
}

function expectedRank(actual: string[], expected: string[]): number {
  for (let index = 0; index < actual.length; index++) {
    if (expected.indexOf(actual[index]) >= 0) return index + 1;
  }
  return 0;
}

interface SplitBenchmarkCount {
  answerable: number;
  noAnswer: number;
  top1: number;
  top5: number;
  rejected: number;
}

function emptySplitCount(): SplitBenchmarkCount {
  return { answerable: 0, noAnswer: 0, top1: 0, top5: 0, rejected: 0 };
}

function splitCount(split: BenchmarkSplit, development: SplitBenchmarkCount,
  holdout: SplitBenchmarkCount): SplitBenchmarkCount {
  return split === 'development' ? development : holdout;
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
              const diagnosticCandidates = await (components.repository as RdbDocumentRepository).searchCandidates({
                queryText: query.text, topK: 5, privacyLevel: 'LOCAL_ONLY'
              });
              let expectedRank = 0;
              for (let candidateIndex = 0; candidateIndex < diagnosticCandidates.length; candidateIndex++) {
                if (diagnosticCandidates[candidateIndex].document.documentId === query.expectedDocumentId) {
                  expectedRank = candidateIndex + 1;
                  break;
                }
              }
              hilog.error(0x0000, 'SemaLinkBench',
                'DEVICE_CORRECTNESS_FAILURE queryIndex=%{public}d expectedRank=%{public}d candidates=%{public}d ' +
                'l1=%{public}s l2=%{public}s', queryIndex, expectedRank, diagnosticCandidates.length,
                warmL1Correct.toString(), warmL2Correct.toString());
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

    it('meets the full fixed ranking and rejection gates through real database retrieval', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const components = await KnowledgeCompositionRoot.create(ability.context);
      await components.repository.clearAll();
      try {
        await components.importer.importBuiltInDocuments();
        const repository = components.repository as RdbDocumentRepository;
        repository.resetSearchDiagnostics();
        const development = emptySplitCount();
        const holdout = emptySplitCount();
        const latencies: number[] = [];
        for (let queryIndex = 0; queryIndex < ANSWERABLE_BENCHMARK_QUERIES.length; queryIndex++) {
          const answerable = ANSWERABLE_BENCHMARK_QUERIES[queryIndex] as AnswerableBenchmarkQuery;
          const result = await components.gateway.query(deviceRequest(
            'rdb-full-' + answerable.queryId, answerable.queryText, 'L2'));
          const count = splitCount(answerable.split, development, holdout);
          const rank = expectedRank(l2DocumentIds(result.payloadJson), answerable.expectedDocumentIds);
          count.answerable += 1;
          if (rank === 1) count.top1 += 1;
          if (rank > 0 && rank <= 5) count.top5 += 1;
          latencies.push(result.retrievalMs);
        }
        for (let queryIndex = 0; queryIndex < NO_ANSWER_BENCHMARK_QUERIES.length; queryIndex++) {
          const noAnswer = NO_ANSWER_BENCHMARK_QUERIES[queryIndex] as NoAnswerBenchmarkQuery;
          const result = await components.gateway.query(deviceRequest(
            'rdb-full-' + noAnswer.queryId, noAnswer.queryText, 'L2'));
          const count = splitCount(noAnswer.split, development, holdout);
          count.noAnswer += 1;
          if (result.itemCount === 0) count.rejected += 1;
        }
        const diagnostics = repository.getSearchDiagnostics();
        const devTop1 = development.top1 / development.answerable;
        const devTop5 = development.top5 / development.answerable;
        const holdoutTop1 = holdout.top1 / holdout.answerable;
        const holdoutTop5 = holdout.top5 / holdout.answerable;
        const devRejection = development.rejected / development.noAnswer;
        const holdoutRejection = holdout.rejected / holdout.noAnswer;
        const p50 = percentile(latencies, 0.50);
        const p95 = percentile(latencies, 0.95);
        hilog.info(0x0000, 'SemaLinkBench',
          'RDB_FULL devTop1=%{public}d devTop5=%{public}d holdoutTop1=%{public}d holdoutTop5=%{public}d ' +
          'devReject=%{public}d holdoutReject=%{public}d p50=%{public}d p95=%{public}d rows=%{public}d fullReads=%{public}d',
          Math.round(devTop1 * 10000), Math.round(devTop5 * 10000), Math.round(holdoutTop1 * 10000),
          Math.round(holdoutTop5 * 10000), Math.round(devRejection * 10000),
          Math.round(holdoutRejection * 10000), p50, p95, diagnostics.candidateRowsReturned,
          diagnostics.fullReadCallsDuringSearch);
        expect(devTop1 >= 0.90).assertTrue();
        expect(devTop5).assertEqual(1);
        expect(holdoutTop1 >= 0.70).assertTrue();
        expect(holdoutTop5).assertEqual(1);
        expect(devRejection).assertEqual(1);
        expect(holdoutRejection).assertEqual(1);
        expect(p95 <= 150).assertTrue();
        expect(diagnostics.fullReadCallsDuringSearch).assertEqual(0);
        expect(diagnostics.searchCalls).assertEqual(
          ANSWERABLE_BENCHMARK_QUERIES.length + NO_ANSWER_BENCHMARK_QUERIES.length);
      } finally {
        await components.repository.clearAll();
        components.database.close();
      }
    });
  });
}
