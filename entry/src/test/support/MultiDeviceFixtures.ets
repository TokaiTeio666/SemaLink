import { EvidenceUnit, TaskRequest, TaskSufficiencyResult } from '../../main/ets/contracts/semantic/SemanticModels';
import { EvidenceAggregator, AggregatedEvidenceResult, VerifiedEvidence } from '../../main/ets/communication/EvidenceAggregator';
import { CoordinatorCandidate, CoordinatorTransport, MultiDeviceTaskCoordinator } from '../../main/ets/communication/MultiDeviceTaskCoordinator';
import {
  MeshSessionDirection,
  planFullMeshEdges,
  preferredSessionDirection
} from '../../main/ets/communication/PeerMeshPlanner';
import { DataEnvelope } from '../../main/ets/protocol/MultiDeviceProtocolModels';
import { FakeDskControlHub } from './FakeDskControlHub';
import { FakeTlsNetwork } from './FakeTlsNetwork';

const DEVICE_IDS: string[] = ['device-a', 'device-b', 'device-c'];

interface FixtureEnvelope { type: string; taskId?: string; }

interface FixtureNode {
  deviceId: string;
  connected: Set<string>;
  aggregate: EvidenceAggregator;
  coordinator: MultiDeviceTaskCoordinator;
}

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
  private readonly cancelled = new Set<string>();
  private readonly nodes = new Map<string, FixtureNode>();
  private readonly available = new Set<string>(DEVICE_IDS);
  private readonly evidenceByDevice = new Map<string, EvidenceUnit[]>();
  private readonly activeConnections = new Map<string, MeshSessionDirection[]>();
  private readonly connectionAttempts = new Map<string, number>();
  private lastRunDeviceId: string = 'device-a';

  constructor() {
    for (const deviceId of DEVICE_IDS) {
      this.tls.addPeer(deviceId);
      this.evidenceByDevice.set(deviceId, []);
      const aggregate = new EvidenceAggregator();
      const node: FixtureNode = {
        deviceId: deviceId,
        connected: new Set<string>(),
        aggregate: aggregate,
        coordinator: new MultiDeviceTaskCoordinator(
          new FixtureTransport(this.dsk, this.tls, aggregate, this.cancelled),
          (): CoordinatorCandidate[] => this.candidatesOf(deviceId))
      };
      this.nodes.set(deviceId, node);
    }
  }

  async connectFullMesh(): Promise<void> {
    for (const deviceId of DEVICE_IDS) {
      if (!this.available.has(deviceId)) {
        this.available.add(deviceId);
        this.tls.addPeer(deviceId);
        this.tls.setEvidence(deviceId, this.evidenceByDevice.get(deviceId) ?? []);
      }
    }
    for (const edge of planFullMeshEdges(DEVICE_IDS)) {
      if ((this.activeConnections.get(edge)?.length ?? 0) > 0) continue;
      const devices: string[] = edge.split('->');
      await this.dsk.connect(devices[1]);
      this.nodes.get(devices[0])?.connected.add(devices[1]);
      this.nodes.get(devices[1])?.connected.add(devices[0]);
      this.activeConnections.set(edge, [preferredSessionDirection(devices[0], devices[1])]);
      this.connectionAttempts.set(edge, (this.connectionAttempts.get(edge) ?? 0) + 1);
    }
  }

  async connectThreeDevices(): Promise<void> { await this.connectFullMesh(); }

  setEvidence(deviceId: string, evidence: EvidenceUnit[]): void {
    this.evidenceByDevice.set(deviceId, evidence.slice());
    this.tls.setEvidence(deviceId, evidence);
  }

  async runTaskFrom(deviceId: string, task: TaskRequest): Promise<TaskSufficiencyResult> {
    const node: FixtureNode | undefined = this.nodes.get(deviceId);
    if (node === undefined) throw new Error('E_FIXTURE_NODE_UNKNOWN');
    node.aggregate.clear();
    this.lastRunDeviceId = deviceId;
    const result: TaskSufficiencyResult = await node.coordinator.submit(task);
    this.cancelled.delete(task.taskId);
    return result;
  }

  async runTask(task: TaskRequest): Promise<TaskSufficiencyResult> {
    return await this.runTaskFrom('device-a', task);
  }

  async cancelTask(taskId: string): Promise<void> { this.cancelled.add(taskId); }

  deliverLateEvidence(deviceId: string, unit: EvidenceUnit): void {
    const envelope: DataEnvelope = {} as DataEnvelope;
    this.nodes.get('device-a')?.coordinator.onEnvelope(deviceId, envelope);
    if (!this.cancelled.has('cancelled')) return;
    void unit;
  }

  disconnect(deviceId: string): void {
    if (!this.available.delete(deviceId)) return;
    const node: FixtureNode | undefined = this.nodes.get(deviceId);
    if (node !== undefined) node.connected.clear();
    for (const other of this.nodes.values()) other.connected.delete(deviceId);
    for (const edge of planFullMeshEdges(DEVICE_IDS)) {
      const devices: string[] = edge.split('->');
      if (devices.indexOf(deviceId) >= 0) this.activeConnections.delete(edge);
    }
    this.dsk.disconnect(deviceId);
    this.tls.disconnect(deviceId);
  }

  injectBackupConnection(leftDeviceId: string, rightDeviceId: string): void {
    const edge: string = this.edgeOf(leftDeviceId, rightDeviceId);
    const sessions: MeshSessionDirection[] | undefined = this.activeConnections.get(edge);
    if (sessions === undefined || sessions.length === 0) return;
    const devices: string[] = edge.split('->');
    const preferred: MeshSessionDirection = preferredSessionDirection(devices[0], devices[1]);
    sessions.push(preferred === 'OUTBOUND' ? 'INBOUND' : 'OUTBOUND');
    this.connectionAttempts.set(edge, (this.connectionAttempts.get(edge) ?? 0) + 1);
  }

  convergeDuplicateConnections(): void {
    for (const edge of this.activeConnections.keys()) {
      const devices: string[] = edge.split('->');
      const preferred: MeshSessionDirection = preferredSessionDirection(devices[0], devices[1]);
      const sessions: MeshSessionDirection[] = this.activeConnections.get(edge) ?? [];
      if (sessions.indexOf(preferred) >= 0) this.activeConnections.set(edge, [preferred]);
    }
  }

  connectionCount(leftDeviceId: string, rightDeviceId: string): number {
    return this.activeConnections.get(this.edgeOf(leftDeviceId, rightDeviceId))?.length ?? 0;
  }

  connectionDirection(leftDeviceId: string, rightDeviceId: string): MeshSessionDirection | undefined {
    const edge: string = this.edgeOf(leftDeviceId, rightDeviceId);
    const direction: MeshSessionDirection | undefined = this.activeConnections.get(edge)?.[0];
    if (direction === undefined) return undefined;
    const sortedLeft: string = edge.split('->')[0];
    if (leftDeviceId === sortedLeft) return direction;
    return direction === 'OUTBOUND' ? 'INBOUND' : 'OUTBOUND';
  }

  connectionAttemptCount(leftDeviceId: string, rightDeviceId: string): number {
    return this.connectionAttempts.get(this.edgeOf(leftDeviceId, rightDeviceId)) ?? 0;
  }

  duplicateNextFrame(deviceId: string): void { this.tls.duplicateNext(deviceId); }
  delayNextFrame(deviceId: string, delayMs: number): void { this.tls.delayNext(deviceId, delayMs); }
  readyPeersOf(deviceId: string): string[] { return Array.from(this.nodes.get(deviceId)?.connected ?? []).sort(); }
  readyDeviceIds(): string[] { return this.readyPeersOf('device-a'); }
  dskPayloadTypes(): string[] { return this.dsk.payloadTypes(); }
  tlsPayloadTypes(): string[] { return this.tls.payloadTypes(); }
  pendingResourceCount(): number { return 0; }
  lastAggregate(): AggregatedEvidenceResult {
    return this.nodes.get(this.lastRunDeviceId)?.aggregate.result() ?? { evidence: [], conflicts: [] };
  }

  private candidatesOf(deviceId: string): CoordinatorCandidate[] {
    const node: FixtureNode | undefined = this.nodes.get(deviceId);
    if (node === undefined) return [];
    const candidates: CoordinatorCandidate[] = [{
      deviceId: deviceId, isLocal: true, routeScore: 1, ready: this.available.has(deviceId)
    }];
    for (const peerId of Array.from(node.connected).sort()) {
      candidates.push({ deviceId: peerId, isLocal: false, routeScore: 1, ready: this.available.has(peerId) });
    }
    return candidates;
  }

  private edgeOf(leftDeviceId: string, rightDeviceId: string): string {
    return leftDeviceId < rightDeviceId ? leftDeviceId + '->' + rightDeviceId : rightDeviceId + '->' + leftDeviceId;
  }
}
