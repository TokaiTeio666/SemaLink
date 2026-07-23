import { EvidenceUnit } from '../contracts/semantic/SemanticModels';
import { Sha256ContentDigester } from '../communication/tls/ContentDigest';
import { encodeUtf8 } from '../communication/tls/Utf8Codec';
import {
  DataEnvelope, DataMessageType, EvidenceBatchPayload, EvidencePagePayload,
  EvidenceAckPayload, DataPayload, PeerContext, RELIABLE_MAX_PAGES
} from './MultiDeviceProtocolModels';
export { DataEnvelope, EvidenceBatchPayload } from './MultiDeviceProtocolModels';

export const MAX_DATA_MESSAGE_BYTES: number = 64 * 1024;
const TYPES: DataMessageType[] = ['DATA_BIND', 'DATA_BIND_ACK', 'TASK', 'TASK_ACK', 'EVIDENCE_BATCH',
  'EVIDENCE_COMPLETE', 'EVIDENCE_PAGE', 'EVIDENCE_ACK', 'TSF', 'ERROR', 'CANCEL'];

export interface EvidenceDigest { digestEvidence(evidence: EvidenceUnit): Promise<string>; }
export interface MultiDeviceCodecOptions { digest?: EvidenceDigest; }

function invalid(): Error { return new Error('E_DATA_PROTOCOL_INVALID'); }
function bytes(text: string): number { return encodeUtf8(text).length; }
function hasType(value: string): boolean { return TYPES.indexOf(value as DataMessageType) >= 0; }
function nonEmpty(value: Object | undefined): boolean { return typeof value === 'string' && (value as string).length > 0; }
function validPeer(peer: Object | undefined): boolean {
  if (peer === undefined || typeof peer !== 'object') return false;
  const value = peer as PeerContext;
  if (!nonEmpty(value.taskId) || !nonEmpty(value.peerTaskId) || !nonEmpty(value.sessionEpoch) ||
    !Number.isInteger(value.sequence) || value.sequence <= 0) return false;
  return value.peerTaskId.indexOf(value.taskId + '@') === 0;
}

export class MultiDeviceProtocolCodec {
  private readonly digest: EvidenceDigest;
  constructor(options?: MultiDeviceCodecOptions) { this.digest = options?.digest ?? new Sha256ContentDigester(); }

  encode(envelope: DataEnvelope): string {
    this.validateShape(envelope);
    const encoded: string = JSON.stringify(envelope);
    if (bytes(encoded) > MAX_DATA_MESSAGE_BYTES) throw invalid();
    return encoded;
  }

  decode(encoded: string, sessionEpoch: string, deviceId: string): DataEnvelope {
    if (bytes(encoded) > MAX_DATA_MESSAGE_BYTES) throw invalid();
    let value: DataEnvelope;
    try { value = JSON.parse(encoded) as DataEnvelope; } catch (_) { throw invalid(); }
    this.validateShape(value);
    if (value.peer.sessionEpoch !== sessionEpoch) throw invalid();
    return value;
  }

  async validate(envelope: DataEnvelope, sessionEpoch: string, deviceId: string): Promise<void> {
    this.validateShape(envelope);
    if (envelope.peer.sessionEpoch !== sessionEpoch) throw invalid();
    if (envelope.type === 'EVIDENCE_BATCH') {
      const payload: EvidenceBatchPayload = envelope.payload as EvidenceBatchPayload;
      const digests: string[] = [];
      for (const unit of payload.evidence) digests.push(await this.digest.digestEvidence(unit));
      if (payload.batchDigest !== digests.join('|')) throw invalid();
      if (!Number.isInteger(payload.encodedBytes) || payload.encodedBytes <= 0 || payload.encodedBytes > MAX_DATA_MESSAGE_BYTES) throw invalid();
    }
    if (envelope.type === 'EVIDENCE_PAGE') {
      const payload: EvidencePagePayload = envelope.payload as EvidencePagePayload;
      const digests: string[] = [];
      for (const unit of payload.evidence) digests.push(await this.digest.digestEvidence(unit));
      if (payload.pageDigest !== digests.join('|') || !Number.isInteger(payload.encodedBytes) ||
        payload.encodedBytes <= 0 || payload.encodedBytes > MAX_DATA_MESSAGE_BYTES) throw invalid();
    }
  }

  private validateShape(envelope: DataEnvelope): void {
    if (envelope === undefined || envelope.version !== '2.0' || !hasType(envelope.type) ||
      !nonEmpty(envelope.messageId) || !Number.isFinite(envelope.sentAtMs) || !validPeer(envelope.peer) ||
      envelope.payload === undefined) throw invalid();
    const payload: DataPayload = envelope.payload;
    if (envelope.type === 'EVIDENCE_BATCH') {
      const batch: EvidenceBatchPayload = payload as EvidenceBatchPayload;
      if (!Array.isArray(batch.evidence) || (batch.round !== 1 && batch.round !== 2) || !nonEmpty(batch.batchDigest)) throw invalid();
    }
    if (envelope.type === 'EVIDENCE_PAGE') {
      const page: EvidencePagePayload = payload as EvidencePagePayload;
      if (!Array.isArray(page.evidence) || (page.round !== 1 && page.round !== 2) ||
        !Number.isInteger(page.pageIndex) || page.pageIndex < 0 ||
        !Number.isInteger(page.pageCount) || page.pageCount < 1 ||
        page.pageCount > RELIABLE_MAX_PAGES || page.pageIndex >= page.pageCount ||
        !nonEmpty(page.pageDigest)) throw invalid();
    }
    if (envelope.type === 'EVIDENCE_ACK') {
      const ack: EvidenceAckPayload = payload as EvidenceAckPayload;
      if (!Number.isInteger(ack.pageIndex) || ack.pageIndex < 0 ||
        (ack.status !== 'OK' && ack.status !== 'ERROR')) throw invalid();
    }
  }
}
