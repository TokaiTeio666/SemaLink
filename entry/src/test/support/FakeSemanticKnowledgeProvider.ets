import { KnowledgeProfile } from '../../main/ets/contracts/knowledge/KnowledgeModels';
import { EvidenceUnit, TaskRequest } from '../../main/ets/contracts/semantic/SemanticModels';
import { SemanticKnowledgeProvider } from '../../main/ets/contracts/semantic/SemanticKnowledgeProvider';
import {
  SEMANTIC_COMMUNICATION_CASES,
  SemanticCommunicationCase
} from './SemanticFixtures';
import { utf8ByteLength } from '../../main/ets/knowledge/payload/Utf8Sizer';

function findCase(taskId: string): SemanticCommunicationCase {
  for (const fixture of SEMANTIC_COMMUNICATION_CASES) {
    if (fixture.task.taskId === taskId) {
      return fixture;
    }
  }
  throw new Error('Missing semantic communication fixture: ' + taskId);
}

function buildEvidence(task: TaskRequest, fixture: SemanticCommunicationCase, sourceDeviceId: string): EvidenceUnit[] {
  const level: 'L1' | 'L2' = fixture.expectedTerminalState === 'L1_SUFFICIENT' ? 'L1' : 'L2';
  const coveredConcepts: string[] = level === 'L1' || fixture.expectedTerminalState === 'L2_SUFFICIENT' ?
    task.requiredConcepts.slice() : task.requiredConcepts.slice(0, 1);
  const evidenceId = 'fixture-' + task.taskId + '-' + level.toLowerCase();
  const unit: EvidenceUnit = {
    semanticContractVersion: '1.0', evidenceId: evidenceId, evidenceGroupId: 'group-' + task.taskId,
    sourceDeviceId: sourceDeviceId, sourceDocId: 'doc-' + fixture.expectedDomain,
    sourceChunkId: level === 'L2' ? 'chunk-' + task.taskId : undefined,
    parentEvidenceId: level === 'L2' ? 'fixture-' + task.taskId + '-l1' : undefined,
    level: level, title: fixture.name, summary: fixture.task.queryText,
    relevance: 1, coveredConcepts: coveredConcepts,
    estimatedCoverageGain: coveredConcepts.length / Math.max(1, task.requiredConcepts.length),
    byteCost: fixture.expectedEvidenceBytes, privacyLevel: task.privacyLevel, privacyCost: 0.2,
    energyCost: level === 'L1' ? 0.05 : 0.1, hash: 'hash-' + evidenceId,
    canEscalateTo: level === 'L1' ? ['L2'] : []
  };
  const measured = utf8ByteLength(JSON.stringify(unit));
  unit.byteCost = measured;
  return [unit];
}

export class FakeSemanticKnowledgeProvider implements SemanticKnowledgeProvider {
  readonly deviceId: string;
  readonly profile: KnowledgeProfile;
  searchCallCount: number = 0;
  profileCallCount: number = 0;
  lastIndexVersion: string = '';

  constructor(deviceId: string = 'local-device') {
    this.deviceId = deviceId;
    const remote = deviceId === 'remote-device';
    this.profile = {
      contractVersion: '1.0', profileVersion: remote ? 'fixture-remote-profile-v1' : 'fixture-local-profile-v1',
      indexState: 'READY',
      knowledgeDomains: remote ?
        [{ tag: '网络', weight: 1, documentCount: 4 }, { tag: '软件测试', weight: 1, documentCount: 4 }] :
        [{ tag: '操作系统', weight: 1, documentCount: 4 }, { tag: '数据库', weight: 1, documentCount: 4 }],
      documentCount: 8, chunkCount: 8, modalities: ['text', 'pdf', 'image', 'ocr_text'],
      retrievalModes: ['keyword'], supportedLevels: ['L1', 'L2'],
      indexVersion: remote ? 'fixture-remote-index-v1' : 'fixture-local-index-v1',
      embeddingModelVersion: '', updatedAt: 1000
    };
    this.lastIndexVersion = this.profile.indexVersion;
  }

  getProfile(): Promise<KnowledgeProfile> {
    this.profileCallCount++;
    this.lastIndexVersion = this.profile.indexVersion;
    return Promise.resolve(this.profile);
  }

  searchEvidence(task: TaskRequest): Promise<EvidenceUnit[]> {
    this.searchCallCount++;
    this.lastIndexVersion = this.profile.indexVersion;
    const fixture = findCase(task.taskId);
    if (fixture.expectedDevice === 'REMOTE' && this.deviceId !== 'remote-device') {
      return Promise.resolve([]);
    }
    if (fixture.expectedDevice === 'LOCAL' && this.deviceId !== 'local-device') {
      return Promise.resolve([]);
    }
    return Promise.resolve(buildEvidence(task, fixture, this.deviceId));
  }
}
