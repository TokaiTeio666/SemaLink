import { describe, expect, it } from '@ohos/hypium';
import { EvidenceUnit } from '../main/ets/contracts/semantic/SemanticModels';
import { CrossDeviceEvidenceMerger } from
  '../main/ets/crossdevice/application/CrossDeviceKnowledgeQueryService';

function evidence(id: string, device: string, hash: string, relevance: number): EvidenceUnit {
  return {
    semanticContractVersion: '1.0', evidenceId: id, evidenceGroupId: id,
    sourceDeviceId: device, sourceDocId: 'opaque', level: 'L1', title: id,
    relevance: relevance, coveredConcepts: [], estimatedCoverageGain: relevance,
    byteCost: 1, privacyLevel: 'PRIVATE_GROUP', privacyCost: 0, energyCost: 0,
    hash: hash, canEscalateTo: ['L1']
  };
}

export default function crossDeviceEvidenceMergeTest(): void {
  describe('CrossDeviceEvidenceMerger', () => {
    it('deduplicates by hash retaining higher relevance and enforces caps', 0, () => {
      const input: EvidenceUnit[] = [
        evidence('low', 'local', 'same', 0.1),
        evidence('high', 'remote', 'same', 0.9)
      ];
      for (let index: number = 0; index < 10; index++) {
        input.push(evidence('e-' + index, 'device-' + (index % 2), 'h-' + index, 0.8));
      }
      const output = new CrossDeviceEvidenceMerger().merge(input);
      expect(output.length).assertEqual(8);
      expect(output.some((item: EvidenceUnit): boolean => item.evidenceId === 'high')).assertTrue();
      expect(output.some((item: EvidenceUnit): boolean => item.evidenceId === 'low')).assertFalse();
    });
  });
}
