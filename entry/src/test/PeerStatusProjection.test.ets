import { describe, expect, it } from '@ohos/hypium';
import {
  activePeerCount,
  isPeerAvailable,
  PeerChannelStateSource,
  projectPeerStatuses
} from '../main/ets/application/PeerStatusProjection';
import { PeerDevice, PeerStatusSnapshot } from '../main/ets/model/AppModels';

class FixedPeerStateSource implements PeerChannelStateSource {
  controlStateOf(deviceId: string) {
    if (deviceId === 'ready') return 'READY';
    if (deviceId === 'failed') return 'FAILED';
    return 'CONNECTING';
  }

  dataStateOf(deviceId: string) {
    return deviceId === 'ready' ? 'READY' : 'DISCONNECTED';
  }
}

function peers(): PeerDevice[] {
  return [
    { deviceId: 'ready', deviceName: 'Tablet B', deviceType: 'tablet' },
    { deviceId: 'failed', deviceName: 'Phone A', deviceType: 'phone' },
    { deviceId: 'connecting', deviceName: '', deviceType: 'tablet' }
  ];
}

export default function peerStatusProjectionTest(): void {
  describe('PeerStatusProjection', () => {
    it('countsOnlyPeersWithReadyControlAndDataChannels', 0, () => {
      const statuses: PeerStatusSnapshot[] = projectPeerStatuses(
        peers(), new FixedPeerStateSource(), new Map<string, string>()
      );

      expect(activePeerCount(statuses)).assertEqual(1);
      expect(isPeerAvailable(statuses[0])).assertTrue();
      expect(isPeerAvailable(statuses[1])).assertFalse();
    });

    it('keepsRealNamesMaskedIdsAndPerPeerFailures', 0, () => {
      const failures = new Map<string, string>([['failed', 'E_CONNECT_FAILED']]);
      const statuses: PeerStatusSnapshot[] = projectPeerStatuses(peers(), new FixedPeerStateSource(), failures);

      expect(statuses[0].deviceName).assertEqual('Tablet B');
      expect(statuses[1].deviceName).assertEqual('Phone A');
      expect(statuses[1].failureCode).assertEqual('E_CONNECT_FAILED');
      expect(statuses[2].deviceName).assertEqual('');
      expect(statuses[2].deviceIdMasked.length > 0).assertTrue();
    });
  });
}
