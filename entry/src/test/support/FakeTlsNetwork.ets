import { EvidenceUnit, TaskRequest } from '../../main/ets/contracts/semantic/SemanticModels';

export interface FakeTlsPeer {
  deviceId: string;
  evidence: EvidenceUnit[];
  connected: boolean;
}

export class FakeTlsNetwork {
  private readonly payloads: string[] = [];
  private readonly peers = new Map<string, FakeTlsPeer>();
  private readonly delayed = new Map<string, number>();
  private readonly duplicated = new Set<string>();
  private readonly invalidFingerprint = new Set<string>();

  addPeer(deviceId: string): void {
    this.peers.set(deviceId, { deviceId: deviceId, evidence: [], connected: true });
  }

  setEvidence(deviceId: string, evidence: EvidenceUnit[]): void {
    const peer: FakeTlsPeer | undefined = this.peers.get(deviceId);
    if (peer !== undefined) peer.evidence = evidence.slice();
  }

  disconnect(deviceId: string): void {
    const peer: FakeTlsPeer | undefined = this.peers.get(deviceId);
    if (peer !== undefined) peer.connected = false;
  }

  delayNext(deviceId: string, delayMs: number): void { this.delayed.set(deviceId, Math.max(0, delayMs)); }
  duplicateNext(deviceId: string): void { this.duplicated.add(deviceId); }
  invalidateFingerprint(deviceId: string): void { this.invalidFingerprint.add(deviceId); }

  send(deviceId: string, payloadType: string): Promise<void> {
    const peer: FakeTlsPeer | undefined = this.peers.get(deviceId);
    if (peer === undefined || !peer.connected) return Promise.reject(new Error('E_TLS_DISCONNECTED'));
    this.payloads.push(payloadType);
    return Promise.resolve();
  }

  search(deviceId: string, _task: TaskRequest): Promise<EvidenceUnit[]> {
    const peer: FakeTlsPeer | undefined = this.peers.get(deviceId);
    if (peer === undefined || !peer.connected) return Promise.reject(new Error('E_TLS_DISCONNECTED'));
    if (this.invalidFingerprint.has(deviceId)) return Promise.reject(new Error('E_TLS_FINGERPRINT'));
    this.payloads.push('EVIDENCE_BATCH');
    const result: EvidenceUnit[] = peer.evidence.slice();
    if (this.duplicated.delete(deviceId)) {
      this.payloads.push('EVIDENCE_BATCH');
      result.push(...peer.evidence);
    }
    const delayMs: number = this.delayed.get(deviceId) ?? 0;
    this.delayed.delete(deviceId);
    if (delayMs === 0) return Promise.resolve(result);
    return new Promise<EvidenceUnit[]>((resolve): void => {
      setTimeout((): void => resolve(result), delayMs);
    });
  }

  payloadTypes(): string[] { return this.payloads.slice(); }
}
