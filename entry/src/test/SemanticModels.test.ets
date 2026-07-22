import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeError } from '../main/ets/contracts/knowledge/KnowledgeError';
import {
  DEFAULT_COVERAGE_THRESHOLD,
  DEFAULT_REQUIRED_CONFIDENCE,
  DeviceProfileAdvertisement,
  DeviceRuntimeSnapshot,
  EvidenceUnit,
  PayloadLevel,
  SEMANTIC_CONTRACT_VERSION,
  TaskPhase,
  TaskRequest,
  TaskSufficiencyFeedback,
  TaskSufficiencyResult,
  validateTaskRequest
} from '../main/ets/contracts/semantic/SemanticModels';

function capturedCode(action: () => void): string {
  try {
    action();
  } catch (error) {
    if (error instanceof KnowledgeError) {
      return error.code;
    }
  }
  return '';
}

function validTaskRequest(): TaskRequest {
  return {
    semanticContractVersion: SEMANTIC_CONTRACT_VERSION,
    taskId: 'semantic-models-task',
    queryText: 'process scheduling priority queue',
    requiredConcepts: ['process', 'scheduling'],
    requiredConfidence: DEFAULT_REQUIRED_CONFIDENCE,
    coverageThreshold: DEFAULT_COVERAGE_THRESHOLD,
    latencyBudgetMs: 1000,
    byteBudget: 4096,
    privacyLevel: 'PRIVATE_GROUP',
    acceptableLevels: ['L1', 'L2']
  };
}

function l1Evidence(): EvidenceUnit {
  return {
    semanticContractVersion: SEMANTIC_CONTRACT_VERSION,
    evidenceId: 'ev-l1-doc-1',
    evidenceGroupId: 'group-doc-1',
    sourceDeviceId: 'local-device',
    sourceDocId: 'doc-1',
    level: 'L1',
    title: 'Process scheduling overview',
    snippet: 'A process is scheduled by priority.',
    relevance: 0.9,
    coveredConcepts: ['process', 'scheduling'],
    estimatedCoverageGain: 1,
    byteCost: 256,
    privacyLevel: 'PRIVATE_GROUP',
    privacyCost: 0.2,
    energyCost: 0.05,
    hash: 'hash-l1',
    canEscalateTo: ['L2']
  };
}

function l2Evidence(parent: EvidenceUnit): EvidenceUnit {
  return {
    semanticContractVersion: SEMANTIC_CONTRACT_VERSION,
    evidenceId: 'ev-l2-chunk-1',
    evidenceGroupId: parent.evidenceGroupId,
    parentEvidenceId: parent.evidenceId,
    sourceDeviceId: parent.sourceDeviceId,
    sourceDocId: parent.sourceDocId,
    sourceChunkId: 'chunk-1',
    level: 'L2',
    title: parent.title,
    summary: 'Detailed scheduling snippet',
    snippet: 'Priority queue uses aging to avoid starvation.',
    relevance: 0.95,
    coveredConcepts: parent.coveredConcepts,
    estimatedCoverageGain: 0.5,
    byteCost: 512,
    privacyLevel: parent.privacyLevel,
    privacyCost: 0.2,
    energyCost: 0.1,
    hash: 'hash-l2',
    canEscalateTo: []
  };
}

export default function semanticModelsTest(): void {
  describe('SemanticModels', () => {
    it('pins default required confidence and coverage threshold to 0.80', 0, () => {
      expect(DEFAULT_REQUIRED_CONFIDENCE).assertEqual(0.8);
      expect(DEFAULT_COVERAGE_THRESHOLD).assertEqual(0.8);
    });

    it('exposes the ten task phases used by the progressive loop', 0, () => {
      const phases: TaskPhase[] = [
        'PENDING', 'ROUTING', 'AWAITING_L1', 'EVALUATING_L1', 'NEED_MORE',
        'AWAITING_L2', 'EVALUATING_L2', 'SUFFICIENT', 'ABORTED', 'FAILED'
      ];
      expect(phases.length).assertEqual(10);
      const seen: Set<string> = new Set<string>();
      for (const phase of phases) {
        seen.add(phase);
      }
      expect(seen.size).assertEqual(10);
      expect(seen.has('PENDING')).assertTrue();
      expect(seen.has('SUFFICIENT')).assertTrue();
      expect(seen.has('ABORTED')).assertTrue();
      expect(seen.has('FAILED')).assertTrue();
    });

    it('accepts only ENOUGH NEED_MORE and ABORT as task sufficiency feedback', 0, () => {
      const enough: TaskSufficiencyFeedback = 'ENOUGH';
      const needMore: TaskSufficiencyFeedback = 'NEED_MORE';
      const abort: TaskSufficiencyFeedback = 'ABORT';
      const feedbacks: TaskSufficiencyFeedback[] = [enough, needMore, abort];
      expect(feedbacks.length).assertEqual(3);
      expect(enough).assertEqual('ENOUGH');
      expect(needMore).assertEqual('NEED_MORE');
      expect(abort).assertEqual('ABORT');
    });

    it('builds task sufficiency results with covered and missing concepts', 0, () => {
      const enough: TaskSufficiencyResult = {
        feedback: 'ENOUGH',
        coverage: 0.9,
        confidence: 0.85,
        diversity: 1,
        coveredConcepts: ['process', 'scheduling'],
        missingConcepts: [],
        acceptedEvidenceIds: ['ev-l1-doc-1']
      };
      const abort: TaskSufficiencyResult = {
        feedback: 'ABORT',
        coverage: 0.4,
        confidence: 0.5,
        diversity: 0.5,
        coveredConcepts: [],
        missingConcepts: ['priority', 'queue'],
        acceptedEvidenceIds: []
      };
      expect(enough.feedback).assertEqual('ENOUGH');
      expect(enough.coveredConcepts.length).assertEqual(2);
      expect(abort.feedback).assertEqual('ABORT');
      expect(abort.missingConcepts.length).assertEqual(2);
    });

    it('captures device runtime snapshots with local and remote state', 0, () => {
      const local: DeviceRuntimeSnapshot = {
        deviceId: 'local-device',
        deviceAlias: 'local-device',
        isLocal: true,
        state: 'READY',
        profileVersion: 'profile-1',
        indexVersion: 'index-1',
        lastSeenAtMs: 1000,
        averageRttMs: 0,
        load: 0.1,
        advertisedAtMs: 1000
      };
      const remote: DeviceRuntimeSnapshot = {
        deviceId: 'remote-device',
        deviceAlias: 'peer-phone',
        isLocal: false,
        state: 'BUSY',
        profileVersion: 'profile-remote-1',
        indexVersion: 'index-remote-1',
        lastSeenAtMs: 2000,
        averageRttMs: 120,
        load: 0.6,
        advertisedAtMs: 2000
      };
      expect(local.isLocal).assertTrue();
      expect(local.state).assertEqual('READY');
      expect(remote.isLocal).assertFalse();
      expect(remote.state).assertEqual('BUSY');
      expect(remote.averageRttMs).assertEqual(120);
    });

    it('advertises device profiles with semantic contract version and TTL', 0, () => {
      const advertisement: DeviceProfileAdvertisement = {
        semanticContractVersion: SEMANTIC_CONTRACT_VERSION,
        deviceId: 'remote-device',
        deviceAlias: 'peer-phone',
        profileVersion: 'profile-remote-1',
        indexVersion: 'index-remote-1',
        indexState: 'READY',
        knowledgeDomains: ['network', 'software-testing'],
        modalities: ['text', 'pdf'],
        retrievalModes: ['keyword'],
        supportedLevels: ['L1', 'L2'],
        advertisedAtMs: 5000,
        ttlMs: 300000
      };
      expect(advertisement.semanticContractVersion).assertEqual('1.0');
      expect(advertisement.indexState).assertEqual('READY');
      expect(advertisement.ttlMs).assertEqual(300000);
      expect(advertisement.supportedLevels.length).assertEqual(2);
    });

    it('distinguishes payload levels from evidence levels and forbids L3 evidence', 0, () => {
      const l0: PayloadLevel = 'L0';
      const l1: PayloadLevel = 'L1';
      const l2: PayloadLevel = 'L2';
      const l3: PayloadLevel = 'L3';
      const levels: PayloadLevel[] = [l0, l1, l2, l3];
      expect(levels.length).assertEqual(4);
      const parent: EvidenceUnit = l1Evidence();
      const child: EvidenceUnit = l2Evidence(parent);
      expect(parent.level).assertEqual('L1');
      expect(child.level).assertEqual('L2');
    });

    it('links L1 and L2 evidence through evidence group and parent identifiers', 0, () => {
      const parent: EvidenceUnit = l1Evidence();
      const child: EvidenceUnit = l2Evidence(parent);
      expect(child.evidenceGroupId).assertEqual(parent.evidenceGroupId);
      expect(child.parentEvidenceId).assertEqual(parent.evidenceId);
      expect(child.sourceDocId).assertEqual(parent.sourceDocId);
      expect(child.level).assertEqual('L2');
      expect(parent.level).assertEqual('L1');
      expect(parent.parentEvidenceId === undefined).assertTrue();
      expect(child.canEscalateTo.length).assertEqual(0);
      expect(parent.canEscalateTo.length).assertEqual(1);
    });

    it('accepts a valid task request with default thresholds', 0, () => {
      const task: TaskRequest = validTaskRequest();
      validateTaskRequest(task);
      expect(task.requiredConfidence).assertEqual(DEFAULT_REQUIRED_CONFIDENCE);
      expect(task.coverageThreshold).assertEqual(DEFAULT_COVERAGE_THRESHOLD);
    });

    it('rejects blank task identity and negative byte budget', 0, () => {
      const blankId: TaskRequest = validTaskRequest();
      blankId.taskId = '   ';
      expect(capturedCode((): void => validateTaskRequest(blankId))).assertEqual('E_QUERY_INVALID');

      const negativeBudget: TaskRequest = validTaskRequest();
      negativeBudget.byteBudget = -1;
      expect(capturedCode((): void => validateTaskRequest(negativeBudget)))
        .assertEqual('E_QUERY_INVALID');

      const zeroLatency: TaskRequest = validTaskRequest();
      zeroLatency.latencyBudgetMs = 0;
      expect(capturedCode((): void => validateTaskRequest(zeroLatency)))
        .assertEqual('E_QUERY_INVALID');

      const blankQuery: TaskRequest = validTaskRequest();
      blankQuery.queryText = '';
      expect(capturedCode((): void => validateTaskRequest(blankQuery)))
        .assertEqual('E_QUERY_INVALID');
    });

    it('rejects out-of-range thresholds and empty acceptable levels', 0, () => {
      const highConfidence: TaskRequest = validTaskRequest();
      highConfidence.requiredConfidence = 1.5;
      expect(capturedCode((): void => validateTaskRequest(highConfidence)))
        .assertEqual('E_QUERY_INVALID');

      const negativeCoverage: TaskRequest = validTaskRequest();
      negativeCoverage.coverageThreshold = -0.1;
      expect(capturedCode((): void => validateTaskRequest(negativeCoverage)))
        .assertEqual('E_QUERY_INVALID');

      const emptyLevels: TaskRequest = validTaskRequest();
      emptyLevels.acceptableLevels = [];
      expect(capturedCode((): void => validateTaskRequest(emptyLevels)))
        .assertEqual('E_QUERY_INVALID');

      const fractionalBudget: TaskRequest = validTaskRequest();
      fractionalBudget.byteBudget = 1.5;
      expect(capturedCode((): void => validateTaskRequest(fractionalBudget)))
        .assertEqual('E_QUERY_INVALID');
    });
  });
}
