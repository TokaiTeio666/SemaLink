import { RemoteKnowledgeProfile } from '../model/CollaborationModels';
import { RemoteKnowledgeProfileRepository } from '../storage/CollaborationRepositories';

export const REMOTE_PROFILE_TTL_MS: number = 5 * 60 * 1000;
export const REMOTE_PROFILE_OFFLINE_RETENTION_MS: number = 24 * 60 * 60 * 1000;

export class RemoteKnowledgeProfileCache {
  private readonly repository: RemoteKnowledgeProfileRepository;

  constructor(repository: RemoteKnowledgeProfileRepository) {
    this.repository = repository;
  }

  store(profile: RemoteKnowledgeProfile): Promise<void> {
    return this.repository.save(profile);
  }

  async storeWithDefaultTtl(profile: RemoteKnowledgeProfile, receivedAtMs: number): Promise<void> {
    await this.repository.save(new RemoteKnowledgeProfile(
      profile.peerKey,
      profile.profileVersion,
      profile.profileDigest,
      profile.indexState,
      profile.knowledgeDomains,
      profile.documentCount,
      profile.chunkCount,
      profile.retrievalModes,
      profile.supportedLevels,
      profile.updatedAtMs,
      receivedAtMs,
      receivedAtMs + REMOTE_PROFILE_TTL_MS
    ));
  }

  async get(peerKey: string, nowMs: number,
    peerOnline: boolean): Promise<RemoteKnowledgeProfile | undefined> {
    const profile: RemoteKnowledgeProfile | undefined = await this.repository.get(peerKey);
    if (profile === undefined) {
      return undefined;
    }
    if (peerOnline) {
      return profile.expiresAtMs >= nowMs ? profile : undefined;
    }
    return nowMs - profile.receivedAtMs <= REMOTE_PROFILE_OFFLINE_RETENTION_MS
      ? profile : undefined;
  }

  listFresh(nowMs: number): Promise<RemoteKnowledgeProfile[]> {
    return this.repository.listFresh(nowMs);
  }
}
