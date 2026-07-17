import { abilityDelegatorRegistry } from '@kit.TestKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, expect, it } from '@ohos/hypium';
import {
  RdbSearchCapabilityProbe,
  RdbSearchCapabilities,
  chooseEnabledRdbSearchBackend,
  chooseRdbSearchBackend
} from '../../../main/ets/knowledge/storage/RdbSearchCapabilityProbe';

export default function rdbSearchCapabilityProbeTest() {
  describe('RdbSearchCapabilityProbe', () => {
    it('safely probes API 24 full text search and chooses a supported backend', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const capabilities: RdbSearchCapabilities = await new RdbSearchCapabilityProbe().probe(ability.context);
      const probedBackend = chooseRdbSearchBackend(capabilities);
      const searchBackend = chooseEnabledRdbSearchBackend(capabilities);

      expect(capabilities.bm25Available && !capabilities.fts5Available).assertFalse();
      expect(capabilities.trigramAvailable && !capabilities.fts5Available).assertFalse();
      expect(capabilities.chineseSubstringMatchAvailable && !capabilities.trigramAvailable).assertFalse();
      expect(capabilities.defaultChineseSubstringMatchAvailable && !capabilities.fts5Available).assertFalse();
      expect(capabilities.probedBackend).assertEqual(probedBackend);
      expect(searchBackend).assertEqual(chooseEnabledRdbSearchBackend(capabilities));
      expect(searchBackend).assertEqual('SQL_LIKE');
      if (capabilities.probedBackend === 'FTS5_TRIGRAM') {
        expect(capabilities.fts5Available).assertTrue();
        expect(capabilities.bm25Available).assertTrue();
        expect(capabilities.trigramAvailable).assertTrue();
        expect(capabilities.chineseSubstringMatchAvailable).assertTrue();
      } else if (capabilities.probedBackend === 'FTS5_DEFAULT') {
        expect(capabilities.fts5Available).assertTrue();
        expect(capabilities.bm25Available).assertTrue();
        expect(capabilities.defaultChineseSubstringMatchAvailable).assertTrue();
      } else {
        expect(capabilities.probedBackend).assertEqual('SQL_LIKE');
      }
      hilog.info(0x534C, 'RdbSearchCapabilityProbe',
        'backend=%{public}s fts5=%{public}s bm25=%{public}s trigram=%{public}s ' +
        'trigramChinese=%{public}s defaultChinese=%{public}s',
        capabilities.probedBackend,
        capabilities.fts5Available ? 'true' : 'false',
        capabilities.bm25Available ? 'true' : 'false',
        capabilities.trigramAvailable ? 'true' : 'false', capabilities.chineseSubstringMatchAvailable ? 'true' : 'false',
        capabilities.defaultChineseSubstringMatchAvailable ? 'true' : 'false');
    });
  });
}
