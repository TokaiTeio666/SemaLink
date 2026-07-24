import { describe, expect, it } from '@ohos/hypium';
import { EvidenceUnit, TaskSufficiencyResult } from '../main/ets/contracts/semantic/SemanticModels';
import { AgentQueryResult } from '../main/ets/agent/query/AgentQueryModels';
import { KnowledgeAnswerFormatter } from '../main/ets/agent/query/KnowledgeAnswerFormatter';

function evidence(id: string, source: string, text: string): EvidenceUnit {
  return {
    semanticContractVersion: '1.0', evidenceId: id, evidenceGroupId: id,
    sourceDeviceId: source, sourceDocId: 'private-doc-id', level: 'L2', title: '数据库课程笔记',
    summary: text, relevance: 0.9, coveredConcepts: ['数据库'], estimatedCoverageGain: 0.8,
    byteCost: 100, privacyLevel: 'PRIVATE_GROUP', privacyCost: 0.1, energyCost: 0.1,
    hash: 'hash-' + id, canEscalateTo: []
  };
}

function sufficiency(feedback: 'ENOUGH' | 'NEED_MORE' | 'ABORT'): TaskSufficiencyResult {
  return {
    feedback: feedback, coverage: feedback === 'ENOUGH' ? 1 : 0.5,
    confidence: feedback === 'ENOUGH' ? 0.9 : 0.4, diversity: 1,
    coveredConcepts: ['数据库'], missingConcepts: [], acceptedEvidenceIds: []
  };
}

export default function knowledgeAnswerFormatterTest(): void {
  describe('KnowledgeAnswerFormatter', () => {
    it('formats local and remote evidence without exposing device ids', 0, () => {
      const units: EvidenceUnit[] = [
        evidence('local-1', 'local-device', '本机内容'),
        evidence('remote-1', 'mock-device-secret', 'SEMALINK_REMOTE_EVIDENCE_UNIQUE_20260722')
      ];
      const result: AgentQueryResult = new AgentQueryResult(
        'internal-secret', units, sufficiency('ENOUGH'), true, true, true, [], 5, ['remote-1']);
      const answer: string = new KnowledgeAnswerFormatter().format(result);
      expect(answer.indexOf('本机内容') >= 0).assertTrue();
      expect(answer.indexOf('SEMALINK_REMOTE_EVIDENCE_UNIQUE_20260722') >= 0).assertTrue();
      expect(answer.indexOf('另一台可信设备') >= 0).assertTrue();
      expect(answer.indexOf('mock-device-secret') < 0).assertTrue();
      expect(answer.indexOf('internal-secret') < 0).assertTrue();
      expect(answer.indexOf('private-doc-id') < 0).assertTrue();
    });

    it('returns a normal empty result and truthfully reports unavailable remote', 0, () => {
      const result: AgentQueryResult = new AgentQueryResult(
        'internal-2', [], sufficiency('ABORT'), true, false, false, [], 1, []);
      const answer: string = new KnowledgeAnswerFormatter().format(result);
      expect(answer.indexOf('未找到相关资料') >= 0).assertTrue();
      expect(answer.indexOf('跨设备通道当前不可用') >= 0).assertTrue();
    });

    it('marks insufficient evidence and caps total output', 0, () => {
      const result: AgentQueryResult = new AgentQueryResult(
        'internal-3', [evidence('local-1', 'local-device', 'x'.repeat(3000))],
        sufficiency('NEED_MORE'), true, false, false, [], 1, []);
      const answer: string = new KnowledgeAnswerFormatter().format(result);
      expect(answer.indexOf('资料可能不完整') >= 0).assertTrue();
      expect(answer.length <= 2000).assertTrue();
    });
  });
}
