import { describe, expect, it } from '@ohos/hypium';
import { AppRuntime } from '../main/ets/runtime/AppRuntime';
import { Transport, TransportListener } from '../main/ets/communication/Transport';
import { PeerDevice } from '../main/ets/model/AppModels';
import { KnowledgeError } from '../main/ets/contracts/knowledge/KnowledgeError';
import { KnowledgeProfile } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { SemanticKnowledgeProvider } from '../main/ets/contracts/semantic/SemanticKnowledgeProvider';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import { AvailableDeviceProvider, TrustedDeviceResolver } from '../main/ets/communication/TrustedDeviceResolver';
import { PeerMeshController } from '../main/ets/communication/PeerMeshOrchestrator';
import { CoordinatorTransport } from '../main/ets/communication/MultiDeviceTaskCoordinator';

class CountingTransport implements Transport {
  listener: TransportListener | null = null;
  destroyCalls: number = 0;

  setListener(listener: TransportListener): void { this.listener = listener; }
  connect(_peer: PeerDevice): Promise<void> { return Promise.resolve(); }
  accept(_wantParam: Record<string, Object>): boolean { return true; }
  send(_text: string): Promise<void> { return Promise.resolve(); }
  disconnect(): Promise<void> { return Promise.resolve(); }
  destroy(): void { this.destroyCalls += 1; }
  isConnected(): boolean { return false; }

  getPeerDevice(): PeerDevice | null {
    return null;
  }
}

interface FakeApplicationInfo {
  name: string;
}

interface FakeContext {
  applicationInfo: FakeApplicationInfo;
}

function fakeContext(): FakeContext {
  return { applicationInfo: { name: 'com.example.semalink' } };
}

class FakeSemanticProvider implements SemanticKnowledgeProvider {
  calls: number = 0;
  evidence: EvidenceUnit[] = [];

  async getProfile(): Promise<KnowledgeProfile> {
    this.calls += 1;
    return {
      contractVersion: '1.0', profileVersion: 'fake-profile', indexState: 'EMPTY', knowledgeDomains: [],
      documentCount: 0, chunkCount: 0, modalities: [], retrievalModes: ['keyword'],
      supportedLevels: ['L1', 'L2'], indexVersion: 'fake-index', embeddingModelVersion: '', updatedAt: 1
    };
  }

  async searchEvidence(task: TaskRequest): Promise<EvidenceUnit[]> {
    this.calls += 1;
    return this.evidence;
  }
}

class EmptyDeviceProvider implements AvailableDeviceProvider {
  async list(): Promise<Array<PeerDevice>> { return []; }
  release(): void {}
}

class ListingDeviceProvider implements AvailableDeviceProvider {
  calls: number = 0;
  released: number = 0;
  private readonly devices: Array<PeerDevice>;

  constructor(devices: Array<PeerDevice>) {
    this.devices = devices;
  }

  async list(): Promise<Array<PeerDevice>> {
    this.calls += 1;
    return this.devices;
  }

  release(): void {
    this.released += 1;
  }
}

class FakePeerMeshController implements PeerMeshController {
  startCalls: number = 0;
  reconcileCalls: number = 0;
  destroyCalls: number = 0;
  ensureReadyBudgets: number[] = [];
  peers: PeerDevice[] = [];
  readyIds: string[] = [];

  async start(): Promise<void> { this.startCalls += 1; }
  async reconcile(): Promise<void> { this.reconcileCalls += 1; }
  async ensureReady(waitBudgetMs: number): Promise<string[]> {
    this.ensureReadyBudgets.push(waitBudgetMs);
    return this.readyIds.slice();
  }
  knownPeers(): PeerDevice[] { return this.peers.slice(); }
  destroy(): void { this.destroyCalls += 1; }
}

class FakeCoordinatorTransport implements CoordinatorTransport {
  sentDeviceIds: string[] = [];
  searchedDeviceIds: string[] = [];
  evidence: EvidenceUnit[] = [];

  async send(deviceId: string, _envelope: Object): Promise<void> {
    this.sentDeviceIds.push(deviceId);
  }

  async search(deviceId: string, _task: TaskRequest, _round: 1 | 2): Promise<EvidenceUnit[]> {
    this.searchedDeviceIds.push(deviceId);
    return deviceId === 'local' ? this.evidence : [];
  }
}

async function capturedKnowledgeError(action: () => Promise<void>): Promise<KnowledgeError | undefined> {
  try {
    await action();
  } catch (error) {
    if (error instanceof KnowledgeError) {
      return error;
    }
  }
  return undefined;
}

export default function appRuntimeTest(): void {
  describe('AppRuntime', () => {
    it('initializesTheSingletonOnlyOnce', 0, () => {
      AppRuntime.reset();
      const first: AppRuntime = AppRuntime.initialize(fakeContext() as never);
      const second: AppRuntime = AppRuntime.initialize(fakeContext() as never);
      expect(first).assertEqual(second);
      AppRuntime.reset();
    });

    it('acceptsCollaborationAsResponder', 0, () => {
      const transport = new CountingTransport();
      const runtime = new AppRuntime(fakeContext() as never, { transport: transport });
      expect(runtime.coordinator.acceptCollaboration({})).assertTrue();
      expect(runtime.store.snapshot().role).assertEqual('RESPONDER');
      runtime.destroy();
    });

    it('destroysOnlyOnce', 0, () => {
      const transport = new CountingTransport();
      const runtime = new AppRuntime(fakeContext() as never, { transport: transport });
      runtime.destroy();
      runtime.destroy();
      expect(transport.destroyCalls).assertEqual(1);
    });

    it('exposes an injected fake semantic provider without creating real knowledge storage', 0, async () => {
      const fake = new FakeSemanticProvider();
      const runtime = new AppRuntime(fakeContext() as never, {
        transport: new CountingTransport(), knowledgeProvider: fake
      });
      await runtime.initializeKnowledge();
      const profile = await runtime.knowledgeProvider.getProfile();
      expect(profile.profileVersion).assertEqual('fake-profile');
      expect(fake.calls).assertEqual(1);
      expect(runtime.knowledgeGateway === undefined).assertTrue();
      runtime.destroy();
    });

    it('exposes the default knowledge provider and gateway from one application service', 0, () => {
      const runtime = new AppRuntime(fakeContext() as never, { transport: new CountingTransport() });
      expect(runtime.knowledgeGateway as Object).assertEqual(runtime.knowledgeProvider as Object);
      runtime.destroy();
      runtime.destroy();
    });

    it('returns safe not-ready through the default provider before knowledge initialization', 0, async () => {
      const runtime = new AppRuntime(fakeContext() as never, { transport: new CountingTransport() });
      const error = await capturedKnowledgeError(async (): Promise<void> => {
        await runtime.knowledgeProvider.getProfile();
      });
      expect(error?.code).assertEqual('E_INDEX_NOT_READY');
      runtime.destroy();
    });

    it('refreshesAndPublishesAvailableDevices', 0, async () => {
      const provider = new ListingDeviceProvider([
        { deviceId: 'remote-b', deviceName: 'Tablet B', deviceType: 'tablet' },
        { deviceId: 'remote-a', deviceName: 'Phone A', deviceType: 'phone' }
      ]);
      const runtime = new AppRuntime(fakeContext() as never, {
        transport: new CountingTransport(),
        resolverFactory: (): TrustedDeviceResolver => new TrustedDeviceResolver(provider)
      });
      runtime.store.update({ activePeerCount: 3 });

      await runtime.refreshAvailableDevices();

      expect(provider.calls).assertEqual(1);
      expect(provider.released).assertEqual(1);
      expect(runtime.store.snapshot().peerStatuses.length).assertEqual(2);
      expect(runtime.store.snapshot().peerStatuses[0].deviceName).assertEqual('Phone A');
      expect(runtime.store.snapshot().peerStatuses[1].deviceName).assertEqual('Tablet B');
      expect(runtime.store.snapshot().peerStatuses[0].controlState).assertEqual('DISCONNECTED');
      expect(runtime.store.snapshot().peerStatuses[0].dataState).assertEqual('DISCONNECTED');
      expect(runtime.store.snapshot().activePeerCount).assertEqual(0);
      runtime.destroy();
    });

    it('delegatesConnectedRefreshAndLifecycleToPeerMesh', 0, async () => {
      const mesh = new FakePeerMeshController();
      mesh.peers = [
        { deviceId: 'remote-b', deviceName: 'Tablet B', deviceType: 'tablet' },
        { deviceId: 'remote-a', deviceName: 'Phone A', deviceType: 'phone' }
      ];
      const provider = new ListingDeviceProvider([]);
      const runtime = new AppRuntime(fakeContext() as never, {
        transport: new CountingTransport(),
        resolverFactory: (): TrustedDeviceResolver => new TrustedDeviceResolver(provider),
        meshFactory: () => mesh
      });

      await runtime.startPeerMesh();
      expect(mesh.startCalls).assertEqual(1);
      expect(runtime.store.snapshot().peerStatuses.length).assertEqual(2);
      await runtime.refreshPeerMesh();
      await runtime.refreshAvailableDevices(true);

      expect(mesh.reconcileCalls).assertEqual(2);
      expect(provider.calls).assertEqual(0);
      expect(runtime.store.snapshot().peerStatuses[0].deviceName).assertEqual('Phone A');
      expect(runtime.store.snapshot().peerStatuses[1].deviceName).assertEqual('Tablet B');
      runtime.destroy();
      runtime.destroy();
      expect(mesh.destroyCalls).assertEqual(1);
    });

    it('exposes one shared multi-device runtime assembly', 0, () => {
      const runtime = new AppRuntime(fakeContext() as never, { transport: new CountingTransport() });
      expect(runtime.deviceDirectory as Object).assertEqual(runtime.semanticDeviceDirectory as Object);
      expect(runtime.multiDeviceCoordinator as Object).assertEqual(runtime.semanticTaskCoordinator as Object);
      expect(runtime.controlHub as Object).assertEqual(runtime.tls?.dsk as Object);
      expect(runtime.connectionPool as Object).assertEqual(runtime.tls?.pool as Object);
      runtime.destroy();
    });

    it('routes collaboration acceptance through the existing runtime', 0, () => {
      const runtime = new AppRuntime(fakeContext() as never, { transport: new CountingTransport() });
      expect(runtime.acceptCollaboration({})).assertTrue();
      runtime.destroy();
    });

    it('submitsAnAutomaticQueryWithLocalEvidenceWithoutAConnectedPeer', 0, async () => {
      const evidence: EvidenceUnit = {
        semanticContractVersion: '1.0', evidenceId: 'local-evidence', evidenceGroupId: 'local-group',
        sourceDeviceId: 'local', sourceDocId: 'doc-1', level: 'L1', title: 'Local answer',
        summary: 'Actual summary', relevance: 1, coveredConcepts: [], estimatedCoverageGain: 1, byteCost: 100,
        privacyLevel: 'PRIVATE_GROUP', privacyCost: 0, energyCost: 0, hash: 'local-hash', canEscalateTo: ['L2']
      };
      const provider = new FakeSemanticProvider();
      provider.evidence = [evidence];
      const runtime = new AppRuntime(fakeContext() as never, {
        transport: new CountingTransport(), knowledgeProvider: provider,
        resolverFactory: (): TrustedDeviceResolver => new TrustedDeviceResolver(new EmptyDeviceProvider())
      });
      await runtime.submitAutomaticQuery('  local question  ');
      expect(runtime.store.snapshot().automaticQueryProgress).assertEqual('ANSWER_READY');
      expect(runtime.store.snapshot().question).assertEqual('local question');
      expect(runtime.store.snapshot().automaticSourceNames.length).assertEqual(1);
      expect(runtime.store.snapshot().collaborationRecords.length).assertEqual(1);
      expect(runtime.store.snapshot().collaborationRecords[0].sourceDeviceNames[0]).assertEqual('local');
      expect(runtime.store.snapshot().collaborationRecords[0].evidenceCount).assertEqual(1);
      expect(runtime.store.snapshot().automaticResultItems.length).assertEqual(1);
      expect(runtime.store.snapshot().automaticResultItems[0].title).assertEqual('Local answer');
      expect(runtime.store.snapshot().automaticResultItems[0].content).assertEqual('Actual summary');
      expect(runtime.store.snapshot().automaticResultItems[0].sourceName).assertEqual('本机');
      expect(runtime.store.snapshot().totalTaskMs > 0).assertTrue();
      runtime.destroy();
    });

    it('usesOnlyReadyMeshPeersAsAutomaticQuerySources', 0, async () => {
      const evidence: EvidenceUnit = {
        semanticContractVersion: '1.0', evidenceId: 'local-mesh-evidence', evidenceGroupId: 'local-group',
        sourceDeviceId: 'local', sourceDocId: 'doc-1', level: 'L1', title: 'Mesh answer',
        summary: 'Mesh summary', relevance: 1, coveredConcepts: [], estimatedCoverageGain: 1, byteCost: 100,
        privacyLevel: 'PRIVATE_GROUP', privacyCost: 0, energyCost: 0, hash: 'mesh-hash', canEscalateTo: ['L2']
      };
      const knowledge = new FakeSemanticProvider();
      knowledge.evidence = [evidence];
      const taskTransport = new FakeCoordinatorTransport();
      taskTransport.evidence = [evidence];
      const mesh = new FakePeerMeshController();
      mesh.peers = [
        { deviceId: 'remote-a', deviceName: 'Phone A', deviceType: 'phone' },
        { deviceId: 'remote-b', deviceName: 'Tablet B', deviceType: 'tablet' }
      ];
      mesh.readyIds = ['remote-a'];
      const legacyProvider = new ListingDeviceProvider([
        { deviceId: 'legacy-peer', deviceName: 'Legacy', deviceType: 'phone' }
      ]);
      const runtime = new AppRuntime(fakeContext() as never, {
        transport: new CountingTransport(), knowledgeProvider: knowledge,
        resolverFactory: (): TrustedDeviceResolver => new TrustedDeviceResolver(legacyProvider),
        meshFactory: () => mesh,
        coordinatorTransport: taskTransport
      });

      await runtime.submitAutomaticQuery('mesh query');

      expect(mesh.ensureReadyBudgets).assertDeepEquals([3000]);
      expect(legacyProvider.calls).assertEqual(0);
      expect(taskTransport.sentDeviceIds).assertDeepEquals(['remote-a']);
      expect(taskTransport.searchedDeviceIds.indexOf('local') >= 0).assertTrue();
      expect(taskTransport.searchedDeviceIds.indexOf('remote-a') >= 0).assertTrue();
      expect(taskTransport.searchedDeviceIds.indexOf('remote-b')).assertEqual(-1);
      expect(runtime.store.snapshot().automaticSourceNames).assertDeepEquals(['local', 'Phone A']);
      expect(runtime.store.snapshot().automaticExcludedSourceNames).assertDeepEquals(['Tablet B']);
      runtime.destroy();
    });
  });
}
