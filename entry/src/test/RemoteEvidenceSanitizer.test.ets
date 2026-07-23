import { describe, expect, it } from '@ohos/hypium';
import { EvidenceUnit } from '../main/ets/contracts/semantic/SemanticModels';
import { SharingPolicy } from '../main/ets/crossdevice/model/SharingPolicy';
import { RemoteEvidenceSanitizer } from
  '../main/ets/crossdevice/query/RemoteEvidenceSanitizer';

function evidence(index: number, relevance: number, snippet: string): EvidenceUnit {
  return {
    semanticContractVersion: '1.0',
    evidenceId: 'private-evidence-' + index,
    evidenceGroupId: 'private-group',
    sourceDeviceId: 'hardware-id',
    sourceDocId: 'database-id',
    sourceChunkId: 'chunk-id',
    level: 'L1',
    title: 'Safe title ' + index,
    summary: 'Safe summary ' + index,
    snippet: snippet,
    relevance: relevance,
    coveredConcepts: ['domain'],
    estimatedCoverageGain: 0.1,
    byteCost: 1,
    privacyLevel: 'PRIVATE_GROUP',
    privacyCost: 0,
    energyCost: 0,
    hash: 'hash-' + index,
    canEscalateTo: ['L1']
  };
}

export default function remoteEvidenceSanitizerTest(): void {
  describe('RemoteEvidenceSanitizer', () => {
    it('keeps the five most relevant items and truncates snippets', 0, () => {
      const sanitizer = new RemoteEvidenceSanitizer();
      const policy = new SharingPolicy(true, true, ['L1'], 5, 12, [], [], 1, 1);
      const input: EvidenceUnit[] = [];
      for (let index: number = 0; index < 7; index++) {
        input.push(evidence(index, index / 10, '0123456789abcdef'));
      }
      const output = sanitizer.sanitize(input, policy, 'Peer Alias', 'domain', 100);
      expect(output.evidence.length).assertEqual(5);
      expect(output.evidence[0].relevance).assertEqual(0.6);
      expect(output.evidence[0].snippet.length).assertEqual(12);
      expect(output.truncated).assertTrue();
    });
  });
}
