import { KnowledgeError } from '../../contracts/knowledge/KnowledgeError';
import { KnowledgeModality } from '../../contracts/knowledge/KnowledgeModels';

export interface RawFileManifestItem {
  filename: string;
  title: string;
  tags: string[];
  modality: KnowledgeModality;
  createdAt: number;
}

export interface RawFileManifest {
  documents: RawFileManifestItem[];
}

export function parseRawFileManifest(json: string): RawFileManifest {
  let manifest: RawFileManifest;
  try {
    manifest = JSON.parse(json) as RawFileManifest;
  } catch (error) {
    throw new KnowledgeError('E_RETRIEVAL_FAILED', 'Built-in document manifest is invalid', false);
  }
  if (!Array.isArray(manifest.documents) || manifest.documents.length === 0) {
    throw new KnowledgeError('E_RETRIEVAL_FAILED', 'Built-in document manifest is empty', false);
  }
  for (const item of manifest.documents) {
    if (item.filename.trim().length === 0 || item.title.trim().length === 0 || !Array.isArray(item.tags) ||
      item.modality !== 'text' || item.createdAt < 0) {
      throw new KnowledgeError('E_RETRIEVAL_FAILED', 'Built-in document manifest contains an invalid entry', false);
    }
  }
  return manifest;
}
