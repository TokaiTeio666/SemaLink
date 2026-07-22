import { Context } from '@kit.AbilityKit';
import { LocalKnowledgeGateway } from '../contracts/knowledge/LocalKnowledgeGateway';
import { SemanticKnowledgeProvider } from '../contracts/semantic/SemanticKnowledgeProvider';
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
import { EvidenceUnitFactory } from '../knowledge/evidence/EvidenceUnitFactory';
import { KnowledgeProfileBuilder } from '../knowledge/profile/KnowledgeProfileBuilder';
import { RdbKeywordRetrievalEngine } from '../knowledge/retrieval/RdbKeywordRetrievalEngine';
import { ArkDataLocalKnowledgeService } from '../knowledge/service/ArkDataLocalKnowledgeService';
import { DocumentRepository } from '../knowledge/storage/DocumentRepository';
import { KnowledgeDatabase } from '../knowledge/storage/KnowledgeDatabase';
import { RdbDocumentRepository } from '../knowledge/storage/RdbDocumentRepository';
import {
  RdbSearchBackend,
  RdbSearchCapabilities,
  chooseEnabledRdbSearchBackend
} from '../knowledge/storage/RdbSearchCapabilityProbe';
import {
  PROCESS_RDB_SEARCH_CAPABILITY_PROVIDER,
  RdbSearchCapabilityProvider
} from '../knowledge/storage/RdbSearchCapabilityProvider';

export interface KnowledgeComponents {
  service: ArkDataLocalKnowledgeService;
  gateway: LocalKnowledgeGateway;
  provider: SemanticKnowledgeProvider;
  importer: RawFileDocumentImporter;
  userImporter: UserDocumentImportCoordinator;
  repository: DocumentRepository;
  database: KnowledgeDatabase;
  searchBackend: RdbSearchBackend;
  searchCapabilities: RdbSearchCapabilities;
}

export class KnowledgeCompositionRoot {
  static async create(context: Context, sourceDeviceId: string = 'local-device',
    capabilityProvider: RdbSearchCapabilityProvider = PROCESS_RDB_SEARCH_CAPABILITY_PROVIDER):
    Promise<KnowledgeComponents> {
    const searchCapabilities = await capabilityProvider.get(context);
    const searchBackend = chooseEnabledRdbSearchBackend(searchCapabilities);
    const database = new KnowledgeDatabase();
    await database.initialize(context);
    const repository = new RdbDocumentRepository(database);
    const importer = new RawFileDocumentImporter(context.resourceManager, repository, new DocumentChunker());
    const userImporter = new UserDocumentImportCoordinator(
      new UserDocumentPicker(new SystemDocumentSelectionSource(context)),
      new UriTextContentReader(),
      new UserDocumentImporter(repository, new DocumentChunker(), new KeywordExtractor())
    );
    const retrieval = new RdbKeywordRetrievalEngine(repository);
    const evidenceFactory = new EvidenceUnitFactory();
    const service = new ArkDataLocalKnowledgeService(
      repository,
      retrieval,
      new L1PayloadBuilder(),
      new L2PayloadBuilder(),
      new KnowledgeProfileBuilder(),
      new KnowledgePayloadValidator(),
      evidenceFactory,
      sourceDeviceId
    );
    return {
      service: service, gateway: service, provider: service, importer: importer, userImporter: userImporter,
      repository: repository, database: database, searchBackend: searchBackend,
      searchCapabilities: searchCapabilities
    };
  }
}
