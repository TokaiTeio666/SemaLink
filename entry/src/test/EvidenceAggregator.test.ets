import { describe, expect, it } from '@ohos/hypium';
import { EvidenceUnit } from '../main/ets/contracts/semantic/SemanticModels';
import { EvidenceAggregator, VerifiedEvidence } from '../main/ets/communication/EvidenceAggregator';

function evidence(id: string, hash: string, source: string, round: 1 | 2): EvidenceUnit {
  return { semanticContractVersion: '1.0', evidenceId: id, evidenceGroupId: 'group-' + id,
    sourceDeviceId: source, sourceDocId: 'doc-' + id, level: round === 1 ? 'L1' : 'L2', title: id,
    summary: 'same', relevance: 1, coveredConcepts: ['concept'], estimatedCoverageGain: 1,
    byteCost: 10, privacyLevel: 'PRIVATE_GROUP', privacyCost: 0, energyCost: 0, hash: hash,
    canEscalateTo: ['L2'] };
}

function verified(unit: EvidenceUnit, source: string, round: 1 | 2): VerifiedEvidence {
  return { evidence: unit, sourceDeviceId: source, contentDigest: unit.hash, round: round };
}

export default function evidenceAggregatorTest(): void {
  describe('EvidenceAggregator', () => {
    it('merges same content and keeps stable canonical output', 0, () => {
      const aggregator = new EvidenceAggregator();
      aggregator.add(verified(evidence('z', 'digest-a', 'remote-c', 2), 'remote-c', 2));
      aggregator.add(verified(evidence('a', 'digest-a', 'remote-b', 1), 'remote-b', 1));
      const result = aggregator.result();
      expect(result.evidence.length).assertEqual(1);
      expect(result.evidence[0].evidence.evidenceId).assertEqual('a');
      expect(result.evidence[0].sourceDeviceIds.join(',')).assertEqual('remote-b,remote-c');
    });

    it('removes every version of an evidence id when its digests conflict', 0, () => {
      const aggregator = new EvidenceAggregator();
      aggregator.add(verified(evidence('same', 'digest-a', 'remote-a', 1), 'remote-a', 1));
      aggregator.add(verified(evidence('same', 'digest-b', 'remote-b', 1), 'remote-b', 1));
      const result = aggregator.result();
      expect(result.evidence.length).assertEqual(0);
      expect(result.conflicts.length).assertEqual(1);
    });
  });
}
