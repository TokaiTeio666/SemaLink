import { relationalStore } from '@kit.ArkData';
import { DocumentChunk } from '../../../../main/ets/knowledge/model/DocumentChunk';
import { KnowledgeDocument } from '../../../../main/ets/knowledge/model/KnowledgeDocument';
import { KnowledgeDatabase } from '../../../../main/ets/knowledge/storage/KnowledgeDatabase';
import { parseStoredPrivacyLevel } from '../../../../main/ets/knowledge/storage/KnowledgeDatabaseSchema';
import {
  parseStoredModality,
  parseStoredStringArray
} from '../../../../main/ets/knowledge/storage/RdbDocumentRepository';

export interface StoredMetadataRows {
  indexState: string;
  indexVersion: string;
  profileVersion: string;
  lastImportedAt: string;
}

async function countRows(database: KnowledgeDatabase, tableName: string): Promise<number> {
  const sql = tableName === 'documents' ?
    'SELECT COUNT(*) FROM documents' : 'SELECT COUNT(*) FROM document_chunks';
  const result = await database.getStore().querySql(sql);
  try {
    return result.goToNextRow() ? result.getLong(0) : 0;
  } finally {
    result.close();
  }
}

export function countDocuments(database: KnowledgeDatabase): Promise<number> {
  return countRows(database, 'documents');
}

export function countChunks(database: KnowledgeDatabase): Promise<number> {
  return countRows(database, 'document_chunks');
}

export async function readMetadataRows(database: KnowledgeDatabase): Promise<StoredMetadataRows> {
  const rows: StoredMetadataRows = {
    indexState: '', indexVersion: '', profileVersion: '', lastImportedAt: ''
  };
  const result = await database.getStore().querySql(
    'SELECT metadata_key,metadata_value FROM knowledge_metadata ORDER BY metadata_key');
  try {
    while (result.goToNextRow()) {
      const key = result.getString(0);
      const value = result.getString(1);
      if (key === 'index_state') rows.indexState = value;
      if (key === 'index_version') rows.indexVersion = value;
      if (key === 'profile_version') rows.profileVersion = value;
      if (key === 'last_imported_at') rows.lastImportedAt = value;
    }
    return rows;
  } finally {
    result.close();
  }
}

export async function readDocuments(database: KnowledgeDatabase): Promise<KnowledgeDocument[]> {
  const documents: KnowledgeDocument[] = [];
  const result = await database.getStore().querySql(
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
    return documents;
  } finally {
    result.close();
  }
}

export async function readChunks(database: KnowledgeDatabase): Promise<DocumentChunk[]> {
  const chunks: DocumentChunk[] = [];
  const result = await database.getStore().querySql(
    'SELECT chunk_id,document_id,chunk_index,chunk_text,summary,keywords_json,start_offset,end_offset,updated_at ' +
    'FROM document_chunks ORDER BY document_id,chunk_index,chunk_id');
  try {
    while (result.goToNextRow()) {
      chunks.push({
        chunkId: result.getString(0), documentId: result.getString(1), chunkIndex: result.getLong(2),
        text: result.getString(3), summary: result.getString(4),
        keywords: parseStoredStringArray(result.getString(5)), startOffset: result.getLong(6),
        endOffset: result.getLong(7), updatedAt: result.getLong(8)
      });
    }
    return chunks;
  } finally {
    result.close();
  }
}
