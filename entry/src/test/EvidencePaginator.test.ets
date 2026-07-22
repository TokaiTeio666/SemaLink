import { describe, expect, it } from '@ohos/hypium';
import { AppError } from '../main/ets/common/AppError';
import { EvidenceUnit } from '../main/ets/contracts/semantic/SemanticModels';
import { utf8ByteLength } from '../main/ets/knowledge/payload/Utf8Sizer';
import { EvidencePaginator } from '../main/ets/protocol/EvidencePaginator';
import { ProtocolCodec } from '../main/ets/protocol/ProtocolCodec';
import {
  EvidencePayload,
  MAX_MESSAGE_BYTES,
  ProtocolEnvelope
} from '../main/ets/protocol/ProtocolModels';

function evidence(id: string, summaryLength: number): EvidenceUnit {
  return {
    semanticContractVersion: '1.0',
    evidenceId: id,
    evidenceGroupId: 'group-' + id,
    sourceDeviceId: 'remote-device',
    sourceDocId: 'doc-' + id,
    level: 'L1',
    title: 'title-' + id,
    summary: 'x'.repeat(summaryLength),
    relevance: 0.9,
    coveredConcepts: ['alpha'],
    estimatedCoverageGain: 0.5,
    byteCost: 100,
    privacyLevel: 'PRIVATE_GROUP',
    privacyCost: 0.2,
    energyCost: 0.05,
    hash: 'hash-' + id,
    canEscalateTo: ['L2']
  };
}

export default function evidencePaginatorTest(): void {
  describe('EvidencePaginator', () => {
    it('packs complete evidence units into ordered messages below 1 KiB', 0, () => {
      const codec: ProtocolCodec = new ProtocolCodec();
      const paginator: EvidencePaginator = new EvidencePaginator(codec);
      const pages: ProtocolEnvelope[] = paginator.paginate('message', 'session', 'task', 1000, 1,
        [evidence('one', 400), evidence('two', 400), evidence('three', 400)]);

      expect(pages.length).assertEqual(3);
      expect(pages[0].messageId === pages[1].messageId).assertFalse();
      expect(pages[1].messageId === pages[2].messageId).assertFalse();
      const ids: string[] = [];
      for (let i = 0; i < pages.length; i++) {
        const payload: EvidencePayload = pages[i].payload as EvidencePayload;
        expect(payload.pageIndex).assertEqual(i);
        expect(payload.pageCount).assertEqual(3);
        expect(payload.evidence.length).assertEqual(1);
        expect(utf8ByteLength(codec.encode(pages[i])) <= MAX_MESSAGE_BYTES).assertTrue();
        ids.push(payload.evidence[0].evidenceId);
      }
      expect(ids.join(',')).assertEqual('one,two,three');
    });

    it('uses a single page when all evidence fits', 0, () => {
      const paginator: EvidencePaginator = new EvidencePaginator();
      const pages: ProtocolEnvelope[] = paginator.paginate('message', 'session', 'task', 1000, 1,
        [evidence('one', 10), evidence('two', 10)]);

      expect(pages.length).assertEqual(1);
      const payload: EvidencePayload = pages[0].payload as EvidencePayload;
      expect(payload.pageIndex).assertEqual(0);
      expect(payload.pageCount).assertEqual(1);
      expect(payload.evidence.length).assertEqual(2);
    });

    it('rejects a single evidence unit that cannot fit one message', 0, () => {
      const paginator: EvidencePaginator = new EvidencePaginator();
      let code: string = '';
      try {
        paginator.paginate('message', 'session', 'task', 1000, 1,
          [evidence('oversized', MAX_MESSAGE_BYTES + 100)]);
      } catch (error) {
        code = (error as AppError).code;
      }
      expect(code).assertEqual('E_EVIDENCE_TOO_LARGE');
    });

    it('returns no pages for empty evidence', 0, () => {
      const paginator: EvidencePaginator = new EvidencePaginator();
      expect(paginator.paginate('message', 'session', 'task', 1000, 1, []).length).assertEqual(0);
    });
  });
}
