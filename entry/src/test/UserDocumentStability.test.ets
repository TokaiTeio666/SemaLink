import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeError } from '../main/ets/contracts/knowledge/KnowledgeError';
import { KnowledgeModality } from '../main/ets/contracts/knowledge/KnowledgeModels';
import { DocumentChunker } from '../main/ets/knowledge/import/DocumentChunker';
import { KeywordExtractor } from '../main/ets/knowledge/import/KeywordExtractor';
import { UserDocumentImporter } from '../main/ets/knowledge/import/UserDocumentImporter';
import { UserDocumentImportCoordinator } from '../main/ets/knowledge/import/UserDocumentImportCoordinator';
import {
  DocumentSelectionSource,
  UserDocumentPicker
} from '../main/ets/knowledge/import/UserDocumentPicker';
import {
  UriTextContentReader,
  UriTextDecoder,
  UriTextFileAccess,
  UserTextDocument
} from '../main/ets/knowledge/import/UriTextContentReader';
import { DocumentChunk } from '../main/ets/knowledge/model/DocumentChunk';
import { KnowledgeDocument } from '../main/ets/knowledge/model/KnowledgeDocument';
import {
  DocumentRepository,
  KnowledgeMetadata,
  RepositoryStatistics
} from '../main/ets/knowledge/storage/DocumentRepository';

class EmptySelectionSource implements DocumentSelectionSource {
  async select(): Promise<string[]> {
    return [];
  }
}

class FailingSelectionSource implements DocumentSelectionSource {
  async select(): Promise<string[]> {
    throw new Error('file:///private/document.txt');
  }
}

class SecondSaveFailingRepository implements DocumentRepository {
  metadata: KnowledgeMetadata = {
    indexState: 'READY', indexVersion: 'index-existing', profileVersion: 'profile-existing', updatedAt: 1
  };
  savedDocuments: number = 0;
  metadataWrites: number = 0;

  async saveDocumentWithChunks(document: KnowledgeDocument, chunks: DocumentChunk[]): Promise<void> {
    if (this.savedDocuments === 1) {
      throw new Error('SQL failed for file:///private/second.txt');
    }
    this.savedDocuments += 1;
  }

  async hasChecksum(checksum: string): Promise<boolean> {
    return false;
  }

  async listDocuments(): Promise<KnowledgeDocument[]> {
    return [];
  }

  async listChunks(): Promise<DocumentChunk[]> {
    return [];
  }

  async clearAll(): Promise<void> {
  }

  async getStatistics(): Promise<RepositoryStatistics> {
    const modalities: KnowledgeModality[] = [];
    return { documentCount: this.savedDocuments, chunkCount: 0, modalities: modalities, domainCounts: [] };
  }

  async getMetadata(): Promise<KnowledgeMetadata> {
    return this.metadata;
  }

  async setMetadata(metadata: KnowledgeMetadata): Promise<void> {
    this.metadataWrites += 1;
    this.metadata = metadata;
  }
}

class SecondSaveAndErrorMetadataFailingRepository extends SecondSaveFailingRepository {
  async setMetadata(metadata: KnowledgeMetadata): Promise<void> {
    if (metadata.indexState === 'ERROR') {
      this.metadataWrites += 1;
      throw new Error('SQL metadata failure for file:///private/second.txt');
    }
    await super.setMetadata(metadata);
  }
}

class ControlledUriTextFileAccess implements UriTextFileAccess {
  private readonly failRead: boolean;
  private readonly failClose: boolean;

  constructor(failRead: boolean, failClose: boolean) {
    this.failRead = failRead;
    this.failClose = failClose;
  }

  async getSize(uri: string): Promise<number> {
    return 4;
  }

  async openReadOnly(uri: string): Promise<number> {
    return 7;
  }

  async read(fd: number, maximumBytes: number): Promise<Uint8Array> {
    if (this.failRead) {
      throw new KnowledgeError('E_FILE_READ_FAILED', '文档读取不完整', true);
    }
    return new Uint8Array([116, 101, 120, 116]);
  }

  async close(fd: number): Promise<void> {
    if (this.failClose) {
      throw new Error('close failed for file:///private/document.txt');
    }
  }
}

class ControlledUriTextDecoder implements UriTextDecoder {
  decode(bytes: Uint8Array): string {
    return 'text';
  }
}

async function capturedKnowledgeError(action: () => Promise<void>): Promise<KnowledgeError | undefined> {
  try {
    await action();
  } catch (error) {
    if (error instanceof KnowledgeError) {
      return error;
    }
  }
  return undefined;
}

function userDocument(name: string, text: string): UserTextDocument {
  return { displayName: name, normalizedText: text, byteSize: text.length };
}

export default function userDocumentStabilityTest() {
  describe('UserDocumentStability', () => {
    it('classifies only an explicit empty selection as cancelled', 0, async () => {
      const picker = new UserDocumentPicker(new EmptySelectionSource());
      const failure = await capturedKnowledgeError(async (): Promise<void> => {
        await picker.select();
      });

      expect(failure === undefined).assertFalse();
      expect(failure?.code).assertEqual('E_FILE_SELECTION_CANCELLED');
      expect(failure?.message).assertEqual('未选择文档');
    });

    it('maps picker rejection to a safe picker failure', 0, async () => {
      const picker = new UserDocumentPicker(new FailingSelectionSource());
      const failure = await capturedKnowledgeError(async (): Promise<void> => {
        await picker.select();
      });

      expect(failure === undefined).assertFalse();
      expect(failure?.code).assertEqual('E_FILE_PICKER_FAILED');
      expect(failure?.message).assertEqual('无法打开文档选择器');
      expect(failure?.message.includes('file:')).assertFalse();
    });

    it('does not start importing when document selection is cancelled', 0, async () => {
      const repository = new SecondSaveFailingRepository();
      const importer = new UserDocumentImporter(repository, new DocumentChunker(), new KeywordExtractor());
      const coordinator = new UserDocumentImportCoordinator(
        new UserDocumentPicker(new EmptySelectionSource()), new UriTextContentReader(), importer);
      const failure = await capturedKnowledgeError(async (): Promise<void> => {
        await coordinator.selectAndImport();
      });

      expect(failure?.code).assertEqual('E_FILE_SELECTION_CANCELLED');
      expect(repository.metadata.indexState).assertEqual('READY');
      expect(repository.metadataWrites).assertEqual(0);
      expect(repository.savedDocuments).assertEqual(0);
    });

    it('sets ERROR metadata when saving the second document fails', 0, async () => {
      const repository = new SecondSaveFailingRepository();
      const importer = new UserDocumentImporter(repository, new DocumentChunker(), new KeywordExtractor());
      const failure = await capturedKnowledgeError(async (): Promise<void> => {
        await importer.importDocuments([
          userDocument('first.txt', 'first stable document'),
          userDocument('second.txt', 'second document triggers controlled failure')
        ]);
      });

      expect(failure === undefined).assertFalse();
      expect(failure?.code).assertEqual('E_RETRIEVAL_FAILED');
      expect(failure?.message).assertEqual('无法导入所选文档');
      expect(repository.metadata.indexState).assertEqual('ERROR');
      expect(repository.metadata.indexVersion.startsWith('index-error-')).assertTrue();
      expect(repository.metadata.profileVersion.startsWith('profile-error-')).assertTrue();
      expect(repository.savedDocuments).assertEqual(1);
      expect(repository.metadataWrites).assertEqual(2);
    });

    it('keeps the safe import error when ERROR metadata persistence also fails', 0, async () => {
      const repository = new SecondSaveAndErrorMetadataFailingRepository();
      const importer = new UserDocumentImporter(repository, new DocumentChunker(), new KeywordExtractor());
      const failure = await capturedKnowledgeError(async (): Promise<void> => {
        await importer.importDocuments([
          userDocument('first.txt', 'first stable document'),
          userDocument('second.txt', 'second document triggers controlled failure')
        ]);
      });

      expect(failure === undefined).assertFalse();
      expect(failure?.code).assertEqual('E_RETRIEVAL_FAILED');
      expect(failure?.message).assertEqual('无法导入所选文档');
      expect(failure?.message.includes('SQL')).assertFalse();
      expect(failure?.message.includes('file:')).assertFalse();
      expect(repository.savedDocuments).assertEqual(1);
      expect(repository.metadataWrites).assertEqual(2);
    });

    it('preserves the primary read error when closing the file also fails', 0, async () => {
      const reader = new UriTextContentReader(
        new ControlledUriTextFileAccess(true, true), new ControlledUriTextDecoder());
      const failure = await capturedKnowledgeError(async (): Promise<void> => {
        await reader.read({ uri: 'file:///private/document.txt', displayName: 'document.txt' }, 0);
      });

      expect(failure?.code).assertEqual('E_FILE_READ_FAILED');
      expect(failure?.message).assertEqual('文档读取不完整');
      expect(failure?.message.includes('file:')).assertFalse();
    });

    it('returns a safe read error when only closing the file fails', 0, async () => {
      const reader = new UriTextContentReader(
        new ControlledUriTextFileAccess(false, true), new ControlledUriTextDecoder());
      const failure = await capturedKnowledgeError(async (): Promise<void> => {
        await reader.read({ uri: 'file:///private/document.txt', displayName: 'document.txt' }, 0);
      });

      expect(failure?.code).assertEqual('E_FILE_READ_FAILED');
      expect(failure?.message).assertEqual('无法读取所选文档');
      expect(failure?.message.includes('file:')).assertFalse();
    });
  });
}
