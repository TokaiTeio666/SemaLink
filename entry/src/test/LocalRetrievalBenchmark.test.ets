import { describe, expect, it } from '@ohos/hypium';
import {
  ANSWERABLE_BENCHMARK_QUERIES,
  NO_ANSWER_BENCHMARK_QUERIES
} from './benchmark/LocalRetrievalBenchmarkDataset';
import { LocalRetrievalBenchmarkRunner } from './benchmark/LocalRetrievalBenchmarkRunner';

export default function localRetrievalBenchmarkTest() {
  describe('LocalRetrievalBenchmark', () => {
    it('keeps the standard dataset large, deterministic and complete', 0, () => {
      expect(ANSWERABLE_BENCHMARK_QUERIES.length >= 60).assertTrue();
      expect(NO_ANSWER_BENCHMARK_QUERIES.length >= 20).assertTrue();
      expect(new LocalRetrievalBenchmarkRunner().validateDataset().length).assertEqual(0);
    });
  });
}
