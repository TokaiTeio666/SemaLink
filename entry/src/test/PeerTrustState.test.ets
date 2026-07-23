import { describe, expect, it } from '@ohos/hypium';
import {
  CollaborationPeer,
  canExchangeProfile,
  canRouteToPeer
} from '../main/ets/crossdevice/model/CollaborationModels';

export default function peerTrustStateTest(): void {
  describe('PeerTrustState', () => {
    it('blocks and revokes peers from profile exchange and routing', 0, () => {
      const trusted: CollaborationPeer =
        CollaborationPeer.pending('peer-key-3', '设备 B', 100)
          .withTrustState('TRUSTED', 110)
          .withOnlineState('ONLINE', 120);
      const blocked: CollaborationPeer = trusted.withTrustState('BLOCKED', 130);
      const revoked: CollaborationPeer = trusted.withTrustState('REVOKED', 140);
      expect(canExchangeProfile(blocked)).assertFalse();
      expect(canRouteToPeer(blocked)).assertFalse();
      expect(canExchangeProfile(revoked)).assertFalse();
      expect(canRouteToPeer(revoked)).assertFalse();
    });

    it('increments update timestamp without exposing transport identifiers', 0, () => {
      const peer: CollaborationPeer =
        CollaborationPeer.pending('peer-key-4', '设备 C', 100).rename('数据库平板', 150);
      expect(peer.peerKey).assertEqual('peer-key-4');
      expect(peer.deviceAlias).assertEqual('数据库平板');
      expect(peer.updatedAtMs).assertEqual(150);
      expect(Object.keys(peer).indexOf('networkId')).assertEqual(-1);
      expect(Object.keys(peer).indexOf('deviceId')).assertEqual(-1);
    });
  });
}
