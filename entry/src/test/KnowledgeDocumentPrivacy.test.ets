import { describe, expect, it } from '@ohos/hypium';
import { PrivacyLevel } from '../main/ets/contracts/semantic/SemanticModels';
import { KnowledgeDocument } from '../main/ets/knowledge/model/KnowledgeDocument';

function document(privacyLevel: PrivacyLevel): KnowledgeDocument {
  return {
    documentId: 'doc-privacy', title: 'Privacy', modality: 'text', normalizedText: 'privacy document',
    tags: ['privacy'], checksum: 'sum-privacy', createdAt: 1, updatedAt: 1, privacyLevel: privacyLevel
  };
}

export default function knowledgeDocumentPrivacyTest() {
  describe('KnowledgeDocumentPrivacy', () => {
    it('requires the closed LOCAL_ONLY or PRIVATE_GROUP privacy level', 0, () => {
      expect(document('LOCAL_ONLY').privacyLevel).assertEqual('LOCAL_ONLY');
      expect(document('PRIVATE_GROUP').privacyLevel).assertEqual('PRIVATE_GROUP');
    });
  });
}
