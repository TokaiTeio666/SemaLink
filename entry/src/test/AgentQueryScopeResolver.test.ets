import { describe, expect, it } from '@ohos/hypium';
import { AgentQueryScope } from '../main/ets/agent/query/AgentQueryModels';
import { AgentQueryScopeResolver } from '../main/ets/agent/query/AgentQueryScopeResolver';

export default function agentQueryScopeResolverTest(): void {
  describe('AgentQueryScopeResolver', () => {
    const resolver: AgentQueryScopeResolver = new AgentQueryScopeResolver();

    it('uses local-only as the safe default and for explicit local phrases', 0, () => {
      expect(resolver.resolve('数据库怎么使用')).assertEqual(AgentQueryScope.LOCAL_ONLY);
      expect(resolver.resolve('查询本机知识')).assertEqual(AgentQueryScope.LOCAL_ONLY);
      expect(resolver.resolve('只看当前设备')).assertEqual(AgentQueryScope.LOCAL_ONLY);
    });

    it('distinguishes remote-only and explicit combined queries', 0, () => {
      expect(resolver.resolve('只查询其他设备上的知识')).assertEqual(AgentQueryScope.REMOTE_ONLY);
      expect(resolver.resolve('查询另一台可信设备')).assertEqual(AgentQueryScope.REMOTE_ONLY);
      expect(resolver.resolve('同时查询本机和其他设备')).assertEqual(AgentQueryScope.LOCAL_AND_REMOTE);
      expect(resolver.resolve('本地与跨设备一起查询')).assertEqual(AgentQueryScope.LOCAL_AND_REMOTE);
    });
  });
}
