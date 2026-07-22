import { describe, expect, it } from '@ohos/hypium';
import { AppRuntime } from '../main/ets/runtime/AppRuntime';
import { Transport, TransportListener } from '../main/ets/communication/Transport';
import { PeerDevice } from '../main/ets/model/AppModels';
import { KnowledgeError } from '../main/ets/contracts/knowledge/KnowledgeError';
import { KnowledgeProfile } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { SemanticKnowledgeProvider } from '../main/ets/contracts/semantic/SemanticKnowledgeProvider';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import { AvailableDeviceProvider, TrustedDeviceResolver } from '../main/ets/communication/TrustedDeviceResolver';

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
        relevance: 1, coveredConcepts: [], estimatedCoverageGain: 1, byteCost: 100,
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
      runtime.destroy();
    });
  });
}
