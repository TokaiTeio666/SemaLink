import { describe, expect, it } from '@ohos/hypium';
import { InMemoryCollaborationPeerRepository } from
  '../main/ets/crossdevice/storage/InMemoryCollaborationRepositories';
import { TrustedDeviceDirectory } from '../main/ets/crossdevice/trust/TrustedDeviceDirectory';
import { CollaborationPeer } from
  '../main/ets/crossdevice/model/CollaborationModels';

export default function trustedDeviceDirectoryTest(): void {
  describe('TrustedDeviceDirectory', () => {
    it('does not equate system visibility with application trust', 0, async () => {
      const repository = new InMemoryCollaborationPeerRepository();
      const directory = new TrustedDeviceDirectory(repository, (): number => 100);
      await directory.observeCandidate('peer-b', '设备 B', true);
      const peers = await directory.list();
      expect(peers.length).assertEqual(1);
      expect(peers[0].trustState).assertEqual('PENDING');
      expect((await directory.routablePeers()).length).assertEqual(0);
    });

    it('supports trust block revoke rename and online transitions', 0, async () => {
      const repository = new InMemoryCollaborationPeerRepository();
      let now: number = 100;
      const directory = new TrustedDeviceDirectory(repository, (): number => now);
      await directory.observeCandidate('peer-c', '设备 C', true);
      now = 110;
      await directory.trust('peer-c');
      expect((await directory.routablePeers()).length).assertEqual(1);
      now = 120;
      await directory.rename('peer-c', '数据库平板');
      now = 130;
      await directory.block('peer-c');
      expect((await directory.routablePeers()).length).assertEqual(0);
      now = 140;
      await directory.revoke('peer-c');
      const peer = await repository.get('peer-c');
      expect(peer?.deviceAlias ?? '').assertEqual('数据库平板');
      expect(peer?.trustState ?? '').assertEqual('REVOKED');
    });

    it('resets persisted online state without losing durable peer metadata', 0, async () => {
      const repository = new InMemoryCollaborationPeerRepository();
      await repository.save(new CollaborationPeer(
        'peer-b', 'Device B', 'TRUSTED', 'ONLINE', 77,
        'profile-v1', 'digest-v1', 1, 80
      ));
      const directory = new TrustedDeviceDirectory(repository, (): number => 100);

      await directory.resetOnlineStates();
      const reset = await repository.get('peer-b');
      expect(reset?.onlineState ?? '').assertEqual('OFFLINE');
      expect(reset?.trustState ?? '').assertEqual('TRUSTED');
      expect(reset?.deviceAlias ?? '').assertEqual('Device B');
      expect(reset?.lastSeenAtMs ?? 0).assertEqual(77);
      expect((await directory.routablePeers()).length).assertEqual(0);

      await directory.observeCandidate('peer-b', 'Device B', true);
      expect((await directory.routablePeers()).length).assertEqual(1);
    });
  });
}
