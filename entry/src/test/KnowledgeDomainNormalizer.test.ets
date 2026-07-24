import { describe, expect, it } from '@ohos/hypium';
import { normalizeKnowledgeDomain } from
  '../main/ets/contracts/semantic/KnowledgeDomainNormalizer';

export default function knowledgeDomainNormalizerTest(): void {
  describe('KnowledgeDomainNormalizer', () => {
    it('normalizes English case and surrounding whitespace', 0, () => {
      expect(normalizeKnowledgeDomain(' HarmonyOS ')).assertEqual('harmonyos');
      expect(normalizeKnowledgeDomain('ArkTS')).assertEqual('arkts');
      expect(normalizeKnowledgeDomain('Database')).assertEqual('database');
    });

    it('normalizes ordinary and full-width whitespace without damaging Chinese', 0, () => {
      expect(normalizeKnowledgeDomain('数据库  事务')).assertEqual('数据库 事务');
      expect(normalizeKnowledgeDomain('数据库　事务')).assertEqual('数据库 事务');
      expect(normalizeKnowledgeDomain('　数据库 事务　')).assertEqual('数据库 事务');
    });
  });
}
