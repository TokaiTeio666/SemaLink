import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeProfile } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { KnowledgeProfileDigestBuilder } from
  '../main/ets/crossdevice/profile/KnowledgeProfileDigestBuilder';

function profile(): KnowledgeProfile {
  return {
    contractVersion: '1.0',
    profileVersion: 'v1',
    indexState: 'READY',
    knowledgeDomains: [
      { tag: 'beta', weight: 0.5, documentCount: 1 },
      { tag: 'alpha', weight: 1, documentCount: 2 }
    ],
    documentCount: 3,
    chunkCount: 8,
    modalities: ['text'],
    retrievalModes: ['keyword'],
    supportedLevels: ['L1'],
    indexVersion: 'internal-index-version',
    embeddingModelVersion: 'private-model',
    updatedAt: 100
  };
}

export default function knowledgeProfileDigestTest(): void {
  describe('KnowledgeProfileDigestBuilder', () => {
    it('uses a deterministic privacy-safe canonical projection', 0, () => {
      const builder = new KnowledgeProfileDigestBuilder();
      const first: string = builder.canonicalText(profile());
      const changed: KnowledgeProfile = profile();
      changed.indexVersion = 'another-internal-value';
      changed.embeddingModelVersion = 'another-private-model';
      expect(builder.canonicalText(changed)).assertEqual(first);
      expect(first.includes('internal-index-version')).assertFalse();
      expect(first.indexOf('alpha') < first.indexOf('beta')).assertTrue();
    });

    it('rejects profiles with more than twenty domains or over eight KiB', 0, () => {
      const builder = new KnowledgeProfileDigestBuilder();
      const oversized: KnowledgeProfile = profile();
      oversized.knowledgeDomains = [];
      for (let index: number = 0; index < 21; index++) {
        oversized.knowledgeDomains.push({
          tag: 'domain-' + index + '-'.repeat(500),
          weight: 1,
          documentCount: 1
        });
      }
      let rejected: boolean = false;
      try {
        builder.canonicalText(oversized);
      } catch (_) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });
  });
}
