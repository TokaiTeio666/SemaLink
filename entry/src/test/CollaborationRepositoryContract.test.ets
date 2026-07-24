import { describe, expect, it } from '@ohos/hypium';
import {
  CollaborationPeer,
  LocalCollaborationIdentity,
  RemoteAccessRecord,
  RemoteKnowledgeProfile
} from '../main/ets/crossdevice/model/CollaborationModels';
import {
  InMemoryCollaborationRepositories
} from '../main/ets/crossdevice/storage/InMemoryCollaborationRepositories';

export default function collaborationRepositoryContractTest(): void {
  describe('CollaborationRepositoryContract', () => {
    it('persists identity and peers without leaking mutable references', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      const identity = new LocalCollaborationIdentity('app-1', '设备 A', 100, 100, 1);
      const peer = CollaborationPeer.pending('peer-1', '设备 B', 100).withTrustState('TRUSTED', 110);
      await repositories.identity.save(identity);
      await repositories.peers.save(peer);

      const loadedIdentity: LocalCollaborationIdentity | undefined = await repositories.identity.load();
      const loadedPeer: CollaborationPeer | undefined = await repositories.peers.get('peer-1');
      expect(loadedIdentity?.appInstanceId ?? '').assertEqual('app-1');
      expect(loadedPeer?.trustState ?? '').assertEqual('TRUSTED');
      expect((await repositories.peers.list()).length).assertEqual(1);
    });

    it('expires remote profiles and bounds recent access records', 0, async () => {
      const repositories = new InMemoryCollaborationRepositories();
      const profile = new RemoteKnowledgeProfile(
        'peer-2', 'v1', 'digest', 'READY', ['数据库'], 2, 4, ['KEYWORD'], ['L1'],
        100, 100, 200
      );
      await repositories.profiles.save(profile);
      expect((await repositories.profiles.listFresh(150)).length).assertEqual(1);
      await repositories.profiles.deleteExpired(201);
      expect((await repositories.profiles.listFresh(201)).length).assertEqual(0);

      for (let index = 0; index < 140; index++) {
        await repositories.accessRecords.save(new RemoteAccessRecord(
          'record-' + index.toString(), 'INBOUND', 'peer-2', 'task-' + index.toString(),
          '数据库', 'L1', 1, 'OK', index, index + 1
        ));
      }
      expect((await repositories.accessRecords.listRecent(128)).length).assertEqual(128);
    });
  });
}
