import { relationalStore } from '@kit.ArkData';
import { KnowledgeError } from '../../contracts/knowledge/KnowledgeError';
import { KnowledgeIndexState, KnowledgeModality } from '../../contracts/knowledge/KnowledgeModels';
import { DocumentChunk } from '../model/DocumentChunk';
import { KnowledgeDocument } from '../model/KnowledgeDocument';
import {
  DocumentRepository,
  DomainCount,
  KnowledgeMetadata,
  RepositoryStatistics
} from './DocumentRepository';
import { KnowledgeDatabase } from './KnowledgeDatabase';

function parseStringArray(json: string): string[] {
  try {
    return JSON.parse(json) as string[];
  } catch (error) {
    throw new KnowledgeError('E_RETRIEVAL_FAILED', 'Stored local knowledge metadata is invalid', false);
  }
}

function parseModality(value: string): KnowledgeModality {
  if (value === 'text' || value === 'pdf' || value === 'image' || value === 'ocr_text') {
    return value;
  }
  throw new KnowledgeError('E_RETRIEVAL_FAILED', 'Stored document modality is invalid', false);
}

function parseState(value: string): KnowledgeIndexState {
  if (value === 'EMPTY' || value === 'BUILDING' || value === 'READY' || value === 'ERROR') {
    return value;
  }
  return 'ERROR';
}

function incrementDomain(counts: DomainCount[], tag: string): void {
  for (const count of counts) {
    if (count.tag === tag) {
      count.documentCount += 1;
      return;
    }
  }
  counts.push({ tag: tag, documentCount: 1 });
}

export class RdbDocumentRepository implements DocumentRepository {
  private readonly database: KnowledgeDatabase;

  constructor(database: KnowledgeDatabase) {
    this.database = database;
  }

  async saveDocumentWithChunks(document: KnowledgeDocument, chunks: DocumentChunk[]): Promise<void> {
    const store = this.database.getStore();
    store.beginTransaction();
    try {
      const documentValues: relationalStore.ValuesBucket = {
        document_id: document.documentId,
        title: document.title,
        modality: document.modality,
        normalized_text: document.normalizedText,
        tags_json: JSON.stringify(document.tags),
        checksum: document.checksum,
        created_at: document.createdAt,
        updated_at: document.updatedAt
      };
      await store.insert('documents', documentValues);
      for (const chunk of chunks) {
        const chunkValues: relationalStore.ValuesBucket = {
          chunk_id: chunk.chunkId,
          document_id: chunk.documentId,
          chunk_index: chunk.chunkIndex,
          chunk_text: chunk.text,
          summary: chunk.summary,
          keywords_json: JSON.stringify(chunk.keywords),
          start_offset: chunk.startOffset,
          end_offset: chunk.endOffset,
          updated_at: chunk.updatedAt
        };
        await store.insert('document_chunks', chunkValues);
      }
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new KnowledgeError('E_RETRIEVAL_FAILED', 'Unable to save an imported knowledge document', true);
    }
  }

  async hasChecksum(checksum: string): Promise<boolean> {
    const result = await this.database.getStore().querySql(
      'SELECT checksum FROM documents WHERE checksum = ? LIMIT 1', [checksum]);
    try {
      return result.goToNextRow();
    } finally {
      result.close();
    }
  }

  async listDocuments(): Promise<KnowledgeDocument[]> {
    const documents: KnowledgeDocument[] = [];
    const result = await this.database.getStore().querySql(
      'SELECT document_id,title,modality,normalized_text,tags_json,checksum,created_at,updated_at FROM documents ORDER BY document_id');
    try {
      while (result.goToNextRow()) {
        documents.push({
          documentId: result.getString(0), title: result.getString(1), modality: parseModality(result.getString(2)),
          normalizedText: result.getString(3), tags: parseStringArray(result.getString(4)), checksum: result.getString(5),
          createdAt: result.getLong(6), updatedAt: result.getLong(7)
        });
      }
    } finally {
      result.close();
    }
    return documents;
  }

  async listChunks(): Promise<DocumentChunk[]> {
    const chunks: DocumentChunk[] = [];
    const result = await this.database.getStore().querySql(
      'SELECT chunk_id,document_id,chunk_index,chunk_text,summary,keywords_json,start_offset,end_offset,updated_at ' +
      'FROM document_chunks ORDER BY document_id,chunk_index');
    try {
      while (result.goToNextRow()) {
        chunks.push({
          chunkId: result.getString(0), documentId: result.getString(1), chunkIndex: result.getLong(2),
          text: result.getString(3), summary: result.getString(4), keywords: parseStringArray(result.getString(5)),
          startOffset: result.getLong(6), endOffset: result.getLong(7), updatedAt: result.getLong(8)
        });
      }
    } finally {
      result.close();
    }
    return chunks;
  }

  async clearAll(): Promise<void> {
    const store = this.database.getStore();
    store.beginTransaction();
    try {
      await store.executeSql('DELETE FROM document_chunks');
      await store.executeSql('DELETE FROM documents');
      store.commit();
      await this.setMetadata({
        indexState: 'EMPTY', indexVersion: 'index-empty', profileVersion: 'profile-empty', updatedAt: Date.now()
      });
    } catch (error) {
      store.rollBack();
      throw new KnowledgeError('E_RETRIEVAL_FAILED', 'Unable to clear the local knowledge base', true);
    }
  }

  async getStatistics(): Promise<RepositoryStatistics> {
    const documents = await this.listDocuments();
    const chunks = await this.listChunks();
    const modalities: KnowledgeModality[] = [];
    const domainCounts: DomainCount[] = [];
    for (const document of documents) {
      if (modalities.indexOf(document.modality) < 0) {
        modalities.push(document.modality);
      }
      for (const tag of document.tags) {
        incrementDomain(domainCounts, tag);
      }
    }
    return {
      documentCount: documents.length,
      chunkCount: chunks.length,
      modalities: modalities,
      domainCounts: domainCounts
    };
  }

  async getMetadata(): Promise<KnowledgeMetadata> {
    let state: KnowledgeIndexState = 'EMPTY';
    let indexVersion = 'index-empty';
    let profileVersion = 'profile-empty';
    let updatedAt = 0;
    const result = await this.database.getStore().querySql(
      'SELECT metadata_key,metadata_value FROM knowledge_metadata');
    try {
      while (result.goToNextRow()) {
        const key = result.getString(0);
        const value = result.getString(1);
        if (key === 'index_state') state = parseState(value);
        if (key === 'index_version') indexVersion = value;
        if (key === 'profile_version') profileVersion = value;
        if (key === 'last_imported_at') updatedAt = Number.parseInt(value);
      }
    } finally {
      result.close();
    }
    return { indexState: state, indexVersion: indexVersion, profileVersion: profileVersion, updatedAt: updatedAt };
  }

  async setMetadata(metadata: KnowledgeMetadata): Promise<void> {
    const store = this.database.getStore();
    await store.executeSql('INSERT OR REPLACE INTO knowledge_metadata(metadata_key,metadata_value) VALUES (?,?)',
      ['index_state', metadata.indexState]);
    await store.executeSql('INSERT OR REPLACE INTO knowledge_metadata(metadata_key,metadata_value) VALUES (?,?)',
      ['index_version', metadata.indexVersion]);
    await store.executeSql('INSERT OR REPLACE INTO knowledge_metadata(metadata_key,metadata_value) VALUES (?,?)',
      ['profile_version', metadata.profileVersion]);
    await store.executeSql('INSERT OR REPLACE INTO knowledge_metadata(metadata_key,metadata_value) VALUES (?,?)',
      ['last_imported_at', metadata.updatedAt.toString()]);
  }
}
