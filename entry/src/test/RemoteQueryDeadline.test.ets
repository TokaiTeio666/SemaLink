import { describe, expect, it } from '@ohos/hypium';
import { InboundRemoteQuery } from
  '../main/ets/crossdevice/query/RemoteKnowledgeQueryServer';

export default function remoteQueryDeadlineTest(): void {
  describe('RemoteQueryDeadline', () => {
    it('exposes an immutable caller deadline', 0, () => {
      const request = new InboundRemoteQuery(
        'request', 'peer', 'Alias', 'domain', 'L1',
        {
          semanticContractVersion: '1.0', taskId: 'task', queryText: 'q',
          requiredConcepts: [], requiredConfidence: 0.8, coverageThreshold: 0.8,
          latencyBudgetMs: 1000, byteBudget: 4096, privacyLevel: 'PRIVATE_GROUP',
          acceptableLevels: ['L1']
        },
        200
      );
      expect(request.deadlineAtMs).assertEqual(200);
    });
  });
}
