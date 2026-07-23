import { describe, expect, it } from '@ohos/hypium';
import { EvidenceUnit } from '../main/ets/contracts/semantic/SemanticModels';
import { SharingPolicy } from '../main/ets/crossdevice/model/SharingPolicy';
import { RemoteEvidenceSanitizer } from
  '../main/ets/crossdevice/query/RemoteEvidenceSanitizer';

export default function remoteEvidenceSizeLimitTest(): void {
  describe('RemoteEvidenceSizeLimit', () => {
    it('keeps the serialized response below 64 KiB', 0, () => {
      const input: EvidenceUnit = {
        semanticContractVersion: '1.0', evidenceId: 'e', evidenceGroupId: 'g',
        sourceDeviceId: 'd', sourceDocId: 'doc', level: 'L1',
        title: 'T'.repeat(70000), summary: 'S'.repeat(70000), snippet: 'X'.repeat(70000),
        relevance: 1, coveredConcepts: ['domain'], estimatedCoverageGain: 1,
        byteCost: 1, privacyLevel: 'PRIVATE_GROUP', privacyCost: 0, energyCost: 0,
        hash: 'h', canEscalateTo: ['L1']
      };
      const policy = new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 1, 1);
      const output = new RemoteEvidenceSanitizer().sanitize(
        [input], policy, 'Alias', 'domain', 100
      );
      expect(JSON.stringify(output).length < 64 * 1024).assertTrue();
      expect(output.truncated).assertTrue();
    });
  });
}
