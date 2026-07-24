import { describe, expect, it } from '@ohos/hypium';
import { PeerTransportMapping } from '../main/ets/crossdevice/trust/PeerTransportMapping';

export default function peerTransportMappingTest(): void {
  describe('PeerTransportMapping', () => {
    it('keeps bidirectional transport identifiers in memory only', 0, () => {
      const mapping = new PeerTransportMapping();
      mapping.bind('system-network-ref', 'peer-key');
      expect(mapping.peerKeyFor('system-network-ref') ?? '').assertEqual('peer-key');
      expect(mapping.systemIdFor('peer-key') ?? '').assertEqual('system-network-ref');
      expect(Object.keys(mapping).join(',').includes('system-network-ref')).assertFalse();
      mapping.clear();
      expect(mapping.peerKeyFor('system-network-ref') === undefined).assertTrue();
    });

    it('replaces stale bindings on reconnect', 0, () => {
      const mapping = new PeerTransportMapping();
      mapping.bind('old-ref', 'peer-key');
      mapping.bind('new-ref', 'peer-key');
      expect(mapping.systemIdFor('peer-key') ?? '').assertEqual('new-ref');
      expect(mapping.peerKeyFor('old-ref') === undefined).assertTrue();
    });
  });
}
