import { describe, expect, it } from '@ohos/hypium';
import { CollaborationPeer } from '../main/ets/crossdevice/model/CollaborationModels';
import { SharingPolicy } from '../main/ets/crossdevice/model/SharingPolicy';

export default function sharingPolicyTest(): void {
  describe('SharingPolicy', () => {
    it('defaults to disabled trusted L1 sharing with bounded evidence', 0, () => {
      const policy: SharingPolicy = SharingPolicy.defaults(100);
      expect(policy.enabled).assertFalse();
      expect(policy.requireTrustedPeer).assertTrue();
      expect(policy.allowedLevels.join(',')).assertEqual('L1');
      expect(policy.maxEvidenceCount).assertEqual(5);
      expect(policy.maxSnippetChars).assertEqual(512);
    });

    it('requires explicit L2 and gives denied domains precedence', 0, () => {
      const peer: CollaborationPeer =
        CollaborationPeer.pending('peer-key-5', '设备 B', 100).withTrustState('TRUSTED', 110);
      const policy = new SharingPolicy(
        true, true, ['L1'], 5, 512, ['数据库', '操作系统'], ['数据库'], 120, 2
      );
      expect(policy.allows(peer, 'L1', '操作系统')).assertTrue();
      expect(policy.allows(peer, 'L1', '数据库')).assertFalse();
      expect(policy.allows(peer, 'L2', '操作系统')).assertFalse();
    });
  });
}
