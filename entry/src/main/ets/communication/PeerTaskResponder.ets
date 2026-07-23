import { EvidenceUnit, TaskRequest } from '../contracts/semantic/SemanticModels';
import { SemanticKnowledgeProvider as KnowledgeProvider } from '../contracts/semantic/SemanticKnowledgeProvider';
import { EvidenceUtilityScheduler } from './EvidenceUtilityScheduler';
import { DataEnvelope, DataMessageType, DataPayload, EvidenceBatchPayload, EvidenceCompletePayload, EvidencePagePayload, EvidenceAckPayload, TaskAckDataPayload, TaskDataPayload, TsfDataPayload, RELIABLE_ACK_TIMEOUT_MS, RELIABLE_MAX_ATTEMPTS, RELIABLE_MAX_PAGES } from '../protocol/MultiDeviceProtocolModels';
import { MAX_DATA_MESSAGE_BYTES, MultiDeviceProtocolCodec, EvidenceDigest } from '../protocol/MultiDeviceProtocolCodec';
import { Sha256ContentDigester } from './tls/ContentDigest';
import { encodeUtf8 } from './tls/Utf8Codec';

export interface ResponderMessage { deviceId?: string; envelope: DataEnvelope; }
export interface PeerTaskResponderTransport { send(deviceId: string, message: ResponderMessage): Promise<void>; }
export interface PeerTaskResponderOptions {
  send: (deviceId: string, message: ResponderMessage) => Promise<void>;
  provider: KnowledgeProvider;
  sessionEpoch: string;
  digest?: EvidenceDigest;
}
interface TaskState {
  task: TaskRequest; candidates: EvidenceUnit[]; sent: EvidenceUnit[]; terminal: boolean; ack: DataEnvelope;
  pageAckWaiters: Map<number, (accepted: boolean) => void>;
}

export class PeerTaskResponder {
  private readonly send: (deviceId: string, message: ResponderMessage) => Promise<void>;
  private readonly provider: KnowledgeProvider;
  private readonly sessionEpoch: string;
  private readonly codec: MultiDeviceProtocolCodec;
  private readonly digester: EvidenceDigest;
  private readonly scheduler = new EvidenceUtilityScheduler();
  private readonly tasks = new Map<string, TaskState>();
  private readonly terminalTaskIds = new Set<string>();
  private sequence = 1;

  constructor(options: PeerTaskResponderOptions) {
    this.send = options.send; this.provider = options.provider; this.sessionEpoch = options.sessionEpoch;
    this.digester = options.digest ?? new Sha256ContentDigester();
    this.codec = new MultiDeviceProtocolCodec({ digest: this.digester });
  }

  async onEnvelope(deviceId: string, envelope: DataEnvelope): Promise<void> {
    try {
      await this.codec.validate(envelope, this.sessionEpoch, deviceId);
    } catch (_) {
      return;
    }
    const peerTaskId: string = envelope.peer.peerTaskId;
    if (this.terminalTaskIds.has(peerTaskId)) return;
    const existing: TaskState | undefined = this.tasks.get(peerTaskId);
    if (existing?.terminal === true) return;
    if (envelope.type === 'CANCEL' || envelope.type === 'ERROR') { this.cancel(peerTaskId); return; }
    if (envelope.type === 'EVIDENCE_ACK' && existing !== undefined) {
      const ack: EvidenceAckPayload = envelope.payload as EvidenceAckPayload;
      existing.pageAckWaiters.get(ack.pageIndex)?.(ack.status === 'OK');
      existing.pageAckWaiters.delete(ack.pageIndex);
      return;
    }
    if (envelope.type === 'TASK') {
      if (existing !== undefined) {
        await this.send(deviceId, { deviceId, envelope: existing.ack });
        return;
      }
      const task: TaskRequest = (envelope.payload as TaskDataPayload).task;
      const ack: DataEnvelope = this.make(envelope, 'TASK_ACK', {
        taskId: task.taskId, peerTaskId, round: 1, acceptedAtMs: Date.now()
      } as TaskAckDataPayload);
      const state: TaskState = { task, candidates: [], sent: [], terminal: false, ack, pageAckWaiters: new Map<number, (accepted: boolean) => void>() };
      this.tasks.set(peerTaskId, state);
      await this.send(deviceId, { deviceId, envelope: ack });
      try {
        state.candidates = await this.provider.searchEvidence(task);
        await this.sendRound(deviceId, state, 1, envelope);
      } catch (_) { this.cancel(peerTaskId); }
      return;
    }
    if (envelope.type === 'TSF' && existing !== undefined) {
      const feedback: string = (envelope.payload as TsfDataPayload).feedback;
      if (feedback === 'NEED_MORE') await this.sendRound(deviceId, existing, 2, envelope);
      else if (feedback === 'ENOUGH' || feedback === 'ABORT') this.cancel(peerTaskId);
    }
  }

  cancel(peerTaskId: string): void {
    const state = this.tasks.get(peerTaskId);
    if (state !== undefined) {
      state.terminal = true;
      for (const waiter of state.pageAckWaiters.values()) waiter(false);
      state.pageAckWaiters.clear();
    }
    this.tasks.delete(peerTaskId);
    this.terminalTaskIds.add(peerTaskId);
  }
  destroy(): void {
    const ids: string[] = [];
    for (const id of this.tasks.keys()) ids.push(id);
    for (const id of ids) this.cancel(id);
    this.terminalTaskIds.clear();
  }

  private async sendRound(deviceId: string, state: TaskState, round: 1 | 2, source: DataEnvelope): Promise<void> {
    const schedule = this.scheduler.schedule(state.task, state.candidates, round, state.sent);
    let evidence: EvidenceUnit[] = schedule.selected.slice();
    const pages: EvidenceUnit[][] = this.partition(evidence, source, round);
    if (pages.length > 1) {
      if (pages.length > RELIABLE_MAX_PAGES) throw new Error('E_EVIDENCE_PAGE_LIMIT');
      for (let pageIndex = 0; pageIndex < pages.length; pageIndex += 1) {
        await this.sendReliablePage(deviceId, state, source, round, pageIndex, pages.length, pages[pageIndex]);
        for (const unit of pages[pageIndex]) state.sent.push(unit);
      }
      await this.emit(deviceId, source, 'EVIDENCE_COMPLETE', { taskId: state.task.taskId, peerTaskId: source.peer.peerTaskId,
        round, evidenceCount: evidence.length, truncatedByBudget: evidence.length < state.candidates.length });
      return;
    }
    let batch: DataEnvelope | null = null;
    while (evidence.length > 0) {
      const digestParts: string[] = [];
      for (const unit of evidence) digestParts.push(await this.digestEvidence(unit));
      const payload: EvidenceBatchPayload = { taskId: state.task.taskId, peerTaskId: source.peer.peerTaskId,
        round, evidence, batchDigest: digestParts.join('|'), encodedBytes: 0 };
      const candidate: DataEnvelope = this.make(source, 'EVIDENCE_BATCH', payload);
      payload.encodedBytes = encodeUtf8(JSON.stringify(candidate)).length;
      if (payload.encodedBytes <= MAX_DATA_MESSAGE_BYTES) {
        batch = candidate;
        break;
      }
      evidence = evidence.slice(0, evidence.length - 1);
    }
    for (const unit of evidence) state.sent.push(unit);
    if (batch !== null) {
      await this.send(deviceId, { deviceId, envelope: batch });
    }
    const complete: EvidenceCompletePayload = { taskId: state.task.taskId, peerTaskId: source.peer.peerTaskId,
      round, evidenceCount: evidence.length, truncatedByBudget: evidence.length < state.candidates.length };
    await this.emit(deviceId, source, 'EVIDENCE_COMPLETE', complete);
  }

  private partition(evidence: EvidenceUnit[], source: DataEnvelope, round: 1 | 2): EvidenceUnit[][] {
    if (evidence.length < 2) return [evidence];
    const pages: EvidenceUnit[][] = [];
    let current: EvidenceUnit[] = [];
    for (const unit of evidence) {
      const candidate = current.concat([unit]);
      const probe: DataEnvelope = this.make(source, 'EVIDENCE_PAGE', {
        taskId: source.peer.taskId, peerTaskId: source.peer.peerTaskId, round, pageIndex: 0, pageCount: 1,
        evidence: candidate, pageDigest: 'probe', encodedBytes: 0
      } as EvidencePagePayload);
      if (current.length > 0 && encodeUtf8(JSON.stringify(probe)).length > MAX_DATA_MESSAGE_BYTES) {
        pages.push(current);
        current = [unit];
      } else current = candidate;
    }
    if (current.length > 0) pages.push(current);
    return pages.length > 1 ? pages : [evidence];
  }

  private async sendReliablePage(deviceId: string, state: TaskState, source: DataEnvelope, round: 1 | 2,
    pageIndex: number, pageCount: number, evidence: EvidenceUnit[]): Promise<void> {
    const digests: string[] = [];
    for (const unit of evidence) digests.push(await this.digestEvidence(unit));
    const payload: EvidencePagePayload = { taskId: state.task.taskId, peerTaskId: source.peer.peerTaskId, round,
      pageIndex, pageCount, evidence, pageDigest: digests.join('|'), encodedBytes: 0 };
    const envelope: DataEnvelope = this.make(source, 'EVIDENCE_PAGE', payload);
    payload.encodedBytes = encodeUtf8(JSON.stringify(envelope)).length;
    for (let attempt = 1; attempt <= RELIABLE_MAX_ATTEMPTS; attempt += 1) {
      const accepted = await new Promise<boolean>((resolve) => {
        const timer = setTimeout((): void => { state.pageAckWaiters.delete(pageIndex); resolve(false); }, RELIABLE_ACK_TIMEOUT_MS);
        state.pageAckWaiters.set(pageIndex, (ok: boolean): void => { clearTimeout(timer); resolve(ok); });
        this.send(deviceId, { deviceId, envelope }).catch((): void => {
          state.pageAckWaiters.delete(pageIndex);
          resolve(false);
        });
      });
      if (accepted) return;
    }
    throw new Error('E_EVIDENCE_PAGE_ACK_TIMEOUT');
  }
  private async digestEvidence(unit: EvidenceUnit): Promise<string> {
    return await this.digester.digestEvidence(unit);
  }
  private make(source: DataEnvelope, type: DataMessageType, payload: DataPayload): DataEnvelope {
    return { version: '2.0', type, messageId: source.messageId + '-' + type, sentAtMs: Date.now(),
      peer: { taskId: source.peer.taskId, peerTaskId: source.peer.peerTaskId, sessionEpoch: source.peer.sessionEpoch, sequence: this.sequence++ },
      payload: payload };
  }
  private async emit(deviceId: string, source: DataEnvelope, type: DataMessageType, payload: DataPayload): Promise<void> {
    await this.send(deviceId, { deviceId, envelope: this.make(source, type, payload) });
  }
}
