import { describe, expect, it } from '@ohos/hypium';
import { ProtocolSession } from '../main/ets/communication/SessionManager';
import { DeviceDirectory } from '../main/ets/communication/DeviceDirectory';
import { DeviceSemanticRouter } from '../main/ets/communication/DeviceSemanticRouter';
import { EvidenceUtilityScheduler } from '../main/ets/communication/EvidenceUtilityScheduler';
import { TaskSufficiencyEvaluator } from '../main/ets/communication/TaskSufficiencyEvaluator';
import { SemanticKnowledgeProvider } from '../main/ets/contracts/semantic/SemanticKnowledgeProvider';
import {
  DeviceProfileAdvertisement,
  EvidenceUnit,
  TaskRequest,
  TaskSufficiencyResult
} from '../main/ets/contracts/semantic/SemanticModels';
import { KnowledgeProfile } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { AppStateStore } from '../main/ets/state/AppStateStore';
import { AppError, P4_ERROR_CODES, calculatePercentile } from '../main/ets/common/AppError';
import { AppSnapshot, INITIAL_SNAPSHOT } from '../main/ets/model/AppModels';
import { ProgressiveQueryCoordinator } from '../main/ets/communication/ProgressiveQueryCoordinator';
import { ProtocolCodec } from '../main/ets/protocol/ProtocolCodec';
import {
  EVIDENCE_PAGING_VERSION,
  ErrorPayload,
  EvidencePayload,
  MAX_MESSAGE_BYTES,
  MessageType,
  ProtocolEnvelope,
  TaskPayload,
  TsfPayload
} from '../main/ets/protocol/ProtocolModels';
import { utf8ByteLength } from '../main/ets/knowledge/payload/Utf8Sizer';
import { FakeSemanticKnowledgeProvider } from './support/FakeSemanticKnowledgeProvider';
import { FakeScheduler } from './support/FakeScheduler';
import {
  SEMANTIC_COMMUNICATION_CASES,
  SemanticCommunicationCase
} from './support/SemanticFixtures';

function task(taskId: string = 'local-task', byteBudget: number = 1000,
  privacyLevel: 'LOCAL_ONLY' | 'PRIVATE_GROUP' = 'LOCAL_ONLY'): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: taskId, queryText: 'alpha beta',
    requiredConcepts: ['alpha', 'beta'], requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: byteBudget, privacyLevel: privacyLevel,
    acceptableLevels: ['L1', 'L2']
  };
}

function evidence(id: string, level: 'L1' | 'L2', concepts: string[], bytes: number): EvidenceUnit {
  return {
    semanticContractVersion: '1.0', evidenceId: id, evidenceGroupId: id,
    sourceDeviceId: 'local-device', sourceDocId: 'doc-' + id, level: level, title: id,
    relevance: 1, coveredConcepts: concepts, estimatedCoverageGain: concepts.length / 2,
    byteCost: bytes, privacyLevel: 'LOCAL_ONLY', privacyCost: 1, energyCost: level === 'L1' ? 0.05 : 0.1,
    hash: 'hash-' + id, canEscalateTo: level === 'L1' ? ['L2'] : []
  };
}

function evidenceWithSummary(id: string, concepts: string[], summaryLength: number): EvidenceUnit {
  const unit: EvidenceUnit = evidence(id, 'L1', concepts, 100);
  unit.summary = 'x'.repeat(summaryLength);
  unit.privacyLevel = 'PRIVATE_GROUP';
  unit.privacyCost = 0.2;
  return unit;
}

function nextTurn(): Promise<void> {
  return new Promise<void>((resolve: () => void) => setTimeout(resolve, 0));
}

class FakeSemanticProvider implements SemanticKnowledgeProvider {
  readonly profile: KnowledgeProfile = {
    contractVersion: '1.0', profileVersion: 'profile-1', indexState: 'READY',
    knowledgeDomains: [{ tag: 'alpha', weight: 1, documentCount: 1 }], documentCount: 1,
    chunkCount: 2, modalities: ['text'], retrievalModes: ['keyword'], supportedLevels: ['L1', 'L2'],
    indexVersion: 'index-1', embeddingModelVersion: '', updatedAt: 1000
  };
  candidates: EvidenceUnit[] = [];
  searchCalls: number = 0;

  getProfile(): Promise<KnowledgeProfile> {
    return Promise.resolve(this.profile);
  }

  searchEvidence(_task: TaskRequest): Promise<EvidenceUnit[]> {
    this.searchCalls += 1;
    return Promise.resolve(this.candidates);
  }
}

class FakeSemanticSession implements ProtocolSession {
  sent: ProtocolEnvelope[] = [];

  sendEnvelope(envelope: ProtocolEnvelope): Promise<void> {
    this.sent.push(envelope);
    return Promise.resolve();
  }
}

function coordinator(provider: FakeSemanticProvider, store: AppStateStore): ProgressiveQueryCoordinator {
  return new ProgressiveQueryCoordinator(
    new FakeSemanticSession(), store, provider, new DeviceDirectory(() => 1000),
    new DeviceSemanticRouter(), new EvidenceUtilityScheduler(), new TaskSufficiencyEvaluator(), () => 1000
  );
}

function remoteProfile(): DeviceProfileAdvertisement {
  return {
    semanticContractVersion: '1.0', deviceId: 'remote-device', deviceAlias: 'remote-device',
    profileVersion: 'remote-profile-1', indexVersion: 'remote-index-1', indexState: 'READY',
    knowledgeDomains: ['alpha', 'beta'], modalities: ['text'], retrievalModes: ['keyword'],
    supportedLevels: ['L1', 'L2'], advertisedAtMs: 1000, ttlMs: 300000
  };
}

export default function progressiveQueryCoordinatorTest(): void {
  describe('ProgressiveQueryCoordinator', () => {
    it('runs local L1 NEED_MORE then L2 ENOUGH', 0, async () => {
      const provider: FakeSemanticProvider = new FakeSemanticProvider();
      provider.candidates = [evidence('l1-alpha', 'L1', ['alpha'], 100), evidence('l2-beta', 'L2', ['beta'], 100)];
      const store: AppStateStore = new AppStateStore();
      const result = await coordinator(provider, store).submit(task());

      expect(result.feedback).assertEqual('ENOUGH');
      expect(store.snapshot().taskPhase).assertEqual('SUFFICIENT');
      expect(store.snapshot().taskRound).assertEqual(2);
      expect(provider.searchCalls).assertEqual(1);
    });

    it('finishes after an L1 result without requesting L2', 0, async () => {
      const provider: FakeSemanticProvider = new FakeSemanticProvider();
      provider.candidates = [evidence('l1-all', 'L1', ['alpha', 'beta'], 100), evidence('l2-unused', 'L2', ['beta'], 100)];
      const store: AppStateStore = new AppStateStore();
      const result = await coordinator(provider, store).submit(task());

      expect(result.feedback).assertEqual('ENOUGH');
      expect(store.snapshot().taskRound).assertEqual(1);
    });

    it('aborts after a second insufficient round', 0, async () => {
      const provider: FakeSemanticProvider = new FakeSemanticProvider();
      provider.candidates = [evidence('l1-alpha', 'L1', ['alpha'], 100), evidence('l2-alpha', 'L2', ['alpha'], 100)];
      const store: AppStateStore = new AppStateStore();
      const result = await coordinator(provider, store).submit(task());

      expect(result.feedback).assertEqual('ABORT');
      expect(store.snapshot().taskPhase).assertEqual('ABORTED');
    });

    it('reports insufficient bytes without selecting evidence', 0, async () => {
      const provider: FakeSemanticProvider = new FakeSemanticProvider();
      provider.candidates = [evidence('l1-alpha', 'L1', ['alpha'], 200), evidence('l1-beta', 'L1', ['beta'], 200)];
      const store: AppStateStore = new AppStateStore();
      const result = await coordinator(provider, store).submit(task('budget-task', 100));

      expect(result.feedback).assertEqual('ABORT');
      expect(store.snapshot().evidenceBytes).assertEqual(0);
    });

    it('rejects a duplicate task while the first task is active', 0, async () => {
      const provider: FakeSemanticProvider = new FakeSemanticProvider();
      provider.candidates = [evidence('l1-all', 'L1', ['alpha', 'beta'], 100)];
      const store: AppStateStore = new AppStateStore();
      const loop: ProgressiveQueryCoordinator = coordinator(provider, store);
      const first: Promise<TaskSufficiencyResult> = loop.submit(task('busy-task'));
      let errorCode: string = '';
      try {
        await loop.submit(task('busy-task'));
      } catch (error) {
        errorCode = (error as AppError).code;
      }
      await first;
      expect(errorCode).assertEqual('E_BUSY');
    });

    it('completes a remote L1 NEED_MORE L2 exchange and ignores duplicate evidence', 0, async () => {
      const provider: FakeSemanticProvider = new FakeSemanticProvider();
      provider.candidates = [evidence('remote-l1', 'L1', ['alpha'], 100), evidence('remote-l2', 'L2', ['beta'], 100)];
      const store: AppStateStore = new AppStateStore();
      const session: FakeSemanticSession = new FakeSemanticSession();
      const directory: DeviceDirectory = new DeviceDirectory(() => 1000);
      const loop: ProgressiveQueryCoordinator = new ProgressiveQueryCoordinator(
        session, store, provider, directory, new DeviceSemanticRouter(),
        new EvidenceUtilityScheduler(), new TaskSufficiencyEvaluator(), () => 1000
      );
      const codec: ProtocolCodec = new ProtocolCodec();
      loop.onProtocolEnvelope(codec.createProfile('profile-1', 'remote-session', 'profile', 1000,
        { profile: remoteProfile() }));
      const pending: Promise<TaskSufficiencyResult> = loop.submit(task('remote-task', 1000, 'PRIVATE_GROUP'));
      await nextTurn();
      expect(session.sent[0].type).assertEqual('TASK');
      const taskEnvelope: ProtocolEnvelope = session.sent[0];
      loop.onProtocolEnvelope(codec.createTaskAck('ack-1', 'remote-session', 'remote-task', 1001,
        { taskId: 'remote-task', round: 1, acceptedAt: 1001, candidateCount: 2 }));
      const l1: ProtocolEnvelope = codec.createEvidence('evidence-1', 'remote-session', 'remote-task', 1002,
        { taskId: 'remote-task', round: 1, evidence: [provider.candidates[0]] });
      loop.onProtocolEnvelope(l1);
      loop.onProtocolEnvelope(l1);
      await nextTurn();
      expect(session.sent.length).assertEqual(2);
      expect(session.sent[1].type).assertEqual('TSF');
      const tsfPayload: TsfPayload = session.sent[1].payload as TsfPayload;
      expect(tsfPayload.round).assertEqual(1);
      loop.onProtocolEnvelope(codec.createCancel('unrelated-cancel', 'remote-session', 'other-task', 1002,
        { taskId: 'other-task', code: 'E_CANCELLED', reason: 'other task cancelled' }));
      loop.onProtocolEnvelope(codec.createEvidence('evidence-2', taskEnvelope.sessionId, 'remote-task', 1003,
        { taskId: 'remote-task', round: 2, evidence: [provider.candidates[1]] }));
      const result: TaskSufficiencyResult = await pending;
      expect(result.feedback).assertEqual('ENOUGH');
      expect(store.snapshot().selectedDeviceId).assertEqual('remote-device');
      expect(store.snapshot().taskRound).assertEqual(2);
    });

    it('advertises paging and evaluates remote evidence only after every page arrives', 0, async () => {
      const provider: FakeSemanticProvider = new FakeSemanticProvider();
      provider.candidates = [evidence('page-alpha', 'L1', ['alpha'], 100),
        evidence('page-beta', 'L1', ['beta'], 100)];
      const store: AppStateStore = new AppStateStore();
      const session: FakeSemanticSession = new FakeSemanticSession();
      const directory: DeviceDirectory = new DeviceDirectory(() => 1000);
      const loop: ProgressiveQueryCoordinator = new ProgressiveQueryCoordinator(
        session, store, provider, directory, new DeviceSemanticRouter(),
        new EvidenceUtilityScheduler(), new TaskSufficiencyEvaluator(), () => 1000
      );
      const codec: ProtocolCodec = new ProtocolCodec();
      loop.onProtocolEnvelope(codec.createProfile('profile-page', 'remote-session', 'profile', 1000,
        { profile: remoteProfile() }));
      const pending: Promise<TaskSufficiencyResult> = loop.submit(task('paged-task', 1000, 'PRIVATE_GROUP'));
      await nextTurn();

      const sentTask: TaskPayload = session.sent[0].payload as TaskPayload;
      expect(sentTask.evidencePagingVersion).assertEqual(EVIDENCE_PAGING_VERSION);
      loop.onProtocolEnvelope(codec.createEvidence('page-1', 'remote-session', 'paged-task', 1001,
        { taskId: 'paged-task', round: 1, pageIndex: 1, pageCount: 2,
          evidence: [provider.candidates[1]] }));
      await nextTurn();
      expect(session.sent.length).assertEqual(1);

      loop.onProtocolEnvelope(codec.createEvidence('page-1-retry', 'remote-session', 'paged-task', 1002,
        { taskId: 'paged-task', round: 1, pageIndex: 1, pageCount: 2,
          evidence: [provider.candidates[1]] }));
      loop.onProtocolEnvelope(codec.createEvidence('page-0', 'remote-session', 'paged-task', 1003,
        { taskId: 'paged-task', round: 1, pageIndex: 0, pageCount: 2,
          evidence: [provider.candidates[0]] }));
      const result: TaskSufficiencyResult = await pending;
      expect(result.feedback).assertEqual('ENOUGH');
      expect(session.sent.length).assertEqual(2);
      expect(session.sent[1].type).assertEqual(MessageType.TSF);

      loop.onProtocolEnvelope(codec.createEvidence('page-0-late', 'remote-session', 'paged-task', 1004,
        { taskId: 'paged-task', round: 1, pageIndex: 0, pageCount: 2,
          evidence: [provider.candidates[0]] }));
      await nextTurn();
      expect(session.sent.length).assertEqual(2);
    });

    it('sends negotiated evidence as ordered messages below the DSK limit', 0, async () => {
      const provider: FakeSemanticProvider = new FakeSemanticProvider();
      provider.candidates = [evidenceWithSummary('large-one', ['alpha'], 100),
        evidenceWithSummary('large-two', ['beta'], 100),
        evidenceWithSummary('large-three', ['gamma'], 100)];
      const store: AppStateStore = new AppStateStore();
      const session: FakeSemanticSession = new FakeSemanticSession();
      const loop: ProgressiveQueryCoordinator = new ProgressiveQueryCoordinator(
        session, store, provider, new DeviceDirectory(() => 1000), new DeviceSemanticRouter(),
        new EvidenceUtilityScheduler(), new TaskSufficiencyEvaluator(), () => 1000
      );
      const codec: ProtocolCodec = new ProtocolCodec();
      const incomingTask: TaskRequest = task('responder-pages', 1000, 'PRIVATE_GROUP');
      loop.onProtocolEnvelope(codec.createTask('incoming-task', 'remote-session', 'responder-pages', 1000,
        { task: incomingTask, round: 1, evidencePagingVersion: EVIDENCE_PAGING_VERSION }));
      await nextTurn();

      expect(session.sent[0].type).assertEqual(MessageType.TASK_ACK);
      let evidencePageCount: number = 0;
      for (let i = 1; i < session.sent.length; i++) {
        if (session.sent[i].type === MessageType.EVIDENCE) {
          const payload: EvidencePayload = session.sent[i].payload as EvidencePayload;
          expect(payload.pageIndex).assertEqual(evidencePageCount);
          expect(utf8ByteLength(codec.encode(session.sent[i])) <= MAX_MESSAGE_BYTES).assertTrue();
          evidencePageCount++;
        }
      }
      expect(evidencePageCount).assertEqual(3);
      for (let i = 1; i < session.sent.length; i++) {
        const payload: EvidencePayload = session.sent[i].payload as EvidencePayload;
        expect(payload.pageCount).assertEqual(evidencePageCount);
      }
    });

    it('keeps a legacy task response in one evidence message', 0, async () => {
      const provider: FakeSemanticProvider = new FakeSemanticProvider();
      provider.candidates = [evidence('legacy-alpha', 'L1', ['alpha'], 100),
        evidence('legacy-beta', 'L1', ['beta'], 100)];
      const session: FakeSemanticSession = new FakeSemanticSession();
      const loop: ProgressiveQueryCoordinator = new ProgressiveQueryCoordinator(
        session, new AppStateStore(), provider, new DeviceDirectory(() => 1000),
        new DeviceSemanticRouter(), new EvidenceUtilityScheduler(), new TaskSufficiencyEvaluator(), () => 1000
      );
      const codec: ProtocolCodec = new ProtocolCodec();
      const incomingTask: TaskRequest = task('legacy-response');
      loop.onProtocolEnvelope(codec.createTask('legacy-task', 'remote-session', 'legacy-response', 1000,
        { task: incomingTask, round: 1 }));
      await nextTurn();

      expect(session.sent.length).assertEqual(2);
      expect(session.sent[1].type).assertEqual(MessageType.EVIDENCE);
      const payload: EvidencePayload = session.sent[1].payload as EvidencePayload;
      expect(payload.pageIndex).assertEqual(0);
      expect(payload.pageCount).assertEqual(1);
      expect(payload.evidence.length).assertEqual(2);
    });

    it('returns a protocol error when one evidence unit cannot fit a page', 0, async () => {
      const provider: FakeSemanticProvider = new FakeSemanticProvider();
      provider.candidates = [evidenceWithSummary('oversized-unit', ['alpha'], MAX_MESSAGE_BYTES + 100)];
      const session: FakeSemanticSession = new FakeSemanticSession();
      const loop: ProgressiveQueryCoordinator = new ProgressiveQueryCoordinator(
        session, new AppStateStore(), provider, new DeviceDirectory(() => 1000),
        new DeviceSemanticRouter(), new EvidenceUtilityScheduler(), new TaskSufficiencyEvaluator(), () => 1000
      );
      const codec: ProtocolCodec = new ProtocolCodec();
      const incomingTask: TaskRequest = task('oversized-response', 1000, 'PRIVATE_GROUP');
      loop.onProtocolEnvelope(codec.createTask('oversized-task', 'remote-session', 'oversized-response', 1000,
        { task: incomingTask, round: 1, evidencePagingVersion: EVIDENCE_PAGING_VERSION }));
      await nextTurn();

      expect(session.sent.length).assertEqual(2);
      expect(session.sent[0].type).assertEqual(MessageType.TASK_ACK);
      expect(session.sent[1].type).assertEqual(MessageType.ERROR);
      const payload: ErrorPayload = session.sent[1].payload as ErrorPayload;
      expect(payload.code).assertEqual('E_EVIDENCE_TOO_LARGE');
    });

    it('fails a remote task when evidence pages disagree on page count', 0, async () => {
      const provider: FakeSemanticProvider = new FakeSemanticProvider();
      provider.candidates = [evidence('conflict-alpha', 'L1', ['alpha'], 100),
        evidence('conflict-beta', 'L1', ['beta'], 100)];
      const store: AppStateStore = new AppStateStore();
      const session: FakeSemanticSession = new FakeSemanticSession();
      const directory: DeviceDirectory = new DeviceDirectory(() => 1000);
      const loop: ProgressiveQueryCoordinator = new ProgressiveQueryCoordinator(
        session, store, provider, directory, new DeviceSemanticRouter(),
        new EvidenceUtilityScheduler(), new TaskSufficiencyEvaluator(), () => 1000
      );
      const codec: ProtocolCodec = new ProtocolCodec();
      loop.onProtocolEnvelope(codec.createProfile('profile-conflict', 'remote-session', 'profile', 1000,
        { profile: remoteProfile() }));
      const pending: Promise<TaskSufficiencyResult> = loop.submit(task('conflict-task', 1000, 'PRIVATE_GROUP'));
      await nextTurn();
      loop.onProtocolEnvelope(codec.createEvidence('conflict-page-0', 'remote-session', 'conflict-task', 1001,
        { taskId: 'conflict-task', round: 1, pageIndex: 0, pageCount: 2,
          evidence: [provider.candidates[0]] }));
      loop.onProtocolEnvelope(codec.createEvidence('conflict-page-1', 'remote-session', 'conflict-task', 1002,
        { taskId: 'conflict-task', round: 1, pageIndex: 1, pageCount: 3,
          evidence: [provider.candidates[1]] }));

      let code: string = '';
      try {
        await pending;
      } catch (error) {
        code = (error as AppError).code;
      }
      expect(code).assertEqual('E_SEMANTIC_PROTOCOL_INVALID');
      expect(store.snapshot().taskPhase).assertEqual('FAILED');
    });

    it('times out a missing page and releases the task for a retry', 0, async () => {
      const provider: FakeSemanticProvider = new FakeSemanticProvider();
      provider.candidates = [evidence('timeout-alpha', 'L1', ['alpha'], 100),
        evidence('timeout-beta', 'L1', ['beta'], 100)];
      const store: AppStateStore = new AppStateStore();
      const session: FakeSemanticSession = new FakeSemanticSession();
      const directory: DeviceDirectory = new DeviceDirectory(() => 1000);
      const timerScheduler: FakeScheduler = new FakeScheduler();
      const loop: ProgressiveQueryCoordinator = new ProgressiveQueryCoordinator(
        session, store, provider, directory, new DeviceSemanticRouter(),
        new EvidenceUtilityScheduler(), new TaskSufficiencyEvaluator(), () => 1000, timerScheduler
      );
      const codec: ProtocolCodec = new ProtocolCodec();
      loop.onProtocolEnvelope(codec.createProfile('profile-timeout', 'remote-session', 'profile', 1000,
        { profile: remoteProfile() }));
      const pending: Promise<TaskSufficiencyResult> = loop.submit(task('timeout-task', 1000, 'PRIVATE_GROUP'));
      await nextTurn();
      loop.onProtocolEnvelope(codec.createEvidence('timeout-page-0', 'remote-session', 'timeout-task', 1001,
        { taskId: 'timeout-task', round: 1, pageIndex: 0, pageCount: 2,
          evidence: [provider.candidates[0]] }));
      timerScheduler.advanceBy(1000);

      let code: string = '';
      try {
        await pending;
      } catch (error) {
        code = (error as AppError).code;
      }
      expect(code).assertEqual('E_EVIDENCE_PAGE_TIMEOUT');
      expect(store.snapshot().taskPhase).assertEqual('FAILED');
      expect(timerScheduler.pendingCount()).assertEqual(0);

      const retry: Promise<TaskSufficiencyResult> = loop.submit(task('timeout-retry', 1000, 'PRIVATE_GROUP'));
      await nextTurn();
      loop.onProtocolEnvelope(codec.createError('retry-error', 'remote-session', 'timeout-retry', 1002,
        { code: 'E_RETRY_STOP', message: 'retry stopped' }));
      try {
        await retry;
      } catch (_error) {
      }
      expect(timerScheduler.pendingCount()).assertEqual(0);
    });

    it('ignores stale remote evidence and surfaces a matching remote error', 0, async () => {
      const provider: FakeSemanticProvider = new FakeSemanticProvider();
      provider.candidates = [evidence('remote-l1', 'L1', ['alpha'], 100)];
      const store: AppStateStore = new AppStateStore();
      const session: FakeSemanticSession = new FakeSemanticSession();
      const directory: DeviceDirectory = new DeviceDirectory(() => 1000);
      const loop: ProgressiveQueryCoordinator = new ProgressiveQueryCoordinator(
        session, store, provider, directory, new DeviceSemanticRouter(),
        new EvidenceUtilityScheduler(), new TaskSufficiencyEvaluator(), () => 1000
      );
      const codec: ProtocolCodec = new ProtocolCodec();
      loop.onProtocolEnvelope(codec.createProfile('profile-2', 'remote-session', 'profile', 1000,
        { profile: remoteProfile() }));
      const pending: Promise<TaskSufficiencyResult> = loop.submit(task('remote-error', 1000, 'PRIVATE_GROUP'));
      await nextTurn();
      loop.onProtocolEnvelope(codec.createEvidence('stale', 'remote-session', 'old-task', 1001,
        { taskId: 'old-task', round: 1, evidence: [provider.candidates[0]] }));
      loop.onProtocolEnvelope(codec.createError('error-1', 'remote-session', 'remote-error', 1002,
        { code: 'E_REMOTE_FAILURE', message: 'remote failed' }));
      let code: string = '';
      try { await pending; } catch (error) { code = (error as AppError).code; }
      expect(code).assertEqual('E_REMOTE_FAILURE');
      expect(store.snapshot().taskPhase).assertEqual('FAILED');
    });

    it('defines eight local, eight remote, and four cross-device deterministic cases', 0, () => {
      expect(SEMANTIC_COMMUNICATION_CASES.length).assertEqual(20);
      let localCount = 0;
      let remoteCount = 0;
      let eitherCount = 0;
      let l1Sufficient = 0;
      let l2Insufficient = 0;
      for (const fixture of SEMANTIC_COMMUNICATION_CASES) {
        if (fixture.expectedDevice === 'LOCAL') {
          localCount++;
        } else if (fixture.expectedDevice === 'REMOTE') {
          remoteCount++;
        } else {
          eitherCount++;
        }
        if (fixture.expectedTerminalState === 'L1_SUFFICIENT') {
          l1Sufficient++;
        }
        if (fixture.expectedTerminalState === 'L2_INSUFFICIENT') {
          l2Insufficient++;
        }
      }
      expect(localCount).assertEqual(8);
      expect(remoteCount).assertEqual(8);
      expect(eitherCount).assertEqual(4);
      expect(l1Sufficient).assertEqual(2);
      expect(l2Insufficient).assertEqual(2);
    });

    it('returns deterministic evidence for all twenty fixed queries', 0, async () => {
      const localProvider = new FakeSemanticKnowledgeProvider('local-device');
      const remoteProvider = new FakeSemanticKnowledgeProvider('remote-device');
      for (const fixture of SEMANTIC_COMMUNICATION_CASES) {
        const provider = fixture.expectedDevice === 'REMOTE' ? remoteProvider : localProvider;
        const first = await provider.searchEvidence(fixture.task);
        const second = await provider.searchEvidence(fixture.task);

        expect(JSON.stringify(first)).assertEqual(JSON.stringify(second));
        expect(first.length).assertEqual(fixture.expectedTerminalState === 'L1_SUFFICIENT' ||
          fixture.expectedTerminalState === 'L2_INSUFFICIENT' ||
          fixture.expectedTerminalState === 'L2_SUFFICIENT' ? 1 : 0);
        for (const unit of first) {
          expect(unit.sourceDeviceId).assertEqual(provider.deviceId);
          expect(unit.byteCost).assertEqual(utf8ByteLength(JSON.stringify(unit)));
          expect(unit.byteCost > 0).assertTrue();
          expect(unit.sourceDocId).assertEqual('doc-' + fixture.expectedDomain);
          expect(unit.level).assertEqual(fixture.expectedTerminalState === 'L1_SUFFICIENT' ? 'L1' : 'L2');
        }
      }
      expect(localProvider.searchCallCount).assertEqual(24);
      expect(remoteProvider.searchCallCount).assertEqual(16);
    });

    it('provides fixed L1 sufficient and L2 insufficient terminal fixtures', 0, async () => {
      const provider = new FakeSemanticKnowledgeProvider('local-device');
      const l1Case: SemanticCommunicationCase = SEMANTIC_COMMUNICATION_CASES[0];
      const l2Case: SemanticCommunicationCase = SEMANTIC_COMMUNICATION_CASES[1];
      const l1 = await provider.searchEvidence(l1Case.task);
      const l2 = await provider.searchEvidence(l2Case.task);

      expect(l1.length).assertEqual(1);
      expect(l1[0].level).assertEqual('L1');
      expect(l1[0].coveredConcepts.length).assertEqual(l1Case.task.requiredConcepts.length);
      expect(l2.length).assertEqual(1);
      expect(l2[0].level).assertEqual('L2');
      expect(l2[0].coveredConcepts.length).assertEqual(1);
    });

    it('records P4 metrics and calculates percentile latency from raw samples', 0, () => {
      const store: AppStateStore = new AppStateStore();
      store.update({ taskId: 'metrics-task', taskRound: 2, taskFeedback: 'ENOUGH',
        taskCoverage: 0.9, taskConfidence: 0.86, taskPrivacyLevel: 'PRIVATE_GROUP',
        firstResultLatencyMs: 120, completionLatencyMs: 260, latencySamplesMs: [120, 180, 260],
        protocolBytes: 900, evidenceBytes: 320 });
      const snapshot: AppSnapshot = store.snapshot();
      expect(snapshot.taskPrivacyLevel).assertEqual('PRIVATE_GROUP');
      expect(snapshot.protocolBytes).assertEqual(900);
      expect(snapshot.evidenceBytes).assertEqual(320);
      expect(calculatePercentile(snapshot.latencySamplesMs, 0.5)).assertEqual(180);
      expect(calculatePercentile(snapshot.latencySamplesMs, 0.95)).assertEqual(260);
      expect(INITIAL_SNAPSHOT.latencySamplesMs.length).assertEqual(0);
    });

    it('defines the P4 error matrix', 0, () => {
      expect(P4_ERROR_CODES.indexOf('INSUFFICIENT_EVIDENCE') >= 0).assertTrue();
      expect(P4_ERROR_CODES.indexOf('E_BACKGROUND_INTERRUPTED') >= 0).assertTrue();
      expect(P4_ERROR_CODES.indexOf('E_PROFILE_STALE') >= 0).assertTrue();
      expect(P4_ERROR_CODES.indexOf('E_SEMANTIC_PROTOCOL_INVALID') >= 0).assertTrue();
      expect(P4_ERROR_CODES.indexOf('E_EVIDENCE_TOO_LARGE') >= 0).assertTrue();
      expect(P4_ERROR_CODES.indexOf('E_EVIDENCE_PAGE_LIMIT') >= 0).assertTrue();
      expect(P4_ERROR_CODES.indexOf('E_EVIDENCE_PAGE_TIMEOUT') >= 0).assertTrue();
    });
  });
}
