import { RemoteKnowledgeProfile } from '../model/CollaborationModels';
import { RemoteKnowledgeProfileRepository } from '../storage/CollaborationRepositories';
import { encodeUtf8 } from '../../communication/tls/Utf8Codec';

export interface ProfileExchangeSender {
  sendDigest(peerKey: string, version: string, digest: string): Promise<void>;
  requestProfile(peerKey: string): Promise<void>;
  sendProfile(peerKey: string, profile: RemoteKnowledgeProfile): Promise<void>;
}

class ExpectedRemoteProfile {
  readonly version: string;
  readonly digest: string;
  constructor(version: string, digest: string) {
    this.version = version;
    this.digest = digest;
  }
}

export class KnowledgeProfileExchangeService {
  private readonly repository: RemoteKnowledgeProfileRepository;
  private readonly sender: ProfileExchangeSender;
  private readonly expected: Map<string, ExpectedRemoteProfile> =
    new Map<string, ExpectedRemoteProfile>();

  constructor(repository: RemoteKnowledgeProfileRepository, sender: ProfileExchangeSender) {
    this.repository = repository;
    this.sender = sender;
  }

  announce(peerKey: string, version: string, digest: string): Promise<void> {
    return this.sender.sendDigest(peerKey, version, digest);
  }

  async onRemoteDigest(peerKey: string, version: string, digest: string): Promise<void> {
    const cached: RemoteKnowledgeProfile | undefined = await this.repository.get(peerKey);
    if (cached === undefined ||
      cached.profileVersion !== version ||
      cached.profileDigest !== digest) {
      this.expected.delete(peerKey);
      this.expected.set(peerKey, new ExpectedRemoteProfile(version, digest));
      while (this.expected.size > 128) {
        const oldest: string | undefined = this.expected.keys().next().value;
        if (oldest === undefined) {
          break;
        }
        this.expected.delete(oldest);
      }
      await this.sender.requestProfile(peerKey);
    }
  }

  sendProfile(peerKey: string, profile: RemoteKnowledgeProfile): Promise<void> {
    return this.sender.sendProfile(peerKey, profile);
  }

  async acceptProfile(profile: RemoteKnowledgeProfile): Promise<void> {
    const expected: ExpectedRemoteProfile | undefined =
      this.expected.get(profile.peerKey);
    if (expected === undefined ||
      expected.version !== profile.profileVersion ||
      expected.digest !== profile.profileDigest) {
      throw new Error('UNEXPECTED_REMOTE_PROFILE');
    }
    if (profile.knowledgeDomains.length > 20 ||
      encodeUtf8(JSON.stringify(profile)).length > 8 * 1024) {
      throw new Error('INVALID_REMOTE_PROFILE');
    }
    await this.repository.save(profile);
    this.expected.delete(profile.peerKey);
  }
}
