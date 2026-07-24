import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeProfile } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { EvidenceUnit, TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import { SemanticKnowledgeProvider } from '../main/ets/contracts/semantic/SemanticKnowledgeProvider';
import { AgentQueryRequest, AgentQueryScope } from '../main/ets/agent/query/AgentQueryModels';
import { AgentQueryScopeResolver } from '../main/ets/agent/query/AgentQueryScopeResolver';
import { LocalFirstAgentKnowledgeQueryService }
  from '../main/ets/agent/query/LocalFirstAgentKnowledgeQueryService';
import { UnavailableCrossDeviceKnowledgePort }
  from '../main/ets/agent/query/UnavailableCrossDeviceKnowledgePort';

class ScopeProvider implements SemanticKnowledgeProvider {
  calls: number = 0;
  getProfile(): Promise<KnowledgeProfile> { return Promise.reject(new Error('unused')); }
  searchEvidence(_task: TaskRequest): Promise<EvidenceUnit[]> {
    this.calls += 1;
    return Promise.resolve([]);
  }
}

export default function agentQueryScopeIntegrationTest(): void {
  describe('AgentQueryScopeIntegration', () => {
    it('resolves the complete Chinese product phrase matrix', 0, () => {
      const resolver: AgentQueryScopeResolver = new AgentQueryScopeResolver();
      expect(resolver.resolve('查询本机的数据库资料')).assertEqual(AgentQueryScope.LOCAL_ONLY);
      expect(resolver.resolve('搜索当前设备里的知识')).assertEqual(AgentQueryScope.LOCAL_ONLY);
      expect(resolver.resolve('查询另一台可信设备')).assertEqual(AgentQueryScope.REMOTE_ONLY);
      expect(resolver.resolve('只查其他设备')).assertEqual(AgentQueryScope.REMOTE_ONLY);
      expect(resolver.resolve('查询本机和其他设备')).assertEqual(AgentQueryScope.LOCAL_AND_REMOTE);
      expect(resolver.resolve('在可信设备中综合查询')).assertEqual(AgentQueryScope.REMOTE_ONLY);
      expect(resolver.resolve('数据库事务隔离级别')).assertEqual(AgentQueryScope.LOCAL_ONLY);
    });

    it('keeps LOCAL_ONLY local, REMOTE_ONLY non-local, and combined locally degradable', 0, async () => {
      const provider: ScopeProvider = new ScopeProvider();
      const service: LocalFirstAgentKnowledgeQueryService = new LocalFirstAgentKnowledgeQueryService(
        provider, new UnavailableCrossDeviceKnowledgePort(), (): number => 5000);
      const local = await service.query(new AgentQueryRequest('local', '本机', AgentQueryScope.LOCAL_ONLY));
      expect(local.queriedLocal).assertTrue();
      expect(local.queriedRemote).assertFalse();
      expect(provider.calls).assertEqual(1);
      const remote = await service.query(new AgentQueryRequest('remote', '其他设备', AgentQueryScope.REMOTE_ONLY));
      expect(remote.queriedLocal).assertFalse();
      expect(remote.queriedRemote).assertFalse();
      expect(remote.remoteAvailable).assertFalse();
      expect(provider.calls).assertEqual(1);
      const combined = await service.query(
        new AgentQueryRequest('combined', '本机和其他设备', AgentQueryScope.LOCAL_AND_REMOTE));
      expect(combined.queriedLocal).assertTrue();
      expect(combined.queriedRemote).assertFalse();
      expect(combined.remoteAvailable).assertFalse();
      expect(provider.calls).assertEqual(2);
    });
  });
}
