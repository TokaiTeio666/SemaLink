import { describe, expect, it } from '@ohos/hypium';
import { CrossDeviceEnvelope } from '../main/ets/crossdevice/protocol/CrossDeviceProtocolModels';
import { CrossDeviceProtocolCodec } from
  '../main/ets/crossdevice/protocol/CrossDeviceProtocolCodec';
import { TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';

class ShortQueryPayload {
  query: TaskRequest = {
    semanticContractVersion: '1.0', taskId: 't', queryText: 'domain',
    requiredConcepts: ['domain'], requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: 4096, privacyLevel: 'PRIVATE_GROUP',
    acceptableLevels: ['L1']
  };
  knowledgeDomain: string = 'domain';
}

class MismatchedQueryPayload {
  query: TaskRequest = {
    semanticContractVersion: '1.0', taskId: 'payload-task', queryText: 'domain',
    requiredConcepts: ['domain'], requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: 4096, privacyLevel: 'PRIVATE_GROUP',
    acceptableLevels: ['L1']
  };
  knowledgeDomain: string = 'domain';
}

function throws(action: () => void): boolean {
  try {
    action();
    return false;
  } catch (_) {
    return true;
  }
}

export default function crossDeviceProtocolLimitsTest(): void {
  describe('CrossDeviceProtocolLimits', () => {
    it('rejects a logical message larger than 64 KiB', 0, () => {
      const codec = new CrossDeviceProtocolCodec();
      const oversizedJson: string = '{"padding":"' + 'x'.repeat(65536) + '"}';
      expect(throws((): void => { codec.decode(oversizedJson); })).assertTrue();
    });

    it('rejects expired messages', 0, () => {
      const codec = new CrossDeviceProtocolCodec();
      const text = JSON.stringify(new CrossDeviceEnvelope(
        'QUERY_REQUEST', 'm', 'r', 't', 'app', 1, 2, 0, new ShortQueryPayload()
      ));
      expect(throws((): void => { codec.decode(text, 3); })).assertTrue();
    });

    it('binds payload task identity to the envelope task identity', 0, () => {
      const codec = new CrossDeviceProtocolCodec();
      const envelope = new CrossDeviceEnvelope(
        'QUERY_REQUEST', 'm', 'r', 'envelope-task', 'app', 1, 2, 0,
        new MismatchedQueryPayload()
      );
      expect(throws((): void => { codec.encode(envelope); })).assertTrue();
    });
  });
}
