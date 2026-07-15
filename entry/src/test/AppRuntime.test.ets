import { describe, expect, it } from '@ohos/hypium';
import { AppRuntime } from '../main/ets/runtime/AppRuntime';
import { Transport, TransportListener } from '../main/ets/communication/Transport';
import { PeerDevice } from '../main/ets/model/AppModels';

class CountingTransport implements Transport {
  listener: TransportListener | null = null;
  destroyCalls: number = 0;

  setListener(listener: TransportListener): void { this.listener = listener; }
  connect(_peer: PeerDevice): Promise<void> { return Promise.resolve(); }
  accept(_wantParam: Record<string, Object>): boolean { return true; }
  send(_text: string): Promise<void> { return Promise.resolve(); }
  disconnect(): Promise<void> { return Promise.resolve(); }
  destroy(): void { this.destroyCalls += 1; }
  isConnected(): boolean { return false; }
}

interface FakeApplicationInfo {
  name: string;
}

interface FakeContext {
  applicationInfo: FakeApplicationInfo;
}

function fakeContext(): FakeContext {
  return { applicationInfo: { name: 'com.example.semalink' } };
}

export default function appRuntimeTest(): void {
  describe('AppRuntime', () => {
    it('initializesTheSingletonOnlyOnce', 0, () => {
      AppRuntime.reset();
      const first: AppRuntime = AppRuntime.initialize(fakeContext() as never);
      const second: AppRuntime = AppRuntime.initialize(fakeContext() as never);
      expect(first).assertEqual(second);
      AppRuntime.reset();
    });

    it('acceptsCollaborationAsResponder', 0, () => {
      const transport = new CountingTransport();
      const runtime = new AppRuntime(fakeContext() as never, { transport: transport });
      expect(runtime.coordinator.acceptCollaboration({})).assertTrue();
      expect(runtime.store.snapshot().role).assertEqual('RESPONDER');
      runtime.destroy();
    });

    it('destroysOnlyOnce', 0, () => {
      const transport = new CountingTransport();
      const runtime = new AppRuntime(fakeContext() as never, { transport: transport });
      runtime.destroy();
      runtime.destroy();
      expect(transport.destroyCalls).assertEqual(1);
    });
  });
}
