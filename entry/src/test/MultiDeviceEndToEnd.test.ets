import { describe, expect, it } from '@ohos/hypium';
import { MultiDeviceFixture } from './support/MultiDeviceFixtures';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';

function makeTask(id: string): TaskRequest {
  return { semanticContractVersion: '1.0', taskId: id, queryText: 'alpha beta',
    requiredConcepts: ['alpha', 'beta'], requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: 4000, privacyLevel: 'PRIVATE_GROUP', acceptableLevels: ['L1', 'L2'] };
}

function evidence(id: string, concept: string, hash: string = 'hash-' + id): EvidenceUnit {
  return { semanticContractVersion: '1.0', evidenceId: id, evidenceGroupId: id,
    sourceDeviceId: 'fixture', sourceDocId: 'doc-' + id, level: 'L1', title: id, summary: id,
    relevance: 1, coveredConcepts: [concept], estimatedCoverageGain: 1, byteCost: 100,
    privacyLevel: 'PRIVATE_GROUP', privacyCost: 0, energyCost: 0, hash: hash, canEscalateTo: ['L2'] };
}

export default function multiDeviceEndToEndTest(): void {
  describe('MultiDeviceEndToEnd', () => {
    it('connectsAWithBothRemoteDevices', 0, async () => {
      const fixture = new MultiDeviceFixture();
      await fixture.connectThreeDevices();
      expect(fixture.readyDeviceIds()).assertDeepEquals(['device-b', 'device-c']);
    });

    it('mergesComplementaryEvidenceAndKeepsEvidenceOffDsk', 0, async () => {
      const fixture = new MultiDeviceFixture();
      fixture.setEvidence('device-b', [evidence('b-alpha', 'alpha')]);
      fixture.setEvidence('device-c', [evidence('c-beta', 'beta')]);
      await fixture.connectThreeDevices();
      const result = await fixture.runTask(makeTask('complementary'));
      expect(result.feedback).assertEqual('ENOUGH');
      expect(fixture.dskPayloadTypes().indexOf('EVIDENCE_BATCH') < 0).assertTrue();
      expect(fixture.tlsPayloadTypes().indexOf('TASK') >= 0).assertTrue();
      expect(fixture.tlsPayloadTypes().indexOf('EVIDENCE_BATCH') >= 0).assertTrue();
    });

    it('deduplicatesSameContentAndIsolatesSameIdConflict', 0, async () => {
      const duplicate = evidence('same', 'alpha', 'same-hash');
      const fixture = new MultiDeviceFixture();
      fixture.setEvidence('device-b', [duplicate]);
      fixture.setEvidence('device-c', [duplicate]);
      await fixture.connectThreeDevices();
      await fixture.runTask(makeTask('duplicates'));
      expect(fixture.lastAggregate().evidence.length).assertEqual(1);
      expect(fixture.lastAggregate().evidence[0].sourceDeviceIds).assertDeepEquals(['device-b', 'device-c']);

      const conflictFixture = new MultiDeviceFixture();
      conflictFixture.setEvidence('device-b', [evidence('same', 'alpha', 'hash-b')]);
      conflictFixture.setEvidence('device-c', [evidence('same', 'beta', 'hash-c')]);
      await conflictFixture.connectThreeDevices();
      await conflictFixture.runTask(makeTask('conflict'));
      expect(conflictFixture.lastAggregate().conflicts.length).assertEqual(1);
    });

    it('isolatesDisconnectAndEmptyResult', 0, async () => {
      const fixture = new MultiDeviceFixture();
      fixture.setEvidence('device-b', [evidence('b-alpha', 'alpha')]);
      fixture.setEvidence('device-c', []);
      await fixture.connectThreeDevices();
      fixture.disconnect('device-c');
      expect(fixture.readyDeviceIds()).assertDeepEquals(['device-b']);
      const result = await fixture.runTask(makeTask('empty-c'));
      expect(result.feedback).assertEqual('ABORT');
      expect(fixture.pendingResourceCount()).assertEqual(0);
    });

    it('ignoresLateFramesAfterCancellation', 0, async () => {
      const fixture = new MultiDeviceFixture();
      await fixture.connectThreeDevices();
      await fixture.cancelTask('cancelled');
      fixture.deliverLateEvidence('device-c', evidence('late', 'beta'));
      expect(fixture.lastAggregate().evidence.length).assertEqual(0);
    });

    it('doesNotLeakStateAfterTenTasks', 0, async () => {
      const fixture = new MultiDeviceFixture();
      await fixture.connectThreeDevices();
      for (let index = 0; index < 10; index += 1) await fixture.runTask(makeTask('task-' + index));
      expect(fixture.pendingResourceCount()).assertEqual(0);
    });
  });
}
