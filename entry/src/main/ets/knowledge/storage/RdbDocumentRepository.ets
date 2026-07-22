import { relationalStore } from '@kit.ArkData';
import { KnowledgeError } from '../../contracts/knowledge/KnowledgeError';
import { KnowledgeIndexState, KnowledgeModality } from '../../contracts/knowledge/KnowledgeModels';
import { DocumentChunk } from '../model/DocumentChunk';
import { KnowledgeDocument } from '../model/KnowledgeDocument';
import { RetrievalCandidate, RetrievalDocument } from '../model/RetrievalCandidate';
import { KnowledgeRetrievalRequest } from '../retrieval/RetrievalEngine';
import {
  DocumentRepository,
  DomainCount,
  KnowledgeMetadata,
  RepositoryStatistics
} from './DocumentRepository';
import { KnowledgeDatabase } from './KnowledgeDatabase';
import { parseStoredPrivacyLevel } from './KnowledgeDatabaseSchema';
import { KnowledgeCandidateSearch } from './KnowledgeCandidateSearch';
import { buildSqlLikeCandidateQuery, SqlLikeCandidateQuery } from './SqlLikeCandidateQuery';

export function storageOperationError(): KnowledgeError {
  return new KnowledgeError('E_STORAGE_FAILED', 'Local knowledge storage operation failed', true);
}

function rollbackAfterFailure(store: relationalStore.RdbStore): void {
  try {
    store.rollBack();
  } catch (error) {
    return;
  }
}

export function parseStoredStringArray(json: string): string[] {
  try {
    const parsed = JSON.parse(json) as string[];
    if (!Array.isArray(parsed)) {
      throw new KnowledgeError('E_STORAGE_FAILED', 'Stored local knowledge metadata is invalid', false);
    }
    for (const value of parsed) {
      if (typeof value !== 'string') {
        throw new KnowledgeError('E_STORAGE_FAILED', 'Stored local knowledge metadata is invalid', false);
      }
    }
    return parsed;
  } catch (error) {
    throw new KnowledgeError('E_STORAGE_FAILED', 'Stored local knowledge metadata is invalid', false);
  }
}

export function parseStoredModality(value: string): KnowledgeModality {
  if (value === 'text' || value === 'pdf' || value === 'image' || value === 'ocr_text') {
    return value;
  }
  throw new KnowledgeError('E_STORAGE_FAILED', 'Stored document modality is invalid', false);
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

function matchedSearchTerms(terms: string[], document: RetrievalDocument, chunk: DocumentChunk): string[] {
  const text = (document.title + ' ' + document.tags.join(' ') + ' ' + chunk.summary + ' ' +
    chunk.keywords.join(' ') + ' ' + chunk.text).toLowerCase();
  const matched: string[] = [];
  for (const term of terms) {
    if (text.includes(term)) {
      matched.push(term);
    }
  }
  return matched;
}

function compact(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9\u4E00-\u9FFF]+/g, '');
}

function mapCandidate(result: relationalStore.ResultSet, query: SqlLikeCandidateQuery,
  request: KnowledgeRetrievalRequest): RetrievalCandidate {
  const document: RetrievalDocument = {
    documentId: result.getString(0), title: result.getString(1), modality: parseStoredModality(result.getString(2)),
    tags: parseStoredStringArray(result.getString(3)), updatedAt: result.getLong(4),
    privacyLevel: parseStoredPrivacyLevel(result.getString(5))
  };
  const chunk: DocumentChunk = {
    chunkId: result.getString(6), documentId: document.documentId, chunkIndex: result.getLong(7),
    text: result.getString(8), summary: result.getString(9), keywords: parseStoredStringArray(result.getString(10)),
    startOffset: result.getLong(11), endOffset: result.getLong(12), updatedAt: result.getLong(13)
  };
  const rawScore: number = Math.max(0, result.getDouble(14));
  const normalized: number = Math.round((rawScore / (rawScore + 10)) * 10000) / 10000;
  const searchable = compact(document.title + document.tags.join(' ') + chunk.summary + chunk.text);
  const normalizedQuery = compact(request.queryText);
  return {
    document: document,
    chunk: chunk,
    relevance: Number.isFinite(normalized) ? normalized : 0,
    matchedPrimaryTerms: matchedSearchTerms(query.primaryTerms, document, chunk),
    matchedNgrams: matchedSearchTerms(query.ngrams, document, chunk),
    exactPhraseMatched: normalizedQuery.length >= 2 && searchable.includes(normalizedQuery)
  };
}

export interface RdbSearchDiagnostics {
  searchCalls: number;
  candidateRowsReturned: number;
  fullReadCallsDuringSearch: number;
}

export class RdbDocumentRepository implements DocumentRepository, KnowledgeCandidateSearch {
  private readonly database: KnowledgeDatabase;
  private activeCandidateSearch: number = 0;
  private searchCalls: number = 0;
  private candidateRowsReturned: number = 0;
  private fullReadCallsDuringSearch: number = 0;

  constructor(database: KnowledgeDatabase) {
    this.database = database;
  }

  async searchCandidates(request: KnowledgeRetrievalRequest): Promise<RetrievalCandidate[]> {
    this.activeCandidateSearch += 1;
    this.searchCalls += 1;
    try {
      const query: SqlLikeCandidateQuery | undefined = buildSqlLikeCandidateQuery(request);
      if (query === undefined) return [];
      const candidates: RetrievalCandidate[] = [];
      try {
        const result = await this.database.getStore().querySql(query.sql, query.bindArgs);
        try {
          while (result.goToNextRow()) candidates.push(mapCandidate(result, query, request));
        } finally {
          result.close();
        }
      } catch (error) {
        throw storageOperationError();
      }
      this.candidateRowsReturned += candidates.length;
      return candidates;
    } finally {
      this.activeCandidateSearch -= 1;
    }
  }

  resetSearchDiagnostics(): void {
    this.searchCalls = 0;
    this.candidateRowsReturned = 0;
    this.fullReadCallsDuringSearch = 0;
  }

  getSearchDiagnostics(): RdbSearchDiagnostics {
    return {
      searchCalls: this.searchCalls,
      candidateRowsReturned: this.candidateRowsReturned,
      fullReadCallsDuringSearch: this.fullReadCallsDuringSearch
    };
  }

  async saveDocumentWithChunks(document: KnowledgeDocument, chunks: DocumentChunk[]): Promise<void> {
    const store = this.database.getStore();
    try {
      store.beginTransaction();
      const documentValues: relationalStore.ValuesBucket = {
        document_id: document.documentId,
        title: document.title,
        modality: document.modality,
        normalized_text: document.normalizedText,
        tags_json: JSON.stringify(document.tags),
        checksum: document.checksum,
        created_at: document.createdAt,
        updated_at: document.updatedAt,
        privacy_level: document.privacyLevel
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
      rollbackAfterFailure(store);
      throw storageOperationError();
    }
  }

  async hasChecksum(checksum: string): Promise<boolean> {
    try {
      const result = await this.database.getStore().querySql(
        'SELECT checksum FROM documents WHERE checksum = ? LIMIT 1', [checksum]);
      try {
        return result.goToNextRow();
      } finally {
        result.close();
      }
    } catch (error) {
      throw storageOperationError();
    }
  }

  async listDocuments(): Promise<KnowledgeDocument[]> {
    if (this.activeCandidateSearch > 0) this.fullReadCallsDuringSearch += 1;
    const documents: KnowledgeDocument[] = [];
    try {
      const result = await this.database.getStore().querySql(
        'SELECT document_id,title,modality,normalized_text,tags_json,checksum,created_at,updated_at,privacy_level ' +
        'FROM documents ORDER BY document_id');
      try {
        while (result.goToNextRow()) {
          documents.push({
            documentId: result.getString(0), title: result.getString(1),
            modality: parseStoredModality(result.getString(2)), normalizedText: result.getString(3),
            tags: parseStoredStringArray(result.getString(4)), checksum: result.getString(5),
            createdAt: result.getLong(6), updatedAt: result.getLong(7),
            privacyLevel: parseStoredPrivacyLevel(result.getString(8))
          });
        }
      } finally {
        result.close();
      }
      return documents;
    } catch (error) {
      throw storageOperationError();
    }
  }

  async listChunks(): Promise<DocumentChunk[]> {
    if (this.activeCandidateSearch > 0) this.fullReadCallsDuringSearch += 1;
    const chunks: DocumentChunk[] = [];
    try {
      const result = await this.database.getStore().querySql(
        'SELECT chunk_id,document_id,chunk_index,chunk_text,summary,keywords_json,start_offset,end_offset,updated_at ' +
        'FROM document_chunks ORDER BY document_id,chunk_index');
      try {
        while (result.goToNextRow()) {
          chunks.push({
            chunkId: result.getString(0), documentId: result.getString(1), chunkIndex: result.getLong(2),
            text: result.getString(3), summary: result.getString(4),
            keywords: parseStoredStringArray(result.getString(5)), startOffset: result.getLong(6),
            endOffset: result.getLong(7), updatedAt: result.getLong(8)
          });
        }
      } finally {
        result.close();
      }
      return chunks;
    } catch (error) {
      throw storageOperationError();
    }
  }

  async clearAll(): Promise<void> {
    let store: relationalStore.RdbStore | undefined = undefined;
    try {
      store = this.database.getStore();
      store.beginTransaction();
      await store.executeSql('DELETE FROM document_chunks');
      await store.executeSql('DELETE FROM documents');
      store.commit();
      await this.setMetadata({
        indexState: 'EMPTY', indexVersion: 'index-empty', profileVersion: 'profile-empty', updatedAt: Date.now()
      });
    } catch (error) {
      if (store !== undefined) {
        rollbackAfterFailure(store);
      }
      throw storageOperationError();
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
    try {
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
    } catch (error) {
      throw storageOperationError();
    }
  }

  async setMetadata(metadata: KnowledgeMetadata): Promise<void> {
    try {
      const store = this.database.getStore();
      await store.executeSql('INSERT OR REPLACE INTO knowledge_metadata(metadata_key,metadata_value) VALUES (?,?)',
        ['index_state', metadata.indexState]);
      await store.executeSql('INSERT OR REPLACE INTO knowledge_metadata(metadata_key,metadata_value) VALUES (?,?)',
        ['index_version', metadata.indexVersion]);
      await store.executeSql('INSERT OR REPLACE INTO knowledge_metadata(metadata_key,metadata_value) VALUES (?,?)',
        ['profile_version', metadata.profileVersion]);
      await store.executeSql('INSERT OR REPLACE INTO knowledge_metadata(metadata_key,metadata_value) VALUES (?,?)',
        ['last_imported_at', metadata.updatedAt.toString()]);
    } catch (error) {
      throw storageOperationError();
    }
  }
}
