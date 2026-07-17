import { Context } from '@kit.AbilityKit';
import { describe, expect, it } from '@ohos/hypium';
import {
  RdbSearchCapabilities,
  RdbSearchCapabilityProbe
} from '../main/ets/knowledge/storage/RdbSearchCapabilityProbe';
import { RdbSearchCapabilityProvider } from '../main/ets/knowledge/storage/RdbSearchCapabilityProvider';

const TRIGRAM_CAPABILITIES: RdbSearchCapabilities = {
  fts5Available: true, bm25Available: true, trigramAvailable: true,
  chineseSubstringMatchAvailable: true, defaultChineseSubstringMatchAvailable: false,
  probedBackend: 'FTS5_TRIGRAM'
};

class RecordingProbe extends RdbSearchCapabilityProbe {
  calls: number = 0;
  shouldFail: boolean = false;

  async probe(context: Context): Promise<RdbSearchCapabilities> {
    this.calls += 1;
    await Promise.resolve(context);
    if (this.shouldFail) throw new Error('unsafe probe detail');
    return TRIGRAM_CAPABILITIES;
  }
}

export default function rdbSearchCapabilityProviderTest() {
  describe('RdbSearchCapabilityProvider', () => {
    it('reuses one capability result across sequential initializations', 0, async () => {
      const probe = new RecordingProbe();
      const provider = new RdbSearchCapabilityProvider(probe);
      const context = {} as Context;

      const first = await provider.get(context);
      const second = await provider.get(context);

      expect(probe.calls).assertEqual(1);
      expect(first).assertEqual(second);
      expect(first.probedBackend).assertEqual('FTS5_TRIGRAM');
    });

    it('shares the same pending promise for concurrent first initialization', 0, async () => {
      const probe = new RecordingProbe();
      const provider = new RdbSearchCapabilityProvider(probe);
      const context = {} as Context;

      const first = provider.get(context);
      const second = provider.get(context);
      const results = await Promise.all([first, second]);

      expect(probe.calls).assertEqual(1);
      expect(first).assertEqual(second);
      expect(results[0]).assertEqual(results[1]);
    });

    it('caches a safe SQL_LIKE result after the first probe failure', 0, async () => {
      const probe = new RecordingProbe();
      probe.shouldFail = true;
      const provider = new RdbSearchCapabilityProvider(probe);
      const context = {} as Context;

      const first = await provider.get(context);
      const second = await provider.get(context);

      expect(probe.calls).assertEqual(1);
      expect(first.probedBackend).assertEqual('SQL_LIKE');
      expect(first.fts5Available).assertFalse();
      expect(first).assertEqual(second);
    });

    it('allows isolated instances so tests do not share process cache state', 0, async () => {
      const firstProbe = new RecordingProbe();
      const secondProbe = new RecordingProbe();
      await new RdbSearchCapabilityProvider(firstProbe).get({} as Context);
      await new RdbSearchCapabilityProvider(secondProbe).get({} as Context);
      expect(firstProbe.calls).assertEqual(1);
      expect(secondProbe.calls).assertEqual(1);
    });
  });
}
