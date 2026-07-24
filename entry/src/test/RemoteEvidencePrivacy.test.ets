import { describe, expect, it } from '@ohos/hypium';
import { EvidenceUnit } from '../main/ets/contracts/semantic/SemanticModels';
import { SharingPolicy } from '../main/ets/crossdevice/model/SharingPolicy';
import { RemoteEvidenceSanitizer } from
  '../main/ets/crossdevice/query/RemoteEvidenceSanitizer';

export default function remoteEvidencePrivacyTest(): void {
  describe('RemoteEvidencePrivacy', () => {
    it('omits document chunk device and database identifiers', 0, () => {
      const input: EvidenceUnit = {
        semanticContractVersion: '1.0', evidenceId: 'e-private',
        evidenceGroupId: 'g-private', sourceDeviceId: 'network-secret',
        sourceDocId: 'C:\\secret\\document.txt', sourceChunkId: 'db-row',
        level: 'L1', title: 'Title', summary: 'Summary', snippet: 'Snippet',
        relevance: 0.9, coveredConcepts: ['domain'], estimatedCoverageGain: 0.1,
        byteCost: 1, privacyLevel: 'PRIVATE_GROUP', privacyCost: 0, energyCost: 0,
        hash: 'private-hash', canEscalateTo: ['L1']
      };
      const policy = new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 1, 1);
      const text: string = JSON.stringify(
        new RemoteEvidenceSanitizer().sanitize([input], policy, 'Peer Alias', 'domain', 100)
      );
      expect(text.includes('network-secret')).assertFalse();
      expect(text.includes('C:\\secret')).assertFalse();
      expect(text.includes('db-row')).assertFalse();
      expect(text.includes('Peer Alias')).assertTrue();
    });

    it('redacts paths SQL and internal identifiers embedded in returned text', 0, () => {
      const input: EvidenceUnit = {
        semanticContractVersion: '1.0', evidenceId: 'e', evidenceGroupId: 'g',
        sourceDeviceId: 'local', sourceDocId: 'doc', level: 'L1', title: 'Title',
        summary: 'file:///data/storage/el2/base/haps/secret.txt',
        snippet: 'CREATE/**/TABLE secrets(x); path=/opt/private/key',
        relevance: 0.9, coveredConcepts: ['domain'], estimatedCoverageGain: 0.1,
        byteCost: 1, privacyLevel: 'PRIVATE_GROUP', privacyCost: 0, energyCost: 0,
        hash: 'h', canEscalateTo: ['L1']
      };
      const policy = new SharingPolicy(true, true, ['L1'], 5, 512, [], [], 1, 1);
      const text: string = JSON.stringify(
        new RemoteEvidenceSanitizer().sanitize([input], policy, 'B', 'domain', 1)
      ).toLowerCase();
      expect(text.includes('/data/storage')).assertFalse();
      expect(text.includes('/opt/private')).assertFalse();
      expect(text.includes('create/**/table')).assertFalse();
      expect(text.includes('documentid=42')).assertFalse();
    });
  });
}
