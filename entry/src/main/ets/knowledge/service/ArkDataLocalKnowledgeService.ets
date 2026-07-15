import { KnowledgeError } from '../../contracts/knowledge/KnowledgeError';
import { LocalKnowledgeGateway } from '../../contracts/knowledge/LocalKnowledgeGateway';
import {
  KnowledgeProfile,
  LocalKnowledgeQuery,
  LocalKnowledgeResult
} from '../../contracts/knowledge/KnowledgeModels';
import {
  KnowledgePayloadValidator,
  validateKnowledgeRequest
} from '../../contracts/knowledge/KnowledgePayloadValidator';
import { L1PayloadBuilder } from '../payload/L1PayloadBuilder';
import { L2PayloadBuilder } from '../payload/L2PayloadBuilder';
import { BudgetedPayload } from '../payload/PayloadBudgetController';
import { KnowledgeProfileBuilder } from '../profile/KnowledgeProfileBuilder';
import { KeywordRetrievalEngine } from '../retrieval/KeywordRetrievalEngine';
import { DocumentRepository } from '../storage/DocumentRepository';

export class ArkDataLocalKnowledgeService implements LocalKnowledgeGateway {
  private readonly repository: DocumentRepository;
  private readonly retrieval: KeywordRetrievalEngine;
  private readonly l1Builder: L1PayloadBuilder;
  private readonly l2Builder: L2PayloadBuilder;
  private readonly profileBuilder: KnowledgeProfileBuilder;
  private readonly validator: KnowledgePayloadValidator;

  constructor(
    repository: DocumentRepository,
    retrieval: KeywordRetrievalEngine,
    l1Builder: L1PayloadBuilder,
    l2Builder: L2PayloadBuilder,
    profileBuilder: KnowledgeProfileBuilder,
    validator: KnowledgePayloadValidator
  ) {
    this.repository = repository;
    this.retrieval = retrieval;
    this.l1Builder = l1Builder;
    this.l2Builder = l2Builder;
    this.profileBuilder = profileBuilder;
    this.validator = validator;
  }

  async query(request: LocalKnowledgeQuery): Promise<LocalKnowledgeResult> {
    validateKnowledgeRequest(request);
    const startedAt = Date.now();
    try {
      const metadata = await this.repository.getMetadata();
      if (metadata.indexState === 'BUILDING') {
        throw new KnowledgeError('E_INDEX_NOT_READY', 'Local knowledge index is still building', true, 500);
      }
      if (metadata.indexState === 'ERROR') {
        throw new KnowledgeError('E_RETRIEVAL_FAILED', 'Local knowledge index is unavailable', true);
      }
      const documents = await this.repository.listDocuments();
      const chunks = await this.repository.listChunks();
      const candidates = this.retrieval.search(request, documents, chunks);
      let payload: BudgetedPayload;
      if (request.requestedLevel === 'L1') {
        payload = this.l1Builder.build(candidates, request.maxPayloadBytes);
      } else {
        payload = this.l2Builder.build(candidates, request.maxPayloadBytes);
      }
      const result: LocalKnowledgeResult = {
        contractVersion: '1.0',
        requestId: request.requestId,
        level: request.requestedLevel,
        itemCount: payload.itemCount,
        payloadJson: payload.payloadJson,
        truncated: payload.truncated,
        retrievalMs: Date.now() - startedAt,
        indexVersion: metadata.indexVersion,
        generatedAt: Date.now()
      };
      this.validator.validateResult(request, result);
      return result;
    } catch (error) {
      if (error instanceof KnowledgeError) {
        throw error;
      }
      throw new KnowledgeError('E_RETRIEVAL_FAILED', 'Local knowledge retrieval failed', true);
    }
  }

  async getKnowledgeProfile(): Promise<KnowledgeProfile> {
    try {
      const statistics = await this.repository.getStatistics();
      const metadata = await this.repository.getMetadata();
      const profile = this.profileBuilder.buildProfile(statistics, metadata);
      this.validator.validateProfile(profile);
      return profile;
    } catch (error) {
      if (error instanceof KnowledgeError) {
        throw error;
      }
      throw new KnowledgeError('E_RETRIEVAL_FAILED', 'Unable to read the local knowledge profile', true);
    }
  }
}
