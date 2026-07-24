import { describe, expect, it } from '@ohos/hypium';
import { RemoteKnowledgeProfile } from '../main/ets/crossdevice/model/CollaborationModels';
import { InMemoryRemoteKnowledgeProfileRepository } from
  '../main/ets/crossdevice/storage/InMemoryCollaborationRepositories';
import {
  KnowledgeProfileExchangeService,
  ProfileExchangeSender
} from '../main/ets/crossdevice/profile/KnowledgeProfileExchangeService';

class RecordingProfileSender implements ProfileExchangeSender {
  digestCount: number = 0;
  requestCount: number = 0;
  responseCount: number = 0;

  sendDigest(_peerKey: string, _version: string, _digest: string): Promise<void> {
    this.digestCount++;
    return Promise.resolve();
  }

  requestProfile(_peerKey: string): Promise<void> {
    this.requestCount++;
    return Promise.resolve();
  }

  sendProfile(_peerKey: string, _profile: RemoteKnowledgeProfile): Promise<void> {
    this.responseCount++;
    return Promise.resolve();
  }
}

export default function knowledgeProfileExchangeTest(): void {
  describe('KnowledgeProfileExchangeService', () => {
    it('requests a profile only when the digest differs', 0, async () => {
      const repository = new InMemoryRemoteKnowledgeProfileRepository();
      const sender = new RecordingProfileSender();
      const exchange = new KnowledgeProfileExchangeService(repository, sender);
      await exchange.onRemoteDigest('peer-a', 'v1', 'digest-a');
      expect(sender.requestCount).assertEqual(1);
      await repository.save(new RemoteKnowledgeProfile(
        'peer-a', 'v1', 'digest-a', 'READY', [], 0, 0, ['keyword'], ['L1'],
        1, 1, 300001
      ));
      await exchange.onRemoteDigest('peer-a', 'v1', 'digest-a');
      expect(sender.requestCount).assertEqual(1);
    });

    it('accepts only the profile matching an outstanding digest request', 0, async () => {
      const repository = new InMemoryRemoteKnowledgeProfileRepository();
      const sender = new RecordingProfileSender();
      const exchange = new KnowledgeProfileExchangeService(repository, sender);
      const profile = new RemoteKnowledgeProfile(
        'peer-b', 'v2', 'digest-b', 'READY', ['HarmonyOS'], 1, 1,
        ['keyword'], ['L1'], 1, 1, 300001
      );
      let rejected: boolean = false;
      try {
        await exchange.acceptProfile(profile);
      } catch (_) {
        rejected = true;
      }
      expect(rejected).assertTrue();
      await exchange.onRemoteDigest('peer-b', 'v2', 'digest-b');
      await exchange.acceptProfile(profile);
      expect((await repository.get('peer-b')) !== undefined).assertTrue();
    });
  });
}
