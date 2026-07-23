import { describe, expect, it } from '@ohos/hypium';
import {
  chooseRdbSearchBackend,
  chooseEnabledRdbSearchBackend,
  RdbSearchCapabilities
} from '../main/ets/knowledge/storage/RdbSearchCapabilityProbe';

function capabilities(trigramChinese: boolean, defaultChinese: boolean): RdbSearchCapabilities {
  return {
    fts5Available: true,
    bm25Available: true,
    trigramAvailable: trigramChinese,
    chineseSubstringMatchAvailable: trigramChinese,
    defaultChineseSubstringMatchAvailable: defaultChinese,
    probedBackend: 'SQL_LIKE'
  };
}

export default function rdbSearchBackendTest(): void {
  describe('RdbSearchBackend', () => {
    it('selects only a backend whose Chinese fixture and ranking capabilities passed', 0, () => {
      expect(chooseRdbSearchBackend(capabilities(true, false))).assertEqual('FTS5_TRIGRAM');
      expect(chooseRdbSearchBackend(capabilities(false, true))).assertEqual('FTS5_DEFAULT');
      expect(chooseRdbSearchBackend(capabilities(false, false))).assertEqual('SQL_LIKE');
      const missingBm25 = capabilities(true, true);
      missingBm25.bm25Available = false;
      expect(chooseRdbSearchBackend(missingBm25)).assertEqual('SQL_LIKE');
      expect(chooseEnabledRdbSearchBackend(capabilities(true, false))).assertEqual('SQL_LIKE');
    });
  });
}
