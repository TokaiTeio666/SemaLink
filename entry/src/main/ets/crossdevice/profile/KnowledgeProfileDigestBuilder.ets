import {
  KnowledgeDomain,
  KnowledgeProfile
} from '../../contracts/knowledge/KnowledgeModels';
import { Sha256ContentDigester } from '../../communication/tls/ContentDigest';
import { encodeUtf8 } from '../../communication/tls/Utf8Codec';

interface CanonicalProfileDomain {
  tag: string;
  weight: number;
  documentCount: number;
}

interface CanonicalKnowledgeProfile {
  contractVersion: string;
  profileVersion: string;
  indexState: string;
  knowledgeDomains: CanonicalProfileDomain[];
  documentCount: number;
  chunkCount: number;
  modalities: string[];
  retrievalModes: string[];
  supportedLevels: string[];
  updatedAt: number;
}

export const MAX_REMOTE_PROFILE_DOMAINS: number = 20;
export const MAX_REMOTE_PROFILE_BYTES: number = 8 * 1024;

export class KnowledgeProfileDigestBuilder {
  private readonly digester: Sha256ContentDigester;

  constructor(digester: Sha256ContentDigester = new Sha256ContentDigester()) {
    this.digester = digester;
  }

  canonicalText(profile: KnowledgeProfile): string {
    if (profile.knowledgeDomains.length > MAX_REMOTE_PROFILE_DOMAINS) {
      throw new Error('PROFILE_DOMAIN_LIMIT');
    }
    const domains: CanonicalProfileDomain[] = profile.knowledgeDomains.map(
      (domain: KnowledgeDomain): CanonicalProfileDomain => {
        return {
          tag: domain.tag,
          weight: domain.weight,
          documentCount: domain.documentCount
        };
      }
    );
    domains.sort((left: CanonicalProfileDomain, right: CanonicalProfileDomain): number =>
      left.tag.localeCompare(right.tag));
    const canonical: CanonicalKnowledgeProfile = {
      contractVersion: profile.contractVersion,
      profileVersion: profile.profileVersion,
      indexState: profile.indexState,
      knowledgeDomains: domains,
      documentCount: profile.documentCount,
      chunkCount: profile.chunkCount,
      modalities: profile.modalities.slice().sort(),
      retrievalModes: profile.retrievalModes.slice().sort(),
      supportedLevels: profile.supportedLevels.slice().sort(),
      updatedAt: profile.updatedAt
    };
    const text: string = JSON.stringify(canonical);
    if (encodeUtf8(text).length > MAX_REMOTE_PROFILE_BYTES) {
      throw new Error('PROFILE_SIZE_LIMIT');
    }
    return text;
  }

  digest(profile: KnowledgeProfile): Promise<string> {
    return this.digester.digestBytes(encodeUtf8(this.canonicalText(profile)));
  }
}
