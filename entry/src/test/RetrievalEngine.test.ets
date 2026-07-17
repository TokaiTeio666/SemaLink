import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeError } from '../main/ets/contracts/knowledge/KnowledgeError';
import { PrivacyLevel } from '../main/ets/contracts/semantic/SemanticModels';
import { DocumentChunk } from '../main/ets/knowledge/model/DocumentChunk';
import { KnowledgeDocument } from '../main/ets/knowledge/model/KnowledgeDocument';
import { KeywordRetrievalEngine } from '../main/ets/knowledge/retrieval/KeywordRetrievalEngine';
import {
  KnowledgeRetrievalRequest,
  RetrievalEngine
} from '../main/ets/knowledge/retrieval/RetrievalEngine';

function document(id: string, privacyLevel: PrivacyLevel, tags: string[], updatedAt: number): KnowledgeDocument {
  return {
    documentId: id, title: 'Process scheduling ' + id, modality: 'text',
    normalizedText: 'process scheduling priority', tags: tags, checksum: 'sum-' + id,
    createdAt: updatedAt, updatedAt: updatedAt, privacyLevel: privacyLevel
  };
}

function chunk(id: string, documentId: string, index: number): DocumentChunk {
  return {
    chunkId: id, documentId: documentId, chunkIndex: index,
    text: 'process scheduling uses priority queues', summary: 'process scheduling', keywords: ['process'],
    startOffset: 0, endOffset: 38, updatedAt: 2
  };
}

function request(privacyLevel: PrivacyLevel): KnowledgeRetrievalRequest {
  return { queryText: 'process scheduling', topK: 20, privacyLevel: privacyLevel };
}

function capturedCode(action: () => void): string {
  try {
    action();
  } catch (error) {
    if (error instanceof KnowledgeError) {
      return error.code;
    }
  }
  return '';
}

export default function retrievalEngineTest() {
  describe('RetrievalEngine', () => {
    it('exposes keyword as the only implemented retrieval mode', 0, () => {
      const engine: RetrievalEngine = new KeywordRetrievalEngine();
      expect(engine.mode()).assertEqual('keyword');
    });

    it('applies the confirmed privacy matrix', 0, () => {
      const documents = [
        document('group', 'PRIVATE_GROUP', ['os'], 2),
        document('local', 'LOCAL_ONLY', ['os'], 2)
      ];
      const chunks = [chunk('c-group', 'group', 0), chunk('c-local', 'local', 0)];
      const engine = new KeywordRetrievalEngine();
      const localTask = engine.search(request('LOCAL_ONLY'), documents, chunks);
      const groupTask = engine.search(request('PRIVATE_GROUP'), documents, chunks);

      expect(localTask.length).assertEqual(2);
      expect(groupTask.length).assertEqual(1);
      expect(groupTask[0].document.documentId).assertEqual('group');
    });

    it('supports existing filters and preserves deterministic ordering', 0, () => {
      const documents = [
        document('b', 'PRIVATE_GROUP', ['os'], 3),
        document('a', 'PRIVATE_GROUP', ['os'], 2),
        document('old', 'PRIVATE_GROUP', ['other'], 1)
      ];
      const chunks = [chunk('c-b', 'b', 0), chunk('c-a', 'a', 0), chunk('c-old', 'old', 0)];
      const filtered: KnowledgeRetrievalRequest = {
        queryText: 'process scheduling', topK: 20, privacyLevel: 'PRIVATE_GROUP',
        filters: { documentIds: ['a', 'b'], tags: ['os'], modalities: ['text'], updatedAfter: 1 }
      };
      const engine = new KeywordRetrievalEngine();
      const first = engine.search(filtered, documents, chunks);
      const second = engine.search(filtered, documents, chunks);

      expect(first.length).assertEqual(2);
      expect(first[0].document.documentId).assertEqual('a');
      expect(JSON.stringify(first)).assertEqual(JSON.stringify(second));
    });

    it('rejects unknown formal modalities without exposing storage details', 0, () => {
      const invalid: KnowledgeRetrievalRequest = {
        queryText: 'process scheduling', topK: 20, privacyLevel: 'PRIVATE_GROUP',
        filters: { modalities: ['sql_column'] }
      };
      const code = capturedCode((): void => {
        new KeywordRetrievalEngine().search(invalid,
          [document('a', 'PRIVATE_GROUP', ['os'], 2)], [chunk('c-a', 'a', 0)]);
      });
      expect(code).assertEqual('E_FILTER_INVALID');
    });

    it('keeps the semantic retrieval candidate limit fixed at 20', 0, () => {
      const documents: KnowledgeDocument[] = [];
      const chunks: DocumentChunk[] = [];
      for (let index = 0; index < 25; index++) {
        const id = index.toString();
        documents.push(document('doc-' + id, 'PRIVATE_GROUP', ['os'], 2));
        chunks.push(chunk('chunk-' + id, 'doc-' + id, 0));
      }
      const semantic: KnowledgeRetrievalRequest = {
        queryText: 'process scheduling', topK: 20, privacyLevel: 'PRIVATE_GROUP'
      };
      const results = new KeywordRetrievalEngine().search(semantic, documents, chunks);
      expect(results.length).assertEqual(20);
    });

    it('uses chunkId as the final stable tie breaker', 0, () => {
      const documents = [document('doc', 'PRIVATE_GROUP', ['os'], 2)];
      const chunks = [chunk('chunk-b', 'doc', 0), chunk('chunk-a', 'doc', 0)];
      const results = new KeywordRetrievalEngine().search(request('PRIVATE_GROUP'), documents, chunks);
      expect(results[0].chunk.chunkId).assertEqual('chunk-a');
      expect(results[1].chunk.chunkId).assertEqual('chunk-b');
    });
  });
}
