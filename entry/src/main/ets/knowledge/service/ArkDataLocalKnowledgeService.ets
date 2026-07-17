import { KnowledgeError } from '../../contracts/knowledge/KnowledgeError';
import { LocalKnowledgeGateway } from '../../contracts/knowledge/LocalKnowledgeGateway';
import { SemanticKnowledgeProvider } from '../../contracts/semantic/SemanticKnowledgeProvider';
import {
  EvidenceUnit,
  TaskRequest,
  TaskRequestFilters,
  validateTaskRequest
} from '../../contracts/semantic/SemanticModels';
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
import { EvidenceUnitFactory } from '../evidence/EvidenceUnitFactory';
import { KnowledgeProfileBuilder } from '../profile/KnowledgeProfileBuilder';
import {
  KnowledgeRetrievalRequest,
  RETRIEVAL_CANDIDATE_LIMIT,
  RetrievalEngine
} from '../retrieval/RetrievalEngine';
import { DocumentRepository } from '../storage/DocumentRepository';

function validateProviderTask(task: TaskRequest): void {
  try {
    if (task === null || task === undefined || typeof task !== 'object') {
      throw new KnowledgeError('E_QUERY_INVALID', 'Semantic task fields are invalid', false);
    }
    if (typeof task.semanticContractVersion !== 'string') {
      throw new KnowledgeError('E_QUERY_INVALID', 'Semantic task fields are invalid', false);
    }
    validateTaskRequest(task);
  } catch (error) {
    if (error instanceof KnowledgeError) {
      throw error;
    }
    throw new KnowledgeError('E_QUERY_INVALID', 'Semantic task fields are invalid', false);
  }
}

function toRetrievalFilters(request: LocalKnowledgeQuery): TaskRequestFilters | undefined {
  if (request.filters === undefined) {
    return undefined;
  }
  const filters: TaskRequestFilters = {
    documentIds: request.filters.documentIds,
    tags: request.filters.tags,
    modalities: request.filters.modalities,
    updatedAfter: request.filters.updatedAfter
  };
  return filters;
}

export class ArkDataLocalKnowledgeService implements LocalKnowledgeGateway, SemanticKnowledgeProvider {
  private readonly repository: DocumentRepository;
  private readonly retrieval: RetrievalEngine;
  private readonly l1Builder: L1PayloadBuilder;
  private readonly l2Builder: L2PayloadBuilder;
  private readonly profileBuilder: KnowledgeProfileBuilder;
  private readonly validator: KnowledgePayloadValidator;
  private readonly evidenceFactory: EvidenceUnitFactory;
  private readonly sourceDeviceId: string;

  constructor(
    repository: DocumentRepository,
    retrieval: RetrievalEngine,
    l1Builder: L1PayloadBuilder,
    l2Builder: L2PayloadBuilder,
    profileBuilder: KnowledgeProfileBuilder,
    validator: KnowledgePayloadValidator,
    evidenceFactory: EvidenceUnitFactory = new EvidenceUnitFactory(),
    sourceDeviceId: string = 'local-device'
  ) {
    this.repository = repository;
    this.retrieval = retrieval;
    this.l1Builder = l1Builder;
    this.l2Builder = l2Builder;
    this.profileBuilder = profileBuilder;
    this.validator = validator;
    this.evidenceFactory = evidenceFactory;
    this.sourceDeviceId = sourceDeviceId;
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
      const retrievalRequest: KnowledgeRetrievalRequest = {
        queryText: request.queryText,
        topK: request.topK,
        privacyLevel: 'LOCAL_ONLY',
        filters: toRetrievalFilters(request)
      };
      const candidates = this.retrieval.search(retrievalRequest, documents, chunks);
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

  async getProfile(): Promise<KnowledgeProfile> {
    return this.getKnowledgeProfile();
  }

  async searchEvidence(task: TaskRequest): Promise<EvidenceUnit[]> {
    validateProviderTask(task);
    try {
      const metadata = await this.repository.getMetadata();
      if (metadata.indexState === 'BUILDING') {
        throw new KnowledgeError('E_INDEX_NOT_READY', 'Local knowledge index is still building', true, 500);
      }
      if (metadata.indexState === 'ERROR') {
        throw new KnowledgeError('E_RETRIEVAL_FAILED', 'Local knowledge index is unavailable', true);
      }
      if (metadata.indexState === 'EMPTY') {
        return [];
      }
      const documents = await this.repository.listDocuments();
      const chunks = await this.repository.listChunks();
      const candidates = this.retrieval.search({
        queryText: task.queryText,
        topK: RETRIEVAL_CANDIDATE_LIMIT,
        privacyLevel: task.privacyLevel,
        filters: task.filters
      }, documents, chunks);
      return this.evidenceFactory.build(candidates, task, this.sourceDeviceId);
    } catch (error) {
      if (error instanceof KnowledgeError) {
        throw error;
      }
      throw new KnowledgeError('E_RETRIEVAL_FAILED', 'Local knowledge evidence retrieval failed', true);
    }
  }
}
