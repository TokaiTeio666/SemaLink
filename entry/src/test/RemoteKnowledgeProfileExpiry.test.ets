import { describe, expect, it } from '@ohos/hypium';
import { RemoteKnowledgeProfile } from '../main/ets/crossdevice/model/CollaborationModels';
import { InMemoryRemoteKnowledgeProfileRepository } from
  '../main/ets/crossdevice/storage/InMemoryCollaborationRepositories';
import { RemoteKnowledgeProfileCache } from
  '../main/ets/crossdevice/profile/RemoteKnowledgeProfileCache';

export default function remoteKnowledgeProfileExpiryTest(): void {
  describe('RemoteKnowledgeProfileExpiry', () => {
    it('persists an exact five minute online expiry', 0, async () => {
      const repository = new InMemoryRemoteKnowledgeProfileRepository();
      const cache = new RemoteKnowledgeProfileCache(repository);
      const profile = new RemoteKnowledgeProfile(
        'peer-a', 'v1', 'd', 'READY', [], 0, 0, ['keyword'], ['L1'],
        10, 10, 20
      );
      await cache.storeWithDefaultTtl(profile, 1000);
      const stored = await repository.get('peer-a');
      expect(stored?.expiresAtMs ?? 0).assertEqual(301000);
    });
  });
}
