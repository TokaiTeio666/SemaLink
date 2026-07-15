import { Context } from '@kit.AbilityKit';
import { KnowledgeError } from '../contracts/knowledge/KnowledgeError';
import { LocalKnowledgeGateway } from '../contracts/knowledge/LocalKnowledgeGateway';
import {
  ImportReport,
  KnowledgeProfile,
  LocalKnowledgeQuery,
  LocalKnowledgeResult
} from '../contracts/knowledge/KnowledgeModels';
import { RawFileDocumentImporter } from '../knowledge/import/RawFileDocumentImporter';
import { UserDocumentImportCoordinator } from '../knowledge/import/UserDocumentImportCoordinator';
import { DocumentRepository } from '../knowledge/storage/DocumentRepository';
import { KnowledgeComponents, KnowledgeCompositionRoot } from './KnowledgeCompositionRoot';

export class KnowledgeApplicationService {
  private gateway?: LocalKnowledgeGateway;
  private importer?: RawFileDocumentImporter;
  private userImporter?: UserDocumentImportCoordinator;
  private repository?: DocumentRepository;

  async initialize(context: Context): Promise<void> {
    const components: KnowledgeComponents = await KnowledgeCompositionRoot.create(context);
    this.gateway = components.gateway;
    this.importer = components.importer;
    this.userImporter = components.userImporter;
    this.repository = components.repository;
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
    if (this.gateway === undefined) {
      throw this.notInitialized();
    }
    return this.gateway.query(request);
  }

  async getKnowledgeProfile(): Promise<KnowledgeProfile> {
    if (this.gateway === undefined) {
      throw this.notInitialized();
    }
    return this.gateway.getKnowledgeProfile();
  }

  private notInitialized(): KnowledgeError {
    return new KnowledgeError('E_INDEX_NOT_READY', 'Local knowledge service is not initialized', true);
  }
}
