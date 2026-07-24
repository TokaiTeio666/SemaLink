import { describe, expect, it } from '@ohos/hypium';
import { CollaborationPeer } from '../main/ets/crossdevice/model/CollaborationModels';
import { SharingPolicy } from '../main/ets/crossdevice/model/SharingPolicy';

export default function sharingPolicyEnforcementTest(): void {
  describe('SharingPolicyEnforcement', () => {
    it('gives denied domains priority and requires explicit L2 permission', 0, () => {
      const peer: CollaborationPeer = CollaborationPeer.pending('peer', 'B', 1)
        .withTrustState('TRUSTED', 2);
      const policy = new SharingPolicy(
        true, true, ['L1'], 5, 512, ['HarmonyOS', 'private'], ['private'], 3, 2
      );
      expect(policy.allows(peer, 'L1', 'HarmonyOS')).assertTrue();
      expect(policy.allows(peer, 'L1', 'private')).assertFalse();
      expect(policy.allows(peer, 'L2', 'HarmonyOS')).assertFalse();
    });
  });
}
