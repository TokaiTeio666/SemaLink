import { describe, expect, it } from '@ohos/hypium';
import {
  AgentAuthorizationCoordinator
} from '../main/ets/agent/AgentAuthorizationCoordinator';

class FakeAuthorizationProxy {
  received: string = '';
  shouldThrow: boolean = false;
  authorize(handshakeData: string): void {
    if (this.shouldThrow) throw new Error('controlled authorization failure');
    this.received = handshakeData;
  }
}

export default function agentAuthorizationContractTest(): void {
  describe('AgentAuthorizationContract', () => {
    it('passes bounded SDK negotiation data unchanged to synchronous authorize', 0, () => {
      const proxy: FakeAuthorizationProxy = new FakeAuthorizationProxy();
      const coordinator: AgentAuthorizationCoordinator = new AgentAuthorizationCoordinator();
      const handshake: string = '{"opaque":"sdk-owned-value"}';
      expect(coordinator.authorize(handshake, (data: string): void => proxy.authorize(data))).assertTrue();
      expect(proxy.received).assertEqual(handshake);
    });

    it('rejects empty and oversized input and contains proxy exceptions', 0, () => {
      const proxy: FakeAuthorizationProxy = new FakeAuthorizationProxy();
      const coordinator: AgentAuthorizationCoordinator = new AgentAuthorizationCoordinator();
      expect(coordinator.authorize('', (data: string): void => proxy.authorize(data))).assertFalse();
      expect(coordinator.authorize('x'.repeat(16 * 1024 + 1),
        (data: string): void => proxy.authorize(data))).assertFalse();
      proxy.shouldThrow = true;
      expect(coordinator.authorize('opaque', (data: string): void => proxy.authorize(data))).assertFalse();
    });
  });
}
