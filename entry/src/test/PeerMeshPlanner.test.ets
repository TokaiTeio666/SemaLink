import { describe, expect, it } from '@ohos/hypium';
import {
  MeshDialRole,
  planFullMeshEdges,
  planPeerRole,
  preferredSessionDirection
} from '../main/ets/communication/PeerMeshPlanner';

export default function peerMeshPlannerTest(): void {
  describe('PeerMeshPlanner', () => {
    it('plansExactlyOnePrimaryDialerForEachPair', 0, () => {
      expect(planPeerRole('device-a', 'device-b')).assertEqual(MeshDialRole.PRIMARY_DIALER);
      expect(planPeerRole('device-b', 'device-a')).assertEqual(MeshDialRole.INBOUND_WAITER);
      expect(planPeerRole('device-a', 'device-a')).assertEqual(MeshDialRole.INVALID_SELF);
    });

    it('producesTheThreeEdgesOfAThreeDeviceMesh', 0, () => {
      expect(planFullMeshEdges(['device-c', 'device-a', 'device-b']))
        .assertDeepEquals(['device-a->device-b', 'device-a->device-c', 'device-b->device-c']);
    });

    it('producesTheSixEdgesOfAFourDeviceMesh', 0, () => {
      expect(planFullMeshEdges(['d', 'c', 'b', 'a']))
        .assertDeepEquals(['a->b', 'a->c', 'a->d', 'b->c', 'b->d', 'c->d']);
    });

    it('selectsTheSameCanonicalDirectionAtBothEnds', 0, () => {
      expect(preferredSessionDirection('device-a', 'device-b')).assertEqual('OUTBOUND');
      expect(preferredSessionDirection('device-b', 'device-a')).assertEqual('INBOUND');
    });
  });
}
