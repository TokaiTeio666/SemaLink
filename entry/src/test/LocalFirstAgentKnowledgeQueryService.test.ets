import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeProfile } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { SemanticKnowledgeProvider } from '../main/ets/contracts/semantic/SemanticKnowledgeProvider';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import { AgentQueryRequest, AgentQueryScope } from '../main/ets/agent/query/AgentQueryModels';
import { LocalFirstAgentKnowledgeQueryService } from '../main/ets/agent/query/LocalFirstAgentKnowledgeQueryService';
import { UnavailableCrossDeviceKnowledgePort } from '../main/ets/agent/query/UnavailableCrossDeviceKnowledgePort';
import { FakeCrossDeviceKnowledgePort } from './support/FakeCrossDeviceKnowledgePort';

function evidence(id: string, source: string, text: string): EvidenceUnit {
  return {
    semanticContractVersion: '1.0', evidenceId: id, evidenceGroupId: 'group-' + id,
    sourceDeviceId: source, sourceDocId: 'doc-' + id, level: 'L2', title: '数据库资料',
    summary: text, snippet: text, relevance: 0.9, coveredConcepts: ['数据库'],
    estimatedCoverageGain: 0.9, byteCost: 128, privacyLevel: 'PRIVATE_GROUP',
    privacyCost: 0.1, energyCost: 0.1, hash: 'hash-' + text, canEscalateTo: []
  };
}

class CapturingProvider implements SemanticKnowledgeProvider {
  evidence: EvidenceUnit[] = [];
  captured?: TaskRequest;
  fail: boolean = false;

  getProfile(): Promise<KnowledgeProfile> {
    return Promise.reject(new Error('Profile is not used by agent query tests'));
  }

  searchEvidence(task: TaskRequest): Promise<EvidenceUnit[]> {
    this.captured = task;
    if (this.fail) {
      return Promise.reject(new Error('controlled local failure'));
    }
    return Promise.resolve(this.evidence);
  }
}

export default function localFirstAgentKnowledgeQueryServiceTest(): void {
  describe('LocalFirstAgentKnowledgeQueryService', () => {
    it('queries the real semantic provider with a real TaskRequest', 0, async () => {
      const local: CapturingProvider = new CapturingProvider();
      local.evidence = [evidence('local-1', 'local-device', '本机数据库证据')];
      const service: LocalFirstAgentKnowledgeQueryService = new LocalFirstAgentKnowledgeQueryService(
        local, new UnavailableCrossDeviceKnowledgePort(), (): number => 1000);
      const result = await service.query(new AgentQueryRequest('internal-1', '数据库', AgentQueryScope.LOCAL_AND_REMOTE));
      expect(local.captured?.taskId).assertEqual('internal-1');
      expect(local.captured?.queryText).assertEqual('数据库');
      expect(result.evidence.length).assertEqual(1);
      expect(result.queriedLocal).assertTrue();
      expect(result.queriedRemote).assertFalse();
      expect(result.remoteAvailable).assertFalse();
    });

    it('merges fake remote evidence and deduplicates by content hash', 0, async () => {
      const local: CapturingProvider = new CapturingProvider();
      local.evidence = [evidence('local-1', 'local-device', '重复证据')];
      const remote: FakeCrossDeviceKnowledgePort = new FakeCrossDeviceKnowledgePort();
      remote.evidence = [
        evidence('remote-duplicate', 'mock-device-secret', '重复证据'),
        evidence('remote-unique', 'mock-device-secret', 'SEMALINK_REMOTE_EVIDENCE_UNIQUE_20260722')
      ];
      const service: LocalFirstAgentKnowledgeQueryService =
        new LocalFirstAgentKnowledgeQueryService(local, remote, (): number => 1000);
      const result = await service.query(new AgentQueryRequest('internal-2', '数据库', AgentQueryScope.LOCAL_AND_REMOTE));
      expect(result.evidence.length).assertEqual(2);
      expect(result.queriedRemote).assertTrue();
      expect(result.remoteAvailable).assertTrue();
      expect(result.remoteEvidenceIds.indexOf('remote-unique') >= 0).assertTrue();
    });

    it('keeps remote success when local provider fails', 0, async () => {
      const local: CapturingProvider = new CapturingProvider();
      local.fail = true;
      const remote: FakeCrossDeviceKnowledgePort = new FakeCrossDeviceKnowledgePort();
      remote.evidence = [evidence('remote-1', 'mock-device-secret', '远端证据')];
      const service: LocalFirstAgentKnowledgeQueryService =
        new LocalFirstAgentKnowledgeQueryService(local, remote, (): number => 1000);
      const result = await service.query(new AgentQueryRequest('internal-3', '数据库', AgentQueryScope.LOCAL_AND_REMOTE));
      expect(result.evidence.length).assertEqual(1);
      expect(result.failedSources.length).assertEqual(1);
      expect(result.queriedRemote).assertTrue();
    });

    it('maps remote timeout and thrown errors without losing local evidence', 0, async () => {
      const local: CapturingProvider = new CapturingProvider();
      local.evidence = [evidence('local-safe', 'local-device', 'local survives')];
      const remote: FakeCrossDeviceKnowledgePort = new FakeCrossDeviceKnowledgePort();
      remote.timedOut = true;
      const service: LocalFirstAgentKnowledgeQueryService =
        new LocalFirstAgentKnowledgeQueryService(local, remote, (): number => 1000);
      const timeout = await service.query(
        new AgentQueryRequest('internal-timeout', 'database', AgentQueryScope.LOCAL_AND_REMOTE));
      expect(timeout.evidence.length).assertEqual(1);
      expect(timeout.failedSources[0]).assertEqual('REMOTE_TIMEOUT');
      remote.timedOut = false;
      remote.throwControlledError = true;
      const failed = await service.query(
        new AgentQueryRequest('internal-error', 'database', AgentQueryScope.LOCAL_AND_REMOTE));
      expect(failed.evidence.length).assertEqual(1);
      expect(failed.failedSources[0]).assertEqual('REMOTE_QUERY_FAILED');
    });

    it('propagates cancellation to cross-device port', 0, () => {
      const remote: FakeCrossDeviceKnowledgePort = new FakeCrossDeviceKnowledgePort();
      const service: LocalFirstAgentKnowledgeQueryService =
        new LocalFirstAgentKnowledgeQueryService(new CapturingProvider(), remote, (): number => 1000);
      service.cancel('internal-4');
      expect(remote.cancelledTaskIds[0]).assertEqual('internal-4');
    });

    it('does not retain a cancellation marker after a query has settled', 0, async () => {
      const remote: FakeCrossDeviceKnowledgePort = new FakeCrossDeviceKnowledgePort();
      const service: LocalFirstAgentKnowledgeQueryService =
        new LocalFirstAgentKnowledgeQueryService(new CapturingProvider(), remote, (): number => 1000);
      const request: AgentQueryRequest = new AgentQueryRequest(
        'reused-internal-id', '本机知识', AgentQueryScope.LOCAL_ONLY);
      await service.query(request);
      service.cancel('reused-internal-id');
      const result = await service.query(request);
      expect(result.internalTaskId).assertEqual('reused-internal-id');
    });
  });
}
