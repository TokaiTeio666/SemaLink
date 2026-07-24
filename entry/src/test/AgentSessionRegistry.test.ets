import { describe, expect, it } from '@ohos/hypium';
import { SequenceIdGenerator } from '../main/ets/common/IdGenerator';
import { AgentSessionRegistry } from '../main/ets/agent/a2a/AgentSessionRegistry';

export default function agentSessionRegistryTest(): void {
  describe('AgentSessionRegistry', () => {
    it('creates and reuses a valid context', 0, () => {
      const registry: AgentSessionRegistry =
        new AgentSessionRegistry(new SequenceIdGenerator(), (): number => 1000, 60000, 8);
      const created: string = registry.resolve('connection-1', undefined);
      expect(created.length > 0).assertTrue();
      expect(registry.resolve('connection-1', created)).assertEqual(created);
    });

    it('rejects invalidated and unknown contexts', 0, () => {
      const registry: AgentSessionRegistry =
        new AgentSessionRegistry(new SequenceIdGenerator(), (): number => 1000, 60000, 8);
      const contextId: string = registry.resolve('connection-1', undefined);
      registry.invalidate(contextId);
      expect(registry.isValid(contextId)).assertFalse();
      expect(registry.isValid('missing')).assertFalse();
    });

    it('creates a fresh context when no id is supplied', 0, () => {
      const registry: AgentSessionRegistry =
        new AgentSessionRegistry(new SequenceIdGenerator(), (): number => 1000, 60000, 8);
      expect(registry.resolve('connection-1', undefined) === registry.resolve('connection-1', undefined)).assertFalse();
    });

    it('rejects capacity without evicting an active context', 0, () => {
      const registry: AgentSessionRegistry =
        new AgentSessionRegistry(new SequenceIdGenerator(), (): number => 1000, 60000, 1);
      const first: string = registry.resolve('connection-1', undefined);
      let rejected: boolean = false;
      try {
        registry.resolve('connection-1', undefined, [first]);
      } catch (_error) {
        rejected = true;
      }
      expect(rejected).assertTrue();
      expect(registry.resolve('connection-1', first)).assertEqual(first);
    });

    it('binds a context to its owning connection', 0, () => {
      const registry: AgentSessionRegistry =
        new AgentSessionRegistry(new SequenceIdGenerator(), (): number => 1000, 60000, 8);
      const contextId: string = registry.resolve('connection-a', undefined);
      let rejected: boolean = false;
      try {
        registry.resolve('connection-b', contextId);
      } catch (_error) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });

    it('evicts an unprotected old context instead of denying normal traffic', 0, () => {
      let now: number = 1000;
      const registry: AgentSessionRegistry =
        new AgentSessionRegistry(new SequenceIdGenerator(), (): number => now, 60000, 1);
      const first: string = registry.resolve('connection-1', undefined);
      now += 1;
      const second: string = registry.resolve('connection-1', undefined);
      expect(second === first).assertFalse();
      expect(registry.isValid(first)).assertFalse();
      expect(registry.isValid(second)).assertTrue();
    });
  });
}
