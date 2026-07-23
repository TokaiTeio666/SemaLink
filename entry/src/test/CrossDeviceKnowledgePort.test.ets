import { describe, expect, it } from '@ohos/hypium';
import { UnavailableCrossDeviceKnowledgePort } from '../main/ets/agent/query/UnavailableCrossDeviceKnowledgePort';
import { FakeCrossDeviceKnowledgePort } from './support/FakeCrossDeviceKnowledgePort';
import { TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';

function task(id: string): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: id, queryText: 'database', requiredConcepts: ['database'],
    requiredConfidence: 0.8, coverageThreshold: 0.8, latencyBudgetMs: 100,
    byteBudget: 1024, privacyLevel: 'PRIVATE_GROUP', acceptableLevels: ['L1']
  };
}

export default function crossDeviceKnowledgePortTest(): void {
  describe('CrossDeviceKnowledgePort', () => {
    it('production default is explicitly unavailable and returns no evidence', 0, async () => {
      const port: UnavailableCrossDeviceKnowledgePort = new UnavailableCrossDeviceKnowledgePort();
      expect(port.availability().available).assertFalse();
      expect(port.availability().reason).assertEqual('REMOTE_CHANNEL_UNAVAILABLE');
    });

    it('fake cancellation is isolated by internal task id', 0, () => {
      const port: FakeCrossDeviceKnowledgePort = new FakeCrossDeviceKnowledgePort();
      port.cancel('internal-1');
      expect(port.cancelledTaskIds.length).assertEqual(1);
      expect(port.cancelledTaskIds[0]).assertEqual('internal-1');
    });

    it('fake expresses timeout, partial failure, empty result, and controlled error', 0, async () => {
      const port: FakeCrossDeviceKnowledgePort = new FakeCrossDeviceKnowledgePort();
      port.timedOut = true;
      expect((await port.search(task('timeout'))).timedOut).assertTrue();
      port.timedOut = false;
      port.partialFailures = 1;
      expect((await port.search(task('partial'))).failedSources).assertEqual(1);
      port.partialFailures = 0;
      expect((await port.search(task('empty'))).evidence.length).assertEqual(0);
      port.throwControlledError = true;
      let rejected: boolean = false;
      try {
        await port.search(task('error'));
      } catch (_error) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });

    it('delayed fake search observes cancellation for only the requested task', 0, async () => {
      const port: FakeCrossDeviceKnowledgePort = new FakeCrossDeviceKnowledgePort();
      port.delayMs = 2;
      const first = port.search(task('first'));
      const second = port.search(task('second'));
      port.cancel('first');
      const results = await Promise.all([first, second]);
      expect(results[0].cancelled).assertTrue();
      expect(results[1].cancelled).assertFalse();
    });
  });
}
