import { Context } from '@kit.AbilityKit';
import { LocalKnowledgeGateway } from '../contracts/knowledge/LocalKnowledgeGateway';
import { KnowledgePayloadValidator } from '../contracts/knowledge/KnowledgePayloadValidator';
import { DocumentChunker } from '../knowledge/import/DocumentChunker';
import { RawFileDocumentImporter } from '../knowledge/import/RawFileDocumentImporter';
import { KeywordExtractor } from '../knowledge/import/KeywordExtractor';
import { UriTextContentReader } from '../knowledge/import/UriTextContentReader';
import { UserDocumentImportCoordinator } from '../knowledge/import/UserDocumentImportCoordinator';
import { UserDocumentImporter } from '../knowledge/import/UserDocumentImporter';
import { SystemDocumentSelectionSource, UserDocumentPicker } from '../knowledge/import/UserDocumentPicker';
import { L1PayloadBuilder } from '../knowledge/payload/L1PayloadBuilder';
import { L2PayloadBuilder } from '../knowledge/payload/L2PayloadBuilder';
import { KnowledgeProfileBuilder } from '../knowledge/profile/KnowledgeProfileBuilder';
import { KeywordRetrievalEngine } from '../knowledge/retrieval/KeywordRetrievalEngine';
import { ArkDataLocalKnowledgeService } from '../knowledge/service/ArkDataLocalKnowledgeService';
import { DocumentRepository } from '../knowledge/storage/DocumentRepository';
import { KnowledgeDatabase } from '../knowledge/storage/KnowledgeDatabase';
import { RdbDocumentRepository } from '../knowledge/storage/RdbDocumentRepository';

export interface KnowledgeComponents {
  gateway: LocalKnowledgeGateway;
  importer: RawFileDocumentImporter;
  userImporter: UserDocumentImportCoordinator;
  repository: DocumentRepository;
}

export class KnowledgeCompositionRoot {
  static async create(context: Context): Promise<KnowledgeComponents> {
    const database = new KnowledgeDatabase();
    await database.initialize(context);
    const repository = new RdbDocumentRepository(database);
    const importer = new RawFileDocumentImporter(context.resourceManager, repository, new DocumentChunker());
    const userImporter = new UserDocumentImportCoordinator(
      new UserDocumentPicker(new SystemDocumentSelectionSource(context)),
      new UriTextContentReader(),
      new UserDocumentImporter(repository, new DocumentChunker(), new KeywordExtractor())
    );
    const gateway = new ArkDataLocalKnowledgeService(
      repository,
      new KeywordRetrievalEngine(),
      new L1PayloadBuilder(),
      new L2PayloadBuilder(),
      new KnowledgeProfileBuilder(),
      new KnowledgePayloadValidator()
    );
    return { gateway: gateway, importer: importer, userImporter: userImporter, repository: repository };
  }
}
