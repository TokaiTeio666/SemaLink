import { abilityDelegatorRegistry } from '@kit.TestKit';
import { relationalStore } from '@kit.ArkData';
import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeDatabase } from
  '../../../main/ets/knowledge/storage/KnowledgeDatabase';
import {
  CollaborationPeer,
  LocalCollaborationIdentity,
  RemoteAccessRecord,
  RemoteKnowledgeProfile
} from '../../../main/ets/crossdevice/model/CollaborationModels';
import { SharingPolicy } from
  '../../../main/ets/crossdevice/model/SharingPolicy';
import {
  RdbCollaborationPeerRepository,
  RdbLocalCollaborationIdentityRepository,
  RdbRemoteAccessRecordRepository,
  RdbRemoteKnowledgeProfileRepository,
  RdbSharingPolicyRepository
} from '../../../main/ets/crossdevice/storage/RdbCollaborationRepositories';

export default function collaborationRepositoryTest(): void {
  describe('CollaborationRepository', () => {
    it('persists collaboration state across a real RDB reopen', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      const storeName = 'semalink_collaboration_' + Date.now() + '.db';
      try {
        let database = new KnowledgeDatabase(storeName);
        await database.initialize(context);
        await new RdbLocalCollaborationIdentityRepository(database).save(
          new LocalCollaborationIdentity('app-instance', 'Alias', 1, 1, 1)
        );
        await new RdbCollaborationPeerRepository(database).save(
          CollaborationPeer.pending('peer-a', 'Peer A', 1).withTrustState('TRUSTED', 2)
        );
        await new RdbRemoteKnowledgeProfileRepository(database).save(
          new RemoteKnowledgeProfile(
            'peer-a', 'v1', 'digest', 'READY', ['domain'], 1, 2,
            ['keyword'], ['L1'], 2, 2, 300002
          )
        );
        await new RdbSharingPolicyRepository(database).save(
          new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 2, 2)
        );
        await new RdbRemoteAccessRecordRepository(database).save(
          new RemoteAccessRecord(
            'record', 'INBOUND', 'peer-a', 'task', 'domain', 'L1',
            1, 'OK', 2, 3
          )
        );
        database.close();

        database = new KnowledgeDatabase(storeName);
        await database.initialize(context);
        expect((await new RdbLocalCollaborationIdentityRepository(database).load())
          ?.appInstanceId ?? '').assertEqual('app-instance');
        expect((await new RdbCollaborationPeerRepository(database).get('peer-a'))
          ?.trustState ?? '').assertEqual('TRUSTED');
        expect((await new RdbRemoteKnowledgeProfileRepository(database).get('peer-a'))
          ?.profileDigest ?? '').assertEqual('digest');
        expect((await new RdbSharingPolicyRepository(database).load()).enabled).assertTrue();
        expect((await new RdbRemoteAccessRecordRepository(database).listRecent(10)).length)
          .assertEqual(1);
        database.close();
      } finally {
        await relationalStore.deleteRdbStore(context, storeName);
      }
    });
  });
}
