import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeError } from '../main/ets/contracts/knowledge/KnowledgeError';
import { LocalKnowledgeGateway } from '../main/ets/contracts/knowledge/LocalKnowledgeGateway';
import { SemanticKnowledgeProvider } from '../main/ets/contracts/semantic/SemanticKnowledgeProvider';
import { KnowledgeModality } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { TaskRequest } from '../main/ets/contracts/semantic/SemanticModels';
import { EvidenceUnitFactory } from '../main/ets/knowledge/evidence/EvidenceUnitFactory';
import { DocumentChunk } from '../main/ets/knowledge/model/DocumentChunk';
import { KnowledgeDocument } from '../main/ets/knowledge/model/KnowledgeDocument';
import { L1PayloadBuilder } from '../main/ets/knowledge/payload/L1PayloadBuilder';
import { L2PayloadBuilder } from '../main/ets/knowledge/payload/L2PayloadBuilder';
import { KnowledgeProfileBuilder } from '../main/ets/knowledge/profile/KnowledgeProfileBuilder';
import { KeywordRetrievalEngine } from '../main/ets/knowledge/retrieval/KeywordRetrievalEngine';
import {
  KnowledgeRetrievalRequest,
  RETRIEVAL_CANDIDATE_LIMIT,
  RetrievalEngine
} from '../main/ets/knowledge/retrieval/RetrievalEngine';
import { RetrievalCandidate } from '../main/ets/knowledge/model/RetrievalCandidate';
import { ArkDataLocalKnowledgeService } from '../main/ets/knowledge/service/ArkDataLocalKnowledgeService';
import {
  DocumentRepository,
  KnowledgeMetadata,
  RepositoryStatistics
} from '../main/ets/knowledge/storage/DocumentRepository';
import { KnowledgePayloadValidator } from '../main/ets/contracts/knowledge/KnowledgePayloadValidator';
import { KnowledgeApplicationService } from '../main/ets/application/KnowledgeApplicationService';
import { LocalKnowledgeQuery } from '../main/ets/contracts/knowledge/KnowledgeModels';

class ProviderRepository implements DocumentRepository {
  documents: KnowledgeDocument[];
  chunks: DocumentChunk[];
  metadata: KnowledgeMetadata;
  failureKind: '' | 'storage' | 'unknown' = '';

  constructor(state: 'EMPTY' | 'BUILDING' | 'READY' | 'ERROR' = 'READY') {
    this.documents = [{
      documentId: 'doc-os', title: '进程调度', modality: 'text',
      normalizedText: '进程调度使用优先级队列', tags: ['操作系统', '调度'], checksum: 'sum-os',
      createdAt: 1, updatedAt: 10, privacyLevel: 'PRIVATE_GROUP'
    }];
    this.chunks = [{
      chunkId: 'chunk-os', documentId: 'doc-os', chunkIndex: 0,
      text: '进程调度使用优先级队列，老化可以避免任务饥饿。', summary: '进程调度与老化',
      keywords: ['进程调度', '优先级队列', '老化'], startOffset: 0, endOffset: 27, updatedAt: 10
    }];
    this.metadata = {
      indexState: state, indexVersion: 'index-real-7', profileVersion: 'profile-real-7', updatedAt: 10
    };
    if (state === 'EMPTY') {
      this.documents = [];
      this.chunks = [];
    }
  }

  async saveDocumentWithChunks(document: KnowledgeDocument, chunks: DocumentChunk[]): Promise<void> {}
  async hasChecksum(checksum: string): Promise<boolean> { return false; }
  async clearAll(): Promise<void> {}
  async setMetadata(metadata: KnowledgeMetadata): Promise<void> { this.metadata = metadata; }

  async listDocuments(): Promise<KnowledgeDocument[]> {
    this.throwIfFailed();
    return this.documents.slice();
  }

  async listChunks(): Promise<DocumentChunk[]> {
    this.throwIfFailed();
    return this.chunks.slice();
  }

  async getStatistics(): Promise<RepositoryStatistics> {
    this.throwIfFailed();
    const modalities: KnowledgeModality[] = this.documents.length === 0 ? [] : ['text'];
    return {
      documentCount: this.documents.length, chunkCount: this.chunks.length, modalities: modalities,
      domainCounts: this.documents.length === 0 ? [] : [
        { tag: '操作系统', documentCount: 1 }, { tag: '调度', documentCount: 1 }
      ]
    };
  }

  async getMetadata(): Promise<KnowledgeMetadata> {
    this.throwIfFailed();
    return this.metadata;
  }

  private throwIfFailed(): void {
    if (this.failureKind === 'storage') {
      throw new KnowledgeError('E_STORAGE_FAILED', 'safe storage failure', true);
    }
    if (this.failureKind === 'unknown') {
      throw new Error('SQL file:///private/source stack');
    }
  }
}

class RecordingRetrievalEngine implements RetrievalEngine {
  lastRequest?: KnowledgeRetrievalRequest;

  mode(): 'keyword' {
    return 'keyword';
  }

  search(request: KnowledgeRetrievalRequest, documents: KnowledgeDocument[], chunks: DocumentChunk[]):
    RetrievalCandidate[] {
    this.lastRequest = request;
    const candidates: RetrievalCandidate[] = [];
    const count: number = Math.min(documents.length, chunks.length, request.topK);
    for (let index = 0; index < count; index++) {
      candidates.push({
        document: documents[index], chunk: chunks[index], relevance: 1,
        matchedPrimaryTerms: [request.queryText], matchedNgrams: [], exactPhraseMatched: true
      });
    }
    return candidates;
  }
}

function provider(repository: DocumentRepository, sourceDeviceId: string = 'test-device',
  retrieval: RetrievalEngine = new KeywordRetrievalEngine()):
  ArkDataLocalKnowledgeService {
  return new ArkDataLocalKnowledgeService(
    repository, retrieval, new L1PayloadBuilder(), new L2PayloadBuilder(),
    new KnowledgeProfileBuilder(), new KnowledgePayloadValidator(), new EvidenceUnitFactory(), sourceDeviceId
  );
}

function task(): TaskRequest {
  return {
    semanticContractVersion: '1.0', taskId: 'provider-task', queryText: '进程调度优先级队列',
    requiredConcepts: ['进程调度', '优先级队列'], requiredConfidence: 1, coverageThreshold: 1,
    latencyBudgetMs: 1, byteBudget: 1, privacyLevel: 'PRIVATE_GROUP', acceptableLevels: ['L1', 'L2']
  };
}

async function capturedError(action: () => Promise<void>): Promise<KnowledgeError | undefined> {
  try {
    await action();
  } catch (error) {
    if (error instanceof KnowledgeError) {
      return error;
    }
  }
  return undefined;
}

export default function semanticKnowledgeProviderTest(): void {
  describe('SemanticKnowledgeProvider', () => {
    it('builds profile from repository statistics and metadata', 0, async () => {
      const profile = await provider(new ProviderRepository()).getProfile();
      expect(profile.documentCount).assertEqual(1);
      expect(profile.chunkCount).assertEqual(1);
      expect(profile.indexVersion).assertEqual('index-real-7');
      expect(profile.profileVersion).assertEqual('profile-real-7');
      expect(JSON.stringify(profile.modalities)).assertEqual(JSON.stringify(['text']));
      expect(JSON.stringify(profile.retrievalModes)).assertEqual(JSON.stringify(['keyword']));
      expect(JSON.stringify(profile.supportedLevels)).assertEqual(JSON.stringify(['L1', 'L2']));
      expect(profile.embeddingModelVersion).assertEqual('');
    });

    it('reports EMPTY BUILDING READY and ERROR profiles from real metadata semantics', 0, async () => {
      const empty = await provider(new ProviderRepository('EMPTY')).getProfile();
      const building = await provider(new ProviderRepository('BUILDING')).getProfile();
      const ready = await provider(new ProviderRepository('READY')).getProfile();
      const failed = await provider(new ProviderRepository('ERROR')).getProfile();
      expect(empty.indexState).assertEqual('EMPTY');
      expect(building.indexState).assertEqual('BUILDING');
      expect(ready.indexState).assertEqual('READY');
      expect(failed.indexState).assertEqual('ERROR');
    });

    it('returns stable real L1 and L2 evidence with injected source device', 0, async () => {
      const service = provider(new ProviderRepository(), 'injected-device');
      const first = await service.searchEvidence(task());
      const second = await service.searchEvidence(task());
      expect(first.length).assertEqual(2);
      expect(first[0].level).assertEqual('L1');
      expect(first[1].level).assertEqual('L2');
      expect(first[1].parentEvidenceId).assertEqual(first[0].evidenceId);
      expect(first[0].sourceDeviceId).assertEqual('injected-device');
      expect(JSON.stringify(first)).assertEqual(JSON.stringify(second));
    });

    it('adapts legacy gateway requests to LOCAL_ONLY while preserving caller topK', 0, async () => {
      const retrieval = new RecordingRetrievalEngine();
      const service = provider(new ProviderRepository(), 'test-device', retrieval);
      const legacy: LocalKnowledgeQuery = {
        contractVersion: '1.0', requestId: 'legacy-top-k', queryText: 'process scheduling', topK: 1,
        requestedLevel: 'L2', maxPayloadBytes: 4096
      };
      const result = await service.query(legacy);
      expect(retrieval.lastRequest?.queryText).assertEqual(legacy.queryText);
      expect(retrieval.lastRequest?.topK).assertEqual(1);
      expect(retrieval.lastRequest?.privacyLevel).assertEqual('LOCAL_ONLY');
      expect(result.itemCount).assertEqual(1);
      expect(result.level).assertEqual('L2');
    });

    it('passes the shared fixed candidate limit to provider retrieval', 0, async () => {
      const retrieval = new RecordingRetrievalEngine();
      await provider(new ProviderRepository(), 'test-device', retrieval).searchEvidence(task());
      expect(retrieval.lastRequest?.topK).assertEqual(RETRIEVAL_CANDIDATE_LIMIT);
      expect(retrieval.lastRequest?.privacyLevel).assertEqual('PRIVATE_GROUP');
    });

    it('does not prune provider evidence using task budgets or confidence', 0, async () => {
      const request = task();
      request.byteBudget = 1;
      request.latencyBudgetMs = 1;
      request.requiredConfidence = 1;
      request.coverageThreshold = 1;
      expect((await provider(new ProviderRepository()).searchEvidence(request)).length).assertEqual(2);
    });

    it('maps BUILDING ERROR and EMPTY metadata deterministically', 0, async () => {
      const building = await capturedError(async (): Promise<void> => {
        await provider(new ProviderRepository('BUILDING')).searchEvidence(task());
      });
      const failed = await capturedError(async (): Promise<void> => {
        await provider(new ProviderRepository('ERROR')).searchEvidence(task());
      });
      const empty = await provider(new ProviderRepository('EMPTY')).searchEvidence(task());
      expect(building?.code).assertEqual('E_INDEX_NOT_READY');
      expect(failed?.code).assertEqual('E_RETRIEVAL_FAILED');
      expect(empty.length).assertEqual(0);
    });

    it('converts null undefined missing and malformed runtime tasks to KnowledgeError', 0, async () => {
      const service = provider(new ProviderRepository());
      const values: TaskRequest[] = [JSON.parse('null') as TaskRequest, JSON.parse('{}') as TaskRequest,
        JSON.parse('{"semanticContractVersion":"1.0","filters":null}') as TaskRequest];
      for (const value of values) {
        const error = await capturedError(async (): Promise<void> => {
          await service.searchEvidence(value);
        });
        expect(error === undefined).assertFalse();
        expect(error?.code).assertEqual('E_QUERY_INVALID');
      }
      let unset: TaskRequest | undefined = undefined;
      const undefinedError = await capturedError(async (): Promise<void> => {
        await service.searchEvidence(unset!);
      });
      expect(undefinedError?.code).assertEqual('E_QUERY_INVALID');
    });

    it('rejects unsupported semantic versions at the provider boundary', 0, async () => {
      const invalid = task();
      invalid.semanticContractVersion = '9.0' as '1.0';
      const error = await capturedError(async (): Promise<void> => {
        await provider(new ProviderRepository()).searchEvidence(invalid);
      });
      expect(error?.code).assertEqual('E_CONTRACT_VERSION_UNSUPPORTED');
    });

    it('preserves storage failures and safely maps unknown failures', 0, async () => {
      const storage = new ProviderRepository();
      storage.failureKind = 'storage';
      const storageError = await capturedError(async (): Promise<void> => {
        await provider(storage).searchEvidence(task());
      });
      const unknown = new ProviderRepository();
      unknown.failureKind = 'unknown';
      const unknownError = await capturedError(async (): Promise<void> => {
        await provider(unknown).searchEvidence(task());
      });
      expect(storageError?.code).assertEqual('E_STORAGE_FAILED');
      expect(unknownError?.code).assertEqual('E_RETRIEVAL_FAILED');
      expect(unknownError?.message.includes('SQL')).assertFalse();
      expect(unknownError?.message.includes('file:')).assertFalse();
      expect(unknownError?.message.includes('stack')).assertFalse();
    });

    it('returns an empty list when retrieval has no match', 0, async () => {
      const request = task();
      request.queryText = '量子引力黑洞蒸发';
      expect((await provider(new ProviderRepository()).searchEvidence(request)).length).assertEqual(0);
    });

    it('keeps old and new application interfaces safely unavailable before initialization', 0, async () => {
      const service = new KnowledgeApplicationService();
      const legacyGateway: LocalKnowledgeGateway = service;
      const semanticProvider: SemanticKnowledgeProvider = service;
      expect(legacyGateway === service).assertTrue();
      expect(semanticProvider === service).assertTrue();
      const legacy: LocalKnowledgeQuery = {
        contractVersion: '1.0', requestId: 'legacy-uninitialized', queryText: 'process', topK: 1,
        requestedLevel: 'L1', maxPayloadBytes: 1024
      };
      const errors: (KnowledgeError | undefined)[] = [];
      errors.push(await capturedError(async (): Promise<void> => { await service.getProfile(); }));
      errors.push(await capturedError(async (): Promise<void> => { await service.searchEvidence(task()); }));
      errors.push(await capturedError(async (): Promise<void> => { await service.getKnowledgeProfile(); }));
      errors.push(await capturedError(async (): Promise<void> => { await service.query(legacy); }));
      for (const error of errors) {
        expect(error?.code).assertEqual('E_INDEX_NOT_READY');
      }
      service.destroy();
    });
  });
}
