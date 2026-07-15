import { KnowledgePayloadValidator } from '../../main/ets/contracts/knowledge/KnowledgePayloadValidator';
import { L1KnowledgePayload, L2KnowledgePayload } from '../../main/ets/contracts/knowledge/KnowledgePayloadSchemas';
import { KnowledgePayloadLevel, LocalKnowledgeQuery, LocalKnowledgeResult } from '../../main/ets/contracts/knowledge/KnowledgeModels';
import { DocumentChunker } from '../../main/ets/knowledge/import/DocumentChunker';
import { DocumentChunk } from '../../main/ets/knowledge/model/DocumentChunk';
import { KnowledgeDocument } from '../../main/ets/knowledge/model/KnowledgeDocument';
import { L1PayloadBuilder } from '../../main/ets/knowledge/payload/L1PayloadBuilder';
import { L2PayloadBuilder } from '../../main/ets/knowledge/payload/L2PayloadBuilder';
import { KnowledgeProfileBuilder } from '../../main/ets/knowledge/profile/KnowledgeProfileBuilder';
import { KeywordRetrievalEngine } from '../../main/ets/knowledge/retrieval/KeywordRetrievalEngine';
import { ArkDataLocalKnowledgeService } from '../../main/ets/knowledge/service/ArkDataLocalKnowledgeService';
import {
  ANSWERABLE_BENCHMARK_QUERIES,
  AnswerableBenchmarkQuery,
  BenchmarkSplit,
  NO_ANSWER_BENCHMARK_QUERIES,
  NoAnswerBenchmarkQuery
} from './LocalRetrievalBenchmarkDataset';
import { BenchmarkCorpus, benchmarkDocumentIds, createBenchmarkCorpus } from './LocalRetrievalBenchmarkDocuments';
import { InMemoryBenchmarkRepository } from './InMemoryBenchmarkRepository';

export interface RankingMetrics {
  split: BenchmarkSplit;
  answerableQueryCount: number;
  noAnswerQueryCount: number;
  top1Accuracy: number;
  top3Recall: number;
  top5Recall: number;
  mrr: number;
  querySuccessRate: number;
  noAnswerRejectionRate: number;
  falsePositiveRate: number;
}

export interface CandidateDiagnostic {
  documentId: string;
  relevance: number;
  matchedPrimaryTerms: string[];
  matchedNgrams: string[];
  exactPhraseMatched: boolean;
}

export interface BenchmarkFailure {
  queryId: string;
  queryText: string;
  split: BenchmarkSplit;
  failureType: string;
  expectedDocumentIds: string[];
  actualTop5: CandidateDiagnostic[];
}

export interface LatencyMetrics {
  level: KnowledgePayloadLevel;
  topK: number;
  sampleCount: number;
  averageMs: number;
  p50Ms: number;
  p95Ms: number;
  minimumMs: number;
  maximumMs: number;
}

export interface ScaleMetrics {
  documentCount: number;
  chunkCount: number;
  scannedCandidateCount: number;
  l1P50Ms: number;
  l1P95Ms: number;
  l2P50Ms: number;
  l2P95Ms: number;
  maximumMs: number;
}

export interface BenchmarkReport {
  schemaVersion: '1.0';
  benchmarkKind: 'local-document-retrieval';
  generatedAt: number;
  dataset: BenchmarkDatasetSummary;
  development: RankingMetrics;
  holdout: RankingMetrics;
  latency: LatencyMetrics[];
  scale: ScaleMetrics[];
  failures: BenchmarkFailure[];
}

export interface BenchmarkDatasetSummary {
  documentCount: number;
  chunkCount: number;
  answerableQueryCount: number;
  noAnswerQueryCount: number;
  developmentQueryCount: number;
  holdoutQueryCount: number;
  warmupRunsPerQuery: number;
  measuredRunsPerQuery: number;
}

interface RankEvaluation {
  rank: number;
  documentIds: string[];
}

const WARMUP_RUNS: number = 2;
const MEASURED_RUNS: number = 8;

function rounded(value: number): number {
  return Math.round(value * 10000) / 10000;
}

function containsExpected(actual: string[], expected: string[]): boolean {
  for (const documentId of actual) {
    if (expected.indexOf(documentId) >= 0) {
      return true;
    }
  }
  return false;
}

function percentile(sorted: number[], fraction: number): number {
  if (sorted.length === 0) {
    return 0;
  }
  const rank = Math.ceil(fraction * sorted.length) - 1;
  return sorted[Math.max(0, Math.min(sorted.length - 1, rank))];
}

function summarizeLatency(level: KnowledgePayloadLevel, topK: number, values: number[]): LatencyMetrics {
  const sorted = values.slice().sort((left: number, right: number): number => left - right);
  let total = 0;
  for (const value of sorted) {
    total += value;
  }
  return {
    level: level, topK: topK, sampleCount: sorted.length,
    averageMs: sorted.length === 0 ? 0 : rounded(total / sorted.length),
    p50Ms: percentile(sorted, 0.50), p95Ms: percentile(sorted, 0.95),
    minimumMs: sorted.length === 0 ? 0 : sorted[0],
    maximumMs: sorted.length === 0 ? 0 : sorted[sorted.length - 1]
  };
}

function request(queryId: string, queryText: string, level: KnowledgePayloadLevel, topK: number): LocalKnowledgeQuery {
  return {
    contractVersion: '1.0', requestId: queryId, queryText: queryText, topK: topK,
    requestedLevel: level, maxPayloadBytes: 4096
  };
}

function resultDocumentIds(result: LocalKnowledgeResult): string[] {
  const ids: string[] = [];
  if (result.level === 'L1') {
    const payload = JSON.parse(result.payloadJson) as L1KnowledgePayload;
    for (const item of payload.items) {
      ids.push(item.documentId);
    }
  } else {
    const payload = JSON.parse(result.payloadJson) as L2KnowledgePayload;
    for (const item of payload.items) {
      if (ids.indexOf(item.documentId) < 0) {
        ids.push(item.documentId);
      }
    }
  }
  return ids;
}

function rankOf(actual: string[], expected: string[]): number {
  for (let index = 0; index < actual.length; index++) {
    if (expected.indexOf(actual[index]) >= 0) {
      return index + 1;
    }
  }
  return 0;
}

function createGateway(corpus: BenchmarkCorpus): ArkDataLocalKnowledgeService {
  return new ArkDataLocalKnowledgeService(
    new InMemoryBenchmarkRepository(corpus.documents, corpus.chunks),
    new KeywordRetrievalEngine(), new L1PayloadBuilder(), new L2PayloadBuilder(),
    new KnowledgeProfileBuilder(), new KnowledgePayloadValidator()
  );
}

function queriesForSplit(split: BenchmarkSplit): AnswerableBenchmarkQuery[] {
  const selected: AnswerableBenchmarkQuery[] = [];
  for (const query of ANSWERABLE_BENCHMARK_QUERIES) {
    if (query.split === split) {
      selected.push(query);
    }
  }
  return selected;
}

function noAnswerForSplit(split: BenchmarkSplit): NoAnswerBenchmarkQuery[] {
  const selected: NoAnswerBenchmarkQuery[] = [];
  for (const query of NO_ANSWER_BENCHMARK_QUERIES) {
    if (query.split === split) {
      selected.push(query);
    }
  }
  return selected;
}

function scaleText(index: number): string {
  const domains: string[] = ['并发锁队列', 'TCP协议超时', '数据库索引事务', '软件测试需求', 'HarmonyOS组件生命周期'];
  const disturbances: string[] = ['性能日志', '状态同步', '资源预算', '接口边界', '故障恢复'];
  const domain = domains[index % domains.length];
  const disturbance = disturbances[(index * 3) % disturbances.length];
  return ('规模文档 ' + index.toString() + ' 讨论 ' + domain + '，并包含 ' + disturbance +
    ' 的工程背景。该段落用于确定性性能趋势，不作为真实准确率答案。').repeat(8);
}

function createScaleCorpus(targetCount: number): BenchmarkCorpus {
  const base = createBenchmarkCorpus();
  if (targetCount <= base.documents.length) {
    return base;
  }
  const chunker = new DocumentChunker();
  for (let index = base.documents.length; index < targetCount; index++) {
    const padded = index.toString().padStart(4, '0');
    const text = scaleText(index);
    const document: KnowledgeDocument = {
      documentId: 'scale-doc-' + padded, title: '规模趋势文档 ' + padded, modality: 'text',
      normalizedText: text, tags: ['规模测试', '工程'], checksum: 'scale-' + padded,
      createdAt: 1783958400000 + index, updatedAt: 1783958400000 + index
    };
    base.documents.push(document);
    const chunks: DocumentChunk[] = chunker.chunkDocument(document.documentId, text, document.updatedAt);
    for (const chunk of chunks) {
      base.chunks.push(chunk);
    }
  }
  return base;
}

export class LocalRetrievalBenchmarkRunner {
  validateDataset(): string[] {
    const errors: string[] = [];
    const documentIds = benchmarkDocumentIds();
    const perDocument: Map<string, number> = new Map<string, number>();
    const queryIds: Set<string> = new Set<string>();
    let development = 0;
    let holdout = 0;
    for (const query of ANSWERABLE_BENCHMARK_QUERIES) {
      if (queryIds.has(query.queryId)) {
        errors.push('duplicate queryId: ' + query.queryId);
      }
      queryIds.add(query.queryId);
      if (query.queryText.trim().length === 0 || query.expectedDocumentIds.length === 0) {
        errors.push('invalid answerable query: ' + query.queryId);
      }
      for (const expectedId of query.expectedDocumentIds) {
        if (documentIds.indexOf(expectedId) < 0) {
          errors.push('unknown documentId: ' + expectedId);
        }
        perDocument.set(expectedId, (perDocument.get(expectedId) || 0) + 1);
      }
      if (query.split === 'development') {
        development += 1;
      } else {
        holdout += 1;
      }
    }
    for (const query of NO_ANSWER_BENCHMARK_QUERIES) {
      if (queryIds.has(query.queryId) || query.expectedDocumentIds.length !== 0) {
        errors.push('invalid no-answer query: ' + query.queryId);
      }
      queryIds.add(query.queryId);
      if (query.split === 'development') {
        development += 1;
      } else {
        holdout += 1;
      }
    }
    for (const documentId of documentIds) {
      if ((perDocument.get(documentId) || 0) < 4) {
        errors.push('document has fewer than four queries: ' + documentId);
      }
    }
    if (ANSWERABLE_BENCHMARK_QUERIES.length < 60 || NO_ANSWER_BENCHMARK_QUERIES.length < 20) {
      errors.push('dataset is smaller than required');
    }
    if (development * 3 !== holdout * 7) {
      errors.push('development/holdout split is not 70/30');
    }
    return errors;
  }

  private diagnostics(queryId: string, queryText: string, corpus: BenchmarkCorpus): CandidateDiagnostic[] {
    const candidates = new KeywordRetrievalEngine().search(
      request('diagnostic-' + queryId, queryText, 'L2', 5), corpus.documents, corpus.chunks);
    const diagnostics: CandidateDiagnostic[] = [];
    for (const candidate of candidates) {
      diagnostics.push({
        documentId: candidate.document.documentId, relevance: candidate.relevance,
        matchedPrimaryTerms: candidate.matchedPrimaryTerms,
        matchedNgrams: candidate.matchedNgrams,
        exactPhraseMatched: candidate.exactPhraseMatched
      });
    }
    return diagnostics;
  }

  private async evaluateSplit(split: BenchmarkSplit, corpus: BenchmarkCorpus,
    failures: BenchmarkFailure[]): Promise<RankingMetrics> {
    const gateway = createGateway(corpus);
    const answerable = queriesForSplit(split);
    const noAnswer = noAnswerForSplit(split);
    let top1 = 0;
    let top3 = 0;
    let top5 = 0;
    let reciprocalRank = 0;
    let successful = 0;
    let rejected = 0;
    for (const query of answerable) {
      const result = await gateway.query(request(query.queryId, query.queryText, 'L2', 5));
      const ids = resultDocumentIds(result);
      const rank = rankOf(ids, query.expectedDocumentIds);
      if (rank === 1) {
        top1 += 1;
      }
      if (rank > 0 && rank <= 3) {
        top3 += 1;
      }
      if (rank > 0 && rank <= 5) {
        top5 += 1;
        successful += 1;
      } else {
        failures.push({
          queryId: query.queryId, queryText: query.queryText, split: split,
          failureType: 'expected document absent from Top-5', expectedDocumentIds: query.expectedDocumentIds,
          actualTop5: this.diagnostics(query.queryId, query.queryText, corpus)
        });
      }
      if (rank > 0) {
        reciprocalRank += 1 / rank;
      }
    }
    for (const query of noAnswer) {
      const result = await gateway.query(request(query.queryId, query.queryText, 'L2', 5));
      if (result.itemCount === 0) {
        rejected += 1;
      } else {
        failures.push({
          queryId: query.queryId, queryText: query.queryText, split: split,
          failureType: 'false positive for no-answer query', expectedDocumentIds: [],
          actualTop5: this.diagnostics(query.queryId, query.queryText, corpus)
        });
      }
    }
    return {
      split: split, answerableQueryCount: answerable.length, noAnswerQueryCount: noAnswer.length,
      top1Accuracy: rounded(top1 / answerable.length), top3Recall: rounded(top3 / answerable.length),
      top5Recall: rounded(top5 / answerable.length), mrr: rounded(reciprocalRank / answerable.length),
      querySuccessRate: rounded(successful / answerable.length),
      noAnswerRejectionRate: rounded(rejected / noAnswer.length),
      falsePositiveRate: rounded((noAnswer.length - rejected) / noAnswer.length)
    };
  }

  private async measureLatency(corpus: BenchmarkCorpus, level: KnowledgePayloadLevel,
    topK: number): Promise<LatencyMetrics> {
    const gateway = createGateway(corpus);
    const samples: number[] = [];
    for (const query of ANSWERABLE_BENCHMARK_QUERIES) {
      for (let run = 0; run < WARMUP_RUNS; run++) {
        await gateway.query(request('warm-' + run.toString() + '-' + query.queryId, query.queryText, level, topK));
      }
      for (let run = 0; run < MEASURED_RUNS; run++) {
        const result = await gateway.query(request('measure-' + run.toString() + '-' + query.queryId,
          query.queryText, level, topK));
        samples.push(result.retrievalMs);
      }
    }
    return summarizeLatency(level, topK, samples);
  }

  private async measureScale(documentCount: number): Promise<ScaleMetrics> {
    const corpus = createScaleCorpus(documentCount);
    const l1: number[] = [];
    const l2: number[] = [];
    const selected: AnswerableBenchmarkQuery[] = ANSWERABLE_BENCHMARK_QUERIES.slice(0, 6);
    const gateway = createGateway(corpus);
    for (const query of selected) {
      for (let warm = 0; warm < WARMUP_RUNS; warm++) {
        await gateway.query(request('scale-warm-l1-' + warm.toString(), query.queryText, 'L1', 5));
        await gateway.query(request('scale-warm-l2-' + warm.toString(), query.queryText, 'L2', 5));
      }
      for (let run = 0; run < MEASURED_RUNS; run++) {
        l1.push((await gateway.query(request('scale-l1-' + run.toString(), query.queryText, 'L1', 5))).retrievalMs);
        l2.push((await gateway.query(request('scale-l2-' + run.toString(), query.queryText, 'L2', 5))).retrievalMs);
      }
    }
    const l1Summary = summarizeLatency('L1', 5, l1);
    const l2Summary = summarizeLatency('L2', 5, l2);
    return {
      documentCount: corpus.documents.length, chunkCount: corpus.chunks.length,
      scannedCandidateCount: corpus.chunks.length, l1P50Ms: l1Summary.p50Ms,
      l1P95Ms: l1Summary.p95Ms, l2P50Ms: l2Summary.p50Ms, l2P95Ms: l2Summary.p95Ms,
      maximumMs: Math.max(l1Summary.maximumMs, l2Summary.maximumMs)
    };
  }

  async runFull(): Promise<BenchmarkReport> {
    const corpus = createBenchmarkCorpus();
    const failures: BenchmarkFailure[] = [];
    const development = await this.evaluateSplit('development', corpus, failures);
    const holdout = await this.evaluateSplit('holdout', corpus, failures);
    const latency: LatencyMetrics[] = [];
    const levels: KnowledgePayloadLevel[] = ['L1', 'L2'];
    const topKs: number[] = [1, 3, 5];
    for (const level of levels) {
      for (const topK of topKs) {
        latency.push(await this.measureLatency(corpus, level, topK));
      }
    }
    const scale: ScaleMetrics[] = [];
    const sizes: number[] = [12, 100, 500, 1000];
    for (const size of sizes) {
      scale.push(await this.measureScale(size));
    }
    return {
      schemaVersion: '1.0', benchmarkKind: 'local-document-retrieval', generatedAt: Date.now(),
      dataset: {
        documentCount: corpus.documents.length, chunkCount: corpus.chunks.length,
        answerableQueryCount: ANSWERABLE_BENCHMARK_QUERIES.length,
        noAnswerQueryCount: NO_ANSWER_BENCHMARK_QUERIES.length,
        developmentQueryCount: development.answerableQueryCount + development.noAnswerQueryCount,
        holdoutQueryCount: holdout.answerableQueryCount + holdout.noAnswerQueryCount,
        warmupRunsPerQuery: WARMUP_RUNS, measuredRunsPerQuery: MEASURED_RUNS
      },
      development: development, holdout: holdout, latency: latency, scale: scale, failures: failures
    };
  }

  toMarkdown(report: BenchmarkReport): string {
    const lines: string[] = [];
    lines.push('# SemaLink 本地知识检索性能实测');
    lines.push('');
    lines.push('> 本报告仅描述本地文档检索，不是设备路由或跨设备通信性能。retrievalMs 不含网络和 UI 渲染。');
    lines.push('');
    lines.push('## 数据集与方法');
    lines.push('');
    lines.push('- 测试时间戳：' + report.generatedAt.toString());
    lines.push('- 文档数：' + report.dataset.documentCount.toString());
    lines.push('- 分块数：' + report.dataset.chunkCount.toString());
    lines.push('- 有答案查询：' + report.dataset.answerableQueryCount.toString());
    lines.push('- 无答案查询：' + report.dataset.noAnswerQueryCount.toString());
    lines.push('- development / holdout：' + report.dataset.developmentQueryCount.toString() + ' / ' +
      report.dataset.holdoutQueryCount.toString());
    lines.push('- 每条查询预热 / 正式重复：' + report.dataset.warmupRunsPerQuery.toString() + ' / ' +
      report.dataset.measuredRunsPerQuery.toString());
    lines.push('- 准确率主评测：L2、topK=5、maxPayloadBytes=4096');
    lines.push('');
    lines.push('## 准确率');
    lines.push('');
    lines.push('| 集合 | Top-1 | Top-3 | Top-5 | MRR | Query Success | 无答案拒绝率 | 假阳性率 |');
    lines.push('|---|---:|---:|---:|---:|---:|---:|---:|');
    lines.push(this.rankingRow(report.development));
    lines.push(this.rankingRow(report.holdout));
    lines.push('');
    lines.push('## L1 / L2 主机本地耗时');
    lines.push('');
    lines.push('| Level | Top-K | 样本 | 平均 ms | P50 ms | P95 ms | 最小 ms | 最大 ms |');
    lines.push('|---|---:|---:|---:|---:|---:|---:|---:|');
    for (const latency of report.latency) {
      lines.push('| ' + latency.level + ' | ' + latency.topK.toString() + ' | ' + latency.sampleCount.toString() +
        ' | ' + latency.averageMs.toString() + ' | ' + latency.p50Ms.toString() + ' | ' +
        latency.p95Ms.toString() + ' | ' + latency.minimumMs.toString() + ' | ' +
        latency.maximumMs.toString() + ' |');
    }
    lines.push('');
    lines.push('## 规模趋势（不用于宣称真实准确率）');
    lines.push('');
    lines.push('| 文档 | 分块 | 每次扫描候选 | L1 P50 | L1 P95 | L2 P50 | L2 P95 | 最大 ms |');
    lines.push('|---:|---:|---:|---:|---:|---:|---:|---:|');
    for (const scale of report.scale) {
      lines.push('| ' + scale.documentCount.toString() + ' | ' + scale.chunkCount.toString() + ' | ' +
        scale.scannedCandidateCount.toString() + ' | ' + scale.l1P50Ms.toString() + ' | ' +
        scale.l1P95Ms.toString() + ' | ' + scale.l2P50Ms.toString() + ' | ' +
        scale.l2P95Ms.toString() + ' | ' + scale.maximumMs.toString() + ' |');
    }
    lines.push('');
    lines.push('## 失败问题');
    lines.push('');
    if (report.failures.length === 0) {
      lines.push('- 无。');
    } else {
      for (const failure of report.failures) {
        lines.push('- `' + failure.queryId + '`（' + failure.split + '）：' + failure.failureType +
          '；期望=' + failure.expectedDocumentIds.join(',') + '；实际 Top-5=' +
          this.diagnosticIds(failure.actualTop5));
      }
    }
    lines.push('');
    lines.push('## 限制');
    lines.push('');
    lines.push('- 主机环境使用真实 KeywordRetrievalEngine、Payload Builder 和 Validator，并以真实内置文档构造内存 Repository；不等同于真实 ArkData RDB 设备耗时。');
    lines.push('- 规模数据为确定性内存生成，仅用于观察增长趋势。');
    lines.push('- 未包含设备路由、网络通信、连接成功率、跨设备首结果延迟、UI 渲染或系统级资源指标。');
    lines.push('- 设备 ohosTest 结果必须单独执行和报告，不能由 HAP 构建成功代替。');
    return lines.join('\n');
  }

  private rankingRow(metrics: RankingMetrics): string {
    return '| ' + metrics.split + ' | ' + metrics.top1Accuracy.toString() + ' | ' +
      metrics.top3Recall.toString() + ' | ' + metrics.top5Recall.toString() + ' | ' +
      metrics.mrr.toString() + ' | ' + metrics.querySuccessRate.toString() + ' | ' +
      metrics.noAnswerRejectionRate.toString() + ' | ' + metrics.falsePositiveRate.toString() + ' |';
  }

  private diagnosticIds(diagnostics: CandidateDiagnostic[]): string {
    const values: string[] = [];
    for (const diagnostic of diagnostics) {
      values.push(diagnostic.documentId + ':' + diagnostic.relevance.toString());
    }
    return values.join(',');
  }
}
