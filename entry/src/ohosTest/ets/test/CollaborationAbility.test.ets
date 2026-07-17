import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { AvailableDeviceProvider, TrustedDeviceResolver } from
  '../../../main/ets/communication/TrustedDeviceResolver';
import { PeerDevice } from '../../../main/ets/model/AppModels';
import { ProtocolCodec } from '../../../main/ets/protocol/ProtocolCodec';
import { ProtocolEnvelope } from '../../../main/ets/protocol/ProtocolModels';
import { AppRuntime } from '../../../main/ets/runtime/AppRuntime';
import { MockSummaryService } from '../../../main/ets/task/MockSummaryService';
import { FakeTransport } from '../../../test/support/FakeTransport';

const TEST_PEER: PeerDevice = {
  deviceId: 'controlled-peer', deviceName: 'Controlled Peer', deviceType: 'tablet'
};

class ControlledDeviceProvider implements AvailableDeviceProvider {
  list(): Promise<Array<PeerDevice>> {
    return Promise.resolve([TEST_PEER]);
  }

  release(): void {
  }
}

export default function collaborationAbilityTest(): void {
  describe('CollaborationAbility', () => {
    it('connectsAndCompletesMinimalQuery', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const transport = new FakeTransport();
      const runtime = new AppRuntime(ability.context, {
        transport: transport,
        resolverFactory: () => new TrustedDeviceResolver(new ControlledDeviceProvider())
      });
      const codec = new ProtocolCodec();
      const question = 'Task 9 lifecycle probe';
      try {
        runtime.coordinator.selectInitiator();
        await runtime.coordinator.connect();
        transport.emitConnected();
        const pending = runtime.coordinator.submit(question);
        const query: ProtocolEnvelope = codec.decode(transport.sentMessages[0]);
        transport.emitMessage(codec.encode(codec.createAck(
          'ack-1', query.sessionId, query.requestId, Date.now(), { acceptedAt: Date.now() }
        )));
        const summary = new MockSummaryService().generate(question);
        transport.emitMessage(codec.encode(codec.createResult(
          'result-1', query.sessionId, query.requestId, Date.now(),
          { summary: summary, sourceDeviceAlias: 'Controlled Peer', processingMs: 1 }
        )));
        await pending;
        expect(runtime.store.snapshot().summary).assertEqual(summary);
        await runtime.coordinator.disconnect();
      } finally {
        runtime.destroy();
        AppRuntime.reset();
      }
    });
  });
}
