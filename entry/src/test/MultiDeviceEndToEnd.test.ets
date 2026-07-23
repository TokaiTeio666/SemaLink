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
    it('connectsEveryPairInTheThreeDeviceMesh', 0, async () => {
      const fixture = new MultiDeviceFixture();
      await fixture.connectFullMesh();
      expect(fixture.readyDeviceIds()).assertDeepEquals(['device-b', 'device-c']);
      expect(fixture.readyPeersOf('device-b')).assertDeepEquals(['device-a', 'device-c']);
      expect(fixture.readyPeersOf('device-c')).assertDeepEquals(['device-a', 'device-b']);
    });

    it('allowsEveryDeviceToQueryTheOtherTwo', 0, async () => {
      const fixture = new MultiDeviceFixture();
      fixture.setEvidence('device-a', [evidence('a-alpha', 'alpha')]);
      fixture.setEvidence('device-b', [evidence('b-beta', 'beta')]);
      fixture.setEvidence('device-c', [evidence('c-gamma', 'gamma')]);
      await fixture.connectFullMesh();

      expect((await fixture.runTaskFrom('device-a', makeTask('from-a'))).feedback).assertEqual('ENOUGH');
      expect(fixture.lastAggregate().evidence.length).assertEqual(3);
      expect((await fixture.runTaskFrom('device-b', makeTask('from-b'))).feedback).assertEqual('ENOUGH');
      expect(fixture.lastAggregate().evidence.length).assertEqual(3);
      expect((await fixture.runTaskFrom('device-c', makeTask('from-c'))).feedback).assertEqual('ENOUGH');
      expect(fixture.lastAggregate().evidence.length).assertEqual(3);
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

    it('keepsTheRemainingPairQueryableWhenOneDeviceLeaves', 0, async () => {
      const fixture = new MultiDeviceFixture();
      fixture.setEvidence('device-a', [evidence('a-alpha', 'alpha')]);
      fixture.setEvidence('device-b', [evidence('b-beta', 'beta')]);
      await fixture.connectFullMesh();
      fixture.disconnect('device-c');

      expect(fixture.readyPeersOf('device-a')).assertDeepEquals(['device-b']);
      expect(fixture.readyPeersOf('device-b')).assertDeepEquals(['device-a']);
      expect((await fixture.runTaskFrom('device-a', makeTask('without-c'))).feedback).assertEqual('ENOUGH');
    });

    it('convergesBackupConnectionsToOnePerUnorderedPair', 0, async () => {
      const fixture = new MultiDeviceFixture();
      await fixture.connectFullMesh();
      fixture.injectBackupConnection('device-b', 'device-a');
      fixture.injectBackupConnection('device-c', 'device-a');
      fixture.injectBackupConnection('device-c', 'device-b');
      fixture.convergeDuplicateConnections();

      expect(fixture.connectionCount('device-a', 'device-b')).assertEqual(1);
      expect(fixture.connectionCount('device-a', 'device-c')).assertEqual(1);
      expect(fixture.connectionCount('device-b', 'device-c')).assertEqual(1);
      expect(fixture.connectionDirection('device-a', 'device-b')).assertEqual('OUTBOUND');
      expect(fixture.connectionDirection('device-b', 'device-a')).assertEqual('INBOUND');
    });

    it('reconnectsOnlyEdgesThatBelongToTheReturningDevice', 0, async () => {
      const fixture = new MultiDeviceFixture();
      await fixture.connectFullMesh();
      const abAttempts: number = fixture.connectionAttemptCount('device-a', 'device-b');
      const acAttempts: number = fixture.connectionAttemptCount('device-a', 'device-c');
      const bcAttempts: number = fixture.connectionAttemptCount('device-b', 'device-c');
      fixture.disconnect('device-c');
      await fixture.connectFullMesh();

      expect(fixture.connectionAttemptCount('device-a', 'device-b')).assertEqual(abAttempts);
      expect(fixture.connectionAttemptCount('device-a', 'device-c')).assertEqual(acAttempts + 1);
      expect(fixture.connectionAttemptCount('device-b', 'device-c')).assertEqual(bcAttempts + 1);
      expect(fixture.readyPeersOf('device-c')).assertDeepEquals(['device-a', 'device-b']);
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
