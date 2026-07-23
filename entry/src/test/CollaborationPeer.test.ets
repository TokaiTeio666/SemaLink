import { describe, expect, it } from '@ohos/hypium';
import {
  CollaborationPeer,
  canRouteToPeer
} from '../main/ets/crossdevice/model/CollaborationModels';

export default function collaborationPeerTest(): void {
  describe('CollaborationPeer', () => {
    it('keeps a system-visible peer pending until application trust', 0, () => {
      const peer: CollaborationPeer = CollaborationPeer.pending('peer-key-1', '设备 B', 100);
      expect(peer.trustState).assertEqual('PENDING');
      expect(canRouteToPeer(peer)).assertFalse();
    });

    it('routes only trusted online peers', 0, () => {
      const pending: CollaborationPeer = CollaborationPeer.pending('peer-key-2', '设备 C', 100);
      const trusted: CollaborationPeer = pending.withTrustState('TRUSTED', 200).withOnlineState('ONLINE', 201);
      expect(canRouteToPeer(trusted)).assertTrue();
      expect(canRouteToPeer(trusted.withOnlineState('OFFLINE', 202))).assertFalse();
    });
  });
}
