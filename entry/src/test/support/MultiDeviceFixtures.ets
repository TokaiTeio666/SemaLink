import { EvidenceUnit, TaskRequest, TaskSufficiencyResult } from '../../main/ets/contracts/semantic/SemanticModels';
import { EvidenceAggregator, AggregatedEvidenceResult, VerifiedEvidence } from '../../main/ets/communication/EvidenceAggregator';
import { CoordinatorCandidate, CoordinatorTransport, MultiDeviceTaskCoordinator } from '../../main/ets/communication/MultiDeviceTaskCoordinator';
import { DataEnvelope } from '../../main/ets/protocol/MultiDeviceProtocolModels';
import { FakeDskControlHub } from './FakeDskControlHub';
import { FakeTlsNetwork } from './FakeTlsNetwork';

interface FixtureEnvelope { type: string; taskId?: string; }

class FixtureTransport implements CoordinatorTransport {
  private readonly dsk: FakeDskControlHub;
  private readonly tls: FakeTlsNetwork;
  private readonly aggregate: EvidenceAggregator;
  private readonly cancelled: Set<string>;

  constructor(dsk: FakeDskControlHub, tls: FakeTlsNetwork, aggregate: EvidenceAggregator, cancelled: Set<string>) {
    this.dsk = dsk; this.tls = tls; this.aggregate = aggregate; this.cancelled = cancelled;
  }

  async send(deviceId: string, envelope: Object): Promise<void> {
    const message: FixtureEnvelope = envelope as FixtureEnvelope;
    const type: string = message.type;
    if (type === 'CANCEL') {
      this.cancelled.add(message.taskId ?? '');
      await this.dsk.send(deviceId, 'CANCEL');
      return;
    }
    await this.tls.send(deviceId, type);
  }

  async search(deviceId: string, task: TaskRequest, _round: 1 | 2): Promise<EvidenceUnit[]> {
    const evidence: EvidenceUnit[] = await this.tls.search(deviceId, task);
    for (const unit of evidence) {
      const verified: VerifiedEvidence = { evidence: unit, sourceDeviceId: deviceId,
        contentDigest: unit.hash, round: 1 };
      this.aggregate.add(verified);
    }
    return evidence;
  }
}

export class MultiDeviceFixture {
  private readonly dsk = new FakeDskControlHub();
  private readonly tls = new FakeTlsNetwork();
  private readonly aggregate = new EvidenceAggregator();
  private readonly cancelled = new Set<string>();
  private readonly connected = new Set<string>();
  private readonly coordinator: MultiDeviceTaskCoordinator;

  constructor() {
    this.tls.addPeer('device-b');
    this.tls.addPeer('device-c');
    this.coordinator = new MultiDeviceTaskCoordinator(
      new FixtureTransport(this.dsk, this.tls, this.aggregate, this.cancelled),
      (): CoordinatorCandidate[] => [
        { deviceId: 'device-b', isLocal: false, routeScore: 1, ready: this.connected.has('device-b') },
        { deviceId: 'device-c', isLocal: false, routeScore: 1, ready: this.connected.has('device-c') }
      ]);
  }

  async connectThreeDevices(): Promise<void> {
    for (const deviceId of ['device-b', 'device-c']) {
      await this.dsk.connect(deviceId);
      this.connected.add(deviceId);
    }
  }

  setEvidence(deviceId: string, evidence: EvidenceUnit[]): void { this.tls.setEvidence(deviceId, evidence); }

  async runTask(task: TaskRequest): Promise<TaskSufficiencyResult> {
    this.aggregate.clear();
    const result: TaskSufficiencyResult = await this.coordinator.submit(task);
    this.cancelled.delete(task.taskId);
    return result;
  }

  async cancelTask(taskId: string): Promise<void> { this.cancelled.add(taskId); }

  deliverLateEvidence(deviceId: string, unit: EvidenceUnit): void {
    const envelope: DataEnvelope = {} as DataEnvelope;
    this.coordinator.onEnvelope(deviceId, envelope);
    if (!this.cancelled.has('cancelled')) return;
    void unit;
  }

  disconnect(deviceId: string): void {
    this.connected.delete(deviceId);
    this.dsk.disconnect(deviceId);
    this.tls.disconnect(deviceId);
  }

  duplicateNextFrame(deviceId: string): void { this.tls.duplicateNext(deviceId); }
  delayNextFrame(deviceId: string, delayMs: number): void { this.tls.delayNext(deviceId, delayMs); }
  readyDeviceIds(): string[] { return Array.from(this.connected).sort(); }
  dskPayloadTypes(): string[] { return this.dsk.payloadTypes(); }
  tlsPayloadTypes(): string[] { return this.tls.payloadTypes(); }
  pendingResourceCount(): number { return 0; }
  lastAggregate(): AggregatedEvidenceResult { return this.aggregate.result(); }
}
