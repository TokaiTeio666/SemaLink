import { EvidenceLevel } from '../../contracts/semantic/SemanticModels';
import { CollaborationPeer } from './CollaborationModels';
import { normalizeKnowledgeDomain } from
  '../../contracts/semantic/KnowledgeDomainNormalizer';

export class SharingPolicy {
  readonly enabled: boolean;
  readonly requireTrustedPeer: boolean;
  readonly allowedLevels: EvidenceLevel[];
  readonly maxEvidenceCount: number;
  readonly maxSnippetChars: number;
  readonly allowedDomains: string[];
  readonly deniedDomains: string[];
  readonly updatedAtMs: number;
  readonly revision: number;

  constructor(enabled: boolean, requireTrustedPeer: boolean, allowedLevels: EvidenceLevel[],
    maxEvidenceCount: number, maxSnippetChars: number, allowedDomains: string[],
    deniedDomains: string[], updatedAtMs: number, revision: number) {
    if (maxEvidenceCount < 1 || maxEvidenceCount > 20 ||
      maxSnippetChars < 1 || maxSnippetChars > 4096 || revision < 1) {
      throw new Error('invalid sharing policy limits');
    }
    this.enabled = enabled;
    this.requireTrustedPeer = requireTrustedPeer;
    this.allowedLevels = allowedLevels.slice();
    this.maxEvidenceCount = maxEvidenceCount;
    this.maxSnippetChars = maxSnippetChars;
    this.allowedDomains = allowedDomains.slice();
    this.deniedDomains = deniedDomains.slice();
    this.updatedAtMs = updatedAtMs;
    this.revision = revision;
  }

  static defaults(nowMs: number): SharingPolicy {
    return new SharingPolicy(false, true, ['L1'], 5, 512, [], [], nowMs, 1);
  }

  allows(peer: CollaborationPeer, level: EvidenceLevel, domain: string): boolean {
    if (!this.enabled) {
      return false;
    }
    if (this.requireTrustedPeer && peer.trustState !== 'TRUSTED') {
      return false;
    }
    const normalizedDomain: string = normalizeKnowledgeDomain(domain);
    const normalizedDenied: string[] = this.deniedDomains.map(
      (value: string): string => normalizeKnowledgeDomain(value)
    );
    if (this.allowedLevels.indexOf(level) < 0 ||
      (normalizedDomain.length > 0 && normalizedDenied.indexOf(normalizedDomain) >= 0)) {
      return false;
    }
    if (this.allowedDomains.length === 0) {
      return true;
    }
    const normalizedAllowed: string[] = this.allowedDomains.map(
      (value: string): string => normalizeKnowledgeDomain(value)
    );
    return normalizedDomain.length > 0 &&
      normalizedAllowed.indexOf(normalizedDomain) >= 0;
  }
}
