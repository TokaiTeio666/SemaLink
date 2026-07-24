import { describe, expect, it } from '@ohos/hypium';
import { ALL_FIXTURES, A2AFixture, A2AFixtureFidelity }
  from './fixtures/a2a/HuaweiA2AV06Fixtures';

export default function a2aFixtureProvenanceTest(): void {
  describe('A2AFixtureProvenance', () => {
    it('classifies every fixture with explicit conservative provenance', 0, () => {
      expect(ALL_FIXTURES.length > 0).assertTrue();
      for (const fixture of ALL_FIXTURES as A2AFixture[]) {
        expect(fixture.sourceUrl.indexOf('developer.huawei.com') >= 0).assertTrue();
        expect(fixture.documentTitle.length > 0).assertTrue();
        expect(fixture.documentVersion.length > 0).assertTrue();
        expect(fixture.scenario.length > 0).assertTrue();
        expect(
          fixture.fidelity === A2AFixtureFidelity.EXACT_OFFICIAL ||
          fixture.fidelity === A2AFixtureFidelity.DERIVED_FROM_OFFICIAL ||
          fixture.fidelity === A2AFixtureFidelity.PROJECT_COMPATIBILITY
        ).assertTrue();
      }
    });

    it('does not claim any hand-constructed minimal payload is an exact official sample', 0, () => {
      const exactCount: number = ALL_FIXTURES.filter((fixture: A2AFixture): boolean =>
        fixture.fidelity === A2AFixtureFidelity.EXACT_OFFICIAL).length;
      expect(exactCount).assertEqual(0);
    });
  });
}
