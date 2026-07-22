import { describe, expect, it } from '@ohos/hypium';
import { Sha256ContentDigester, Sha256DigestProvider } from '../main/ets/communication/tls/ContentDigest';
import { EvidenceUnit } from '../main/ets/contracts/semantic/SemanticModels';

function evidence(id: string, device: string): EvidenceUnit {
  return { semanticContractVersion: '1.0', evidenceId: id, evidenceGroupId: 'g', sourceDeviceId: device, sourceDocId: 'doc-' + id, level: 'L1', title: 'Title', summary: 'Summary', snippet: 'Snippet', relevance: 0.8, coveredConcepts: ['b', 'a'], estimatedCoverageGain: 0.4, byteCost: 1, privacyLevel: 'PRIVATE_GROUP', privacyCost: 0, energyCost: 0, hash: 'legacy', canEscalateTo: ['L2'] };
}

class FixedDigestProvider implements Sha256DigestProvider {
  private readonly value: string;

  constructor(value: string) {
    this.value = value;
  }

  async digest(_data: Uint8Array): Promise<string> {
    return this.value;
  }
}

export default function contentDigestTest(): void {
  describe('Sha256ContentDigester', () => {
    it('hashes abc with SHA-256', 0, async () => {
      const data: Uint8Array = new Uint8Array([97, 98, 99]);
      const provider: Sha256DigestProvider = new FixedDigestProvider(
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(await new Sha256ContentDigester({ provider }).digestBytes(data))
        .assertEqual('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
    it('ignores identity and sorts concepts', 0, async () => {
      const provider: Sha256DigestProvider = new FixedDigestProvider('canonical-evidence-digest');
      const d = new Sha256ContentDigester({ provider });
      expect(await d.digestEvidence(evidence('a', 'b'))).assertEqual(await d.digestEvidence(evidence('z', 'c')));
    });
  });
}
