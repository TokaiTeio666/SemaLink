import { describe, expect, it } from '@ohos/hypium';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BenchmarkReport, LocalRetrievalBenchmarkRunner } from './benchmark/LocalRetrievalBenchmarkRunner';
import { RUN_FULL_LOCAL_RETRIEVAL_BENCHMARK } from './benchmark/BenchmarkRunMode';

const LOG_CHUNK_SIZE: number = 1800;

function emitEncodedChunks(kind: string, content: string): void {
  const encoded = encodeURIComponent(content);
  const total = Math.ceil(encoded.length / LOG_CHUNK_SIZE);
  for (let index = 0; index < total; index++) {
    const marker = 'SEMALINK_BENCH_' + kind + '_' + index.toString().padStart(4, '0') + '_' +
      total.toString().padStart(4, '0') + ':';
    const chunk = encoded.substring(index * LOG_CHUNK_SIZE, Math.min(encoded.length, (index + 1) * LOG_CHUNK_SIZE));
    hilog.info(0x0000, 'SemaLinkBench', '%{public}s', marker + chunk);
  }
}

export default function localRetrievalFullBenchmarkTest() {
  describe('LocalRetrievalFullBenchmark', () => {
    it('runs the reproducible local retrieval benchmark', 0, async () => {
      if (!RUN_FULL_LOCAL_RETRIEVAL_BENCHMARK) {
        expect(true).assertTrue();
        return;
      }
      const runner = new LocalRetrievalBenchmarkRunner();
      const report: BenchmarkReport = await runner.runFull();
      const markdown = runner.toMarkdown(report);
      for (const failure of report.failures) {
        failure.queryText = '[redacted]';
      }
      emitEncodedChunks('JSON', JSON.stringify(report));
      emitEncodedChunks('MARKDOWN', markdown);
      expect(report.dataset.answerableQueryCount >= 60).assertTrue();
      expect(report.dataset.noAnswerQueryCount >= 20).assertTrue();
    });
  });
}
