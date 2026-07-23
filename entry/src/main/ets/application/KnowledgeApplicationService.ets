import { Context } from '@kit.AbilityKit';
import { KnowledgeError } from '../contracts/knowledge/KnowledgeError';
import { LocalKnowledgeGateway } from '../contracts/knowledge/LocalKnowledgeGateway';
import { SemanticKnowledgeProvider } from '../contracts/semantic/SemanticKnowledgeProvider';
import { EvidenceUnit, TaskRequest } from '../contracts/semantic/SemanticModels';
import {
  ImportReport,
  KnowledgeProfile,
  LocalKnowledgeQuery,
  LocalKnowledgeResult
} from '../contracts/knowledge/KnowledgeModels';
import { RawFileDocumentImporter } from '../knowledge/import/RawFileDocumentImporter';
import { UserDocumentImportCoordinator } from '../knowledge/import/UserDocumentImportCoordinator';
import { DocumentRepository } from '../knowledge/storage/DocumentRepository';
import { KnowledgeDatabase } from '../knowledge/storage/KnowledgeDatabase';
import { KnowledgeComponents, KnowledgeCompositionRoot } from './KnowledgeCompositionRoot';

export class KnowledgeApplicationService implements LocalKnowledgeGateway, SemanticKnowledgeProvider {
  private gateway?: LocalKnowledgeGateway;
  private provider?: SemanticKnowledgeProvider;
  private importer?: RawFileDocumentImporter;
  private userImporter?: UserDocumentImportCoordinator;
  private repository?: DocumentRepository;
  private database?: KnowledgeDatabase;
  private initialization?: Promise<void>;
  private destroyed: boolean = false;

  async initialize(context: Context, sourceDeviceId: string = 'local-device'): Promise<void> {
    if (this.destroyed) {
      throw this.notInitialized();
    }
    if (this.database !== undefined) {
      return;
    }
    if (this.initialization === undefined) {
      this.initialization = this.initializeComponents(context, sourceDeviceId)
        .catch((error: Object): Promise<void> => {
          this.initialization = undefined;
          return Promise.reject(error);
        });
    }
    await this.initialization;
  }

  private async initializeComponents(context: Context, sourceDeviceId: string): Promise<void> {
    const components: KnowledgeComponents = await KnowledgeCompositionRoot.create(context, sourceDeviceId);
    if (this.destroyed) {
      components.database.close();
      throw this.notInitialized();
    }
    this.gateway = components.gateway;
    this.provider = components.provider;
    this.importer = components.importer;
    this.userImporter = components.userImporter;
    this.repository = components.repository;
    this.database = components.database;
  }

  async importBuiltInDocuments(): Promise<ImportReport> {
    if (this.importer === undefined) {
      throw this.notInitialized();
    }
    return this.importer.importBuiltInDocuments();
  }

  async selectAndImportTextDocuments(): Promise<ImportReport> {
    if (this.userImporter === undefined) {
      throw this.notInitialized();
    }
    return this.userImporter.selectAndImport();
  }

  async clearKnowledgeBase(): Promise<void> {
    if (this.repository === undefined) {
      throw this.notInitialized();
    }
    await this.repository.clearAll();
  }

  async query(request: LocalKnowledgeQuery): Promise<LocalKnowledgeResult> {
    if (this.initialization !== undefined) {
      await this.initialization;
    }
    if (this.gateway === undefined) {
      throw this.notInitialized();
    }
    return this.gateway.query(request);
  }

  async getKnowledgeProfile(): Promise<KnowledgeProfile> {
    if (this.initialization !== undefined) {
      await this.initialization;
    }
    if (this.gateway === undefined) {
      throw this.notInitialized();
    }
    return this.gateway.getKnowledgeProfile();
  }

  async searchEvidence(task: TaskRequest): Promise<EvidenceUnit[]> {
    if (this.initialization !== undefined) {
      await this.initialization;
    }
    if (this.provider === undefined) {
      throw this.notInitialized();
    }
    return this.provider.searchEvidence(task);
  }

  async getProfile(): Promise<KnowledgeProfile> {
    if (this.initialization !== undefined) {
      await this.initialization;
    }
    if (this.provider === undefined) {
      throw this.notInitialized();
    }
    return this.provider.getProfile();
  }

  destroy(): void {
    if (this.destroyed) {
      return;
    }
    this.destroyed = true;
    const database = this.database;
    this.gateway = undefined;
    this.provider = undefined;
    this.importer = undefined;
    this.userImporter = undefined;
    this.repository = undefined;
    this.database = undefined;
    if (database !== undefined) {
      database.close();
    }
  }

  private notInitialized(): KnowledgeError {
    return new KnowledgeError('E_INDEX_NOT_READY', 'Local knowledge service is not initialized', true);
  }
}
