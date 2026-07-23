import { describe, expect, it } from '@ohos/hypium';
import { CrossDeviceQueryResult } from
  '../main/ets/agent/query/CrossDeviceKnowledgePort';
import { TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import {
  isFallbackEligible
} from '../main/ets/crossdevice/transport/HarmonyCrossDeviceKnowledgePort';

export default function crossDeviceFallbackRoutingTest(): void {
  describe('CrossDeviceFallbackRouting', () => {
    it('defines only BUSY and network failure as fallback eligible', 0, () => {
      expect(isFallbackEligible(
        CrossDeviceQueryResult.failed('REMOTE_BUSY')
      )).assertTrue();
      expect(isFallbackEligible(
        CrossDeviceQueryResult.failed('REMOTE_NETWORK_ERROR')
      )).assertTrue();
      expect(isFallbackEligible(
        CrossDeviceQueryResult.failed('REMOTE_LEVEL_DENIED')
      )).assertFalse();
    });
  });
}
