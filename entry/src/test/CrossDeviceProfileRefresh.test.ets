import { describe, expect, it } from '@ohos/hypium';
import { CollaborationPeer } from
  '../main/ets/crossdevice/model/CollaborationModels';
import {
  ProfileRefreshSummary,
  refreshRemoteProfiles
} from '../main/ets/crossdevice/runtime/CrossDeviceRuntime';

function onlinePeer(peerKey: string): CollaborationPeer {
  return CollaborationPeer.pending(peerKey, peerKey, 1)
    .withTrustState('TRUSTED', 2)
    .withOnlineState('ONLINE', 3);
}

export default function crossDeviceProfileRefreshTest(): void {
  describe('CrossDeviceProfileRefresh', () => {
    it('continues after missing mappings and an individual send timeout', 0, async () => {
      const offline: string[] = [];
      const summary: ProfileRefreshSummary = await refreshRemoteProfiles(
        [onlinePeer('D'), onlinePeer('C'), onlinePeer('B')],
        (peerKey: string): boolean => peerKey !== 'C',
        (peerKey: string): Promise<void> => peerKey === 'D'
          ? new Promise<void>(() => {})
          : Promise.resolve(),
        (peer: CollaborationPeer): Promise<void> => {
          offline.push(peer.peerKey);
          return Promise.resolve();
        },
        1
      );

      expect(summary.succeeded).assertEqual(1);
      expect(summary.skipped).assertEqual(1);
      expect(summary.failed).assertEqual(1);
      expect(offline.length).assertEqual(2);
      expect(offline.indexOf('C') >= 0).assertTrue();
      expect(offline.indexOf('D') >= 0).assertTrue();
    });
  });
}
