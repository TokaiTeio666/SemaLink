import { AppError, ErrorStage } from '../common/AppError';
import { EvidenceUnit } from '../contracts/semantic/SemanticModels';
import { ProtocolCodec } from './ProtocolCodec';
import {
  EvidencePayload,
  MAX_EVIDENCE_PAGE_COUNT,
  ProtocolEnvelope
} from './ProtocolModels';

export class EvidencePaginator {
  private readonly codec: ProtocolCodec;

  constructor(codec: ProtocolCodec = new ProtocolCodec()) {
    this.codec = codec;
  }

  paginate(messageIdPrefix: string, sessionId: string, taskId: string, sentAt: number,
    round: number, evidence: EvidenceUnit[]): ProtocolEnvelope[] {
    if (evidence.length === 0) {
      return [];
    }
    const pageEvidence: EvidenceUnit[][] = [];
    let current: EvidenceUnit[] = [];
    for (const unit of evidence) {
      const candidate: EvidenceUnit[] = current.concat([unit]);
      if (this.fits(messageIdPrefix, sessionId, taskId, sentAt, round,
        pageEvidence.length, MAX_EVIDENCE_PAGE_COUNT, candidate)) {
        current = candidate;
        continue;
      }
      if (current.length === 0) {
        throw new AppError('E_EVIDENCE_TOO_LARGE', 'A single evidence unit exceeds the 1 KiB message limit',
          ErrorStage.PROTOCOL, false);
      }
      pageEvidence.push(current);
      if (pageEvidence.length >= MAX_EVIDENCE_PAGE_COUNT) {
        throw new AppError('E_EVIDENCE_PAGE_LIMIT', 'Evidence page count exceeds the protocol limit',
          ErrorStage.PROTOCOL, false);
      }
      current = [unit];
      if (!this.fits(messageIdPrefix, sessionId, taskId, sentAt, round,
        pageEvidence.length, MAX_EVIDENCE_PAGE_COUNT, current)) {
        throw new AppError('E_EVIDENCE_TOO_LARGE', 'A single evidence unit exceeds the 1 KiB message limit',
          ErrorStage.PROTOCOL, false);
      }
    }
    if (current.length > 0) {
      pageEvidence.push(current);
    }

    const pageCount: number = pageEvidence.length;
    const pages: ProtocolEnvelope[] = [];
    for (let pageIndex = 0; pageIndex < pageCount; pageIndex++) {
      const envelope: ProtocolEnvelope = this.createPage(messageIdPrefix, sessionId, taskId, sentAt,
        round, pageIndex, pageCount, pageEvidence[pageIndex]);
      this.codec.encode(envelope);
      pages.push(envelope);
    }
    return pages;
  }

  private fits(messageIdPrefix: string, sessionId: string, taskId: string, sentAt: number,
    round: number, pageIndex: number, pageCount: number, evidence: EvidenceUnit[]): boolean {
    const envelope: ProtocolEnvelope = this.createPage(messageIdPrefix, sessionId, taskId, sentAt,
      round, pageIndex, pageCount, evidence);
    try {
      this.codec.encode(envelope);
      return true;
    } catch (error) {
      const appError: AppError = error as AppError;
      if (appError.code === 'E_PROTOCOL_INVALID') {
        return false;
      }
      throw appError;
    }
  }

  private createPage(messageIdPrefix: string, sessionId: string, taskId: string, sentAt: number,
    round: number, pageIndex: number, pageCount: number, evidence: EvidenceUnit[]): ProtocolEnvelope {
    const payload: EvidencePayload = {
      taskId: taskId,
      round: round,
      pageIndex: pageIndex,
      pageCount: pageCount,
      evidence: evidence
    };
    const messageId: string = pageCount === 1
      ? messageIdPrefix
      : messageIdPrefix + '-page-' + pageIndex.toString();
    return this.codec.createEvidence(messageId, sessionId, taskId, sentAt, payload);
  }
}
