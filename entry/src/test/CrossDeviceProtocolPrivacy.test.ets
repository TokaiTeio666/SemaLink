import { describe, expect, it } from '@ohos/hypium';
import { CrossDeviceEnvelope } from '../main/ets/crossdevice/protocol/CrossDeviceProtocolModels';
import { CrossDeviceProtocolCodec } from
  '../main/ets/crossdevice/protocol/CrossDeviceProtocolCodec';
import { TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';

class SafeQueryPayload {
  query: TaskRequest = {
    semanticContractVersion: '1.0', taskId: 't', queryText: 'safe question',
    requiredConcepts: ['safe'], requiredConfidence: 0.8, coverageThreshold: 0.8,
    latencyBudgetMs: 1000, byteBudget: 4096, privacyLevel: 'PRIVATE_GROUP',
    acceptableLevels: ['L1']
  };
  knowledgeDomain: string = 'safe';
}

class DocumentPayload {
  documentBody: string = 'full text';
}

function throws(action: () => void): boolean {
  try {
    action();
    return false;
  } catch (_) {
    return true;
  }
}

export default function crossDeviceProtocolPrivacyTest(): void {
  describe('CrossDeviceProtocolPrivacy', () => {
    it('rejects forbidden transport identifiers and storage details', 0, () => {
      const codec = new CrossDeviceProtocolCodec();
      const forbidden: string[] = [
        'networkId', 'deviceId', 'filePath', 'sql', 'databaseId',
        'documentIds', 'sourceDocId', 'sourceChunkId', 'evidenceId'
      ];
      forbidden.forEach((field: string): void => {
        const payload: Record<string, Object> = {};
        payload[field] = 'secret';
        const envelope = new CrossDeviceEnvelope(
          'QUERY_RESPONSE', 'm', 'r', 't', 'app', 1, 2, 0, payload
        );
        expect(throws((): void => { codec.encode(envelope); })).assertTrue();
      });
    });

    it('allows only bounded query text rather than document content', 0, () => {
      const codec = new CrossDeviceProtocolCodec();
      const allowed = new CrossDeviceEnvelope(
        'QUERY_REQUEST', 'm', 'r', 't', 'app', 1, 2, 0, new SafeQueryPayload()
      );
      expect(codec.encode(allowed).includes('safe question')).assertTrue();
      const forbidden = new CrossDeviceEnvelope(
        'QUERY_RESPONSE', 'm', 'r', 't', 'app', 1, 2, 0, new DocumentPayload()
      );
      expect(throws((): void => { codec.encode(forbidden); })).assertTrue();
    });
  });
}
