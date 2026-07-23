import { describe, expect, it } from '@ohos/hypium';
import { RemoteKnowledgeProfile } from '../main/ets/crossdevice/model/CollaborationModels';
import { InMemoryRemoteKnowledgeProfileRepository } from
  '../main/ets/crossdevice/storage/InMemoryCollaborationRepositories';
import { RemoteKnowledgeProfileCache } from
  '../main/ets/crossdevice/profile/RemoteKnowledgeProfileCache';

function remote(expiresAtMs: number): RemoteKnowledgeProfile {
  return new RemoteKnowledgeProfile(
    'peer-a', 'v1', 'digest', 'READY', ['docs'], 1, 2, ['keyword'], ['L1'],
    100, 100, expiresAtMs
  );
}

export default function remoteKnowledgeProfileCacheTest(): void {
  describe('RemoteKnowledgeProfileCache', () => {
    it('serves fresh online profiles and bounded offline fallback', 0, async () => {
      const repository = new InMemoryRemoteKnowledgeProfileRepository();
      const cache = new RemoteKnowledgeProfileCache(repository);
      await cache.store(remote(5 * 60 * 1000));
      expect((await cache.get('peer-a', 1000, true)) !== undefined).assertTrue();
      expect((await cache.get('peer-a', 6 * 60 * 1000, true)) === undefined).assertTrue();
      expect((await cache.get('peer-a', 23 * 60 * 60 * 1000, false)) !== undefined).assertTrue();
      expect((await cache.get('peer-a', 25 * 60 * 60 * 1000, false)) === undefined).assertTrue();
    });
  });
}
