import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeError } from '../main/ets/contracts/knowledge/KnowledgeError';
import { KnowledgeProfile } from '../main/ets/contracts/knowledge/KnowledgeModels';
import {
  EvidenceLevel,
  EvidenceUnit,
  PrivacyLevel,
  SEMANTIC_CONTRACT_VERSION,
  TaskRequest,
  validateSemanticContractVersion,
  validateTaskRequest
} from '../main/ets/contracts/semantic/SemanticModels';
import { SemanticKnowledgeProvider } from '../main/ets/contracts/semantic/SemanticKnowledgeProvider';

class ContractProvider implements SemanticKnowledgeProvider {
  private readonly profile: KnowledgeProfile;

  constructor(profile: KnowledgeProfile) {
    this.profile = profile;
  }

  async getProfile(): Promise<KnowledgeProfile> {
    return this.profile;
  }

  async searchEvidence(task: TaskRequest): Promise<EvidenceUnit[]> {
    return [];
  }
}

function profile(): KnowledgeProfile {
  return {
    contractVersion: '1.0', profileVersion: 'profile-1', indexState: 'READY', knowledgeDomains: [],
    documentCount: 0, chunkCount: 0, modalities: [], retrievalModes: ['keyword'],
    supportedLevels: ['L1', 'L2'], indexVersion: 'index-1', embeddingModelVersion: '', updatedAt: 1
  };
}

function task(): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: 'task-1', queryText: 'process scheduling',
    requiredConcepts: ['process', 'scheduling'], requiredConfidence: 0.8, coverageThreshold: 0.7,
    latencyBudgetMs: 1000, byteBudget: 4096, privacyLevel: 'PRIVATE_GROUP',
    acceptableLevels: ['L1', 'L2'],
    filters: { documentIds: ['doc-1'], tags: ['os'], modalities: ['text'], updatedAfter: 1 }
  };
}

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

export default function semanticContractTest() {
  describe('SemanticContract', () => {
    it('exposes the confirmed contract version and closed privacy and evidence levels', 0, () => {
      const local: PrivacyLevel = 'LOCAL_ONLY';
      const group: PrivacyLevel = 'PRIVATE_GROUP';
      const l1: EvidenceLevel = 'L1';
      const l2: EvidenceLevel = 'L2';

      expect(SEMANTIC_CONTRACT_VERSION).assertEqual('1.0');
      expect(local).assertEqual('LOCAL_ONLY');
      expect(group).assertEqual('PRIVATE_GROUP');
      expect(l1).assertEqual('L1');
      expect(l2).assertEqual('L2');
    });

    it('keeps the task and evidence fields required by the evidence provider', 0, () => {
      const request: TaskRequest = task();
      const evidence: EvidenceUnit = {
        semanticContractVersion: '1.0',
        evidenceId: 'ev-l2-chunk-1', evidenceGroupId: 'doc-doc-1', parentEvidenceId: 'ev-l1-doc-1',
        sourceDeviceId: 'local-device', sourceDocId: 'doc-1', sourceChunkId: 'chunk-1', level: 'L2',
        title: 'Process scheduling', snippet: 'A process is scheduled by priority.', relevance: 0.9,
        coveredConcepts: ['process', 'scheduling'], estimatedCoverageGain: 1,
        privacyLevel: 'PRIVATE_GROUP', privacyCost: 0.2, energyCost: 0.1,
        hash: 'stable-hash', byteCost: 512, canEscalateTo: []
      };

      expect(request.semanticContractVersion).assertEqual('1.0');
      expect(JSON.stringify(request.acceptableLevels)).assertEqual(JSON.stringify(['L1', 'L2']));
      expect(evidence.parentEvidenceId).assertEqual('ev-l1-doc-1');
      expect(evidence.sourceDocId).assertEqual('doc-1');
      expect(evidence.sourceChunkId).assertEqual('chunk-1');
    });

    it('validates the formal task bounds and maps unsupported versions safely', 0, () => {
      const valid = task();
      validateTaskRequest(valid);
      expect(capturedCode((): void => validateSemanticContractVersion('2.0')))
        .assertEqual('E_CONTRACT_VERSION_UNSUPPORTED');

      valid.requiredConfidence = 1.1;
      expect(capturedCode((): void => validateTaskRequest(valid))).assertEqual('E_QUERY_INVALID');
      valid.requiredConfidence = 0.8;
      valid.coverageThreshold = -0.1;
      expect(capturedCode((): void => validateTaskRequest(valid))).assertEqual('E_QUERY_INVALID');
      valid.coverageThreshold = 0.7;
      valid.latencyBudgetMs = 0;
      expect(capturedCode((): void => validateTaskRequest(valid))).assertEqual('E_QUERY_INVALID');
      valid.latencyBudgetMs = 1000;
      valid.byteBudget = 1.5;
      expect(capturedCode((): void => validateTaskRequest(valid))).assertEqual('E_QUERY_INVALID');
      valid.byteBudget = 4096;
      valid.acceptableLevels = [];
      expect(capturedCode((): void => validateTaskRequest(valid))).assertEqual('E_QUERY_INVALID');
      valid.acceptableLevels = ['L1', 'L1'];
      expect(capturedCode((): void => validateTaskRequest(valid))).assertEqual('E_QUERY_INVALID');
    });

    it('rejects blank task identity and filters that resemble storage access', 0, () => {
      const invalid = task();
      invalid.queryText = '   ';
      expect(capturedCode((): void => validateTaskRequest(invalid))).assertEqual('E_QUERY_INVALID');
      invalid.queryText = 'process scheduling';
      invalid.taskId = '';
      expect(capturedCode((): void => validateTaskRequest(invalid))).assertEqual('E_QUERY_INVALID');
      invalid.taskId = 'task-1';
      if (invalid.filters !== undefined) {
        invalid.filters.documentIds = ['file:///data/private'];
      }
      expect(capturedCode((): void => validateTaskRequest(invalid))).assertEqual('E_FILTER_INVALID');
      if (invalid.filters !== undefined) {
        invalid.filters.documentIds = ['doc-1'];
        invalid.filters.updatedAfter = Number.NaN;
      }
      expect(capturedCode((): void => validateTaskRequest(invalid))).assertEqual('E_FILTER_INVALID');
    });

    it('rejects invalid privacy concepts and single-segment or UNC storage references', 0, () => {
      const invalid = task();
      invalid.privacyLevel = 'NETWORK' as PrivacyLevel;
      expect(capturedCode((): void => validateTaskRequest(invalid))).assertEqual('E_QUERY_INVALID');
      invalid.privacyLevel = 'PRIVATE_GROUP';
      invalid.requiredConcepts = ['process', '   '];
      expect(capturedCode((): void => validateTaskRequest(invalid))).assertEqual('E_QUERY_INVALID');
      invalid.requiredConcepts = ['process'];
      if (invalid.filters !== undefined) {
        invalid.filters.documentIds = ['/tmp'];
      }
      expect(capturedCode((): void => validateTaskRequest(invalid))).assertEqual('E_FILTER_INVALID');
      if (invalid.filters !== undefined) {
        invalid.filters.documentIds = ['\\\\server\\share\\file'];
      }
      expect(capturedCode((): void => validateTaskRequest(invalid))).assertEqual('E_FILTER_INVALID');
    });

    it('reuses the formal knowledge profile and returns no-match as an empty list', 0, async () => {
      const provider: SemanticKnowledgeProvider = new ContractProvider(profile());
      const actualProfile: KnowledgeProfile = await provider.getProfile();
      const emptyTask = task();
      emptyTask.taskId = 'task-empty';
      emptyTask.queryText = 'no match';
      emptyTask.requiredConcepts = [];
      emptyTask.privacyLevel = 'LOCAL_ONLY';
      emptyTask.acceptableLevels = ['L1'];
      const evidence: EvidenceUnit[] = await provider.searchEvidence(emptyTask);

      expect(actualProfile.profileVersion).assertEqual('profile-1');
      expect(evidence.length).assertEqual(0);
    });
  });
}
