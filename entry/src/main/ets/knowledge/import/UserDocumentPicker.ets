import { Context } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { KnowledgeError } from '../../contracts/knowledge/KnowledgeError';
import { MAX_USER_DOCUMENTS } from './UserDocumentPolicy';

export interface SelectedUserDocument {
  uri: string;
  displayName: string;
}

export interface DocumentSelectionSource {
  select(): Promise<string[]>;
}

function displayNameFromUri(uri: string): string {
  const queryIndex: number = uri.indexOf('?');
  const withoutQuery: string = queryIndex >= 0 ? uri.substring(0, queryIndex) : uri;
  const slash: number = withoutQuery.lastIndexOf('/');
  return slash >= 0 ? withoutQuery.substring(slash + 1) : withoutQuery;
}

export class SystemDocumentSelectionSource implements DocumentSelectionSource {
  private readonly context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  async select(): Promise<string[]> {
    const documentPicker = new picker.DocumentViewPicker(this.context);
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = MAX_USER_DOCUMENTS;
    options.fileSuffixFilters = ['文本与 Markdown|.txt,.md,.markdown'];
    return documentPicker.select(options);
  }
}

export class UserDocumentPicker {
  private readonly source: DocumentSelectionSource;

  constructor(source: DocumentSelectionSource) {
    this.source = source;
  }

  async select(): Promise<SelectedUserDocument[]> {
    let uris: string[];
    try {
      uris = await this.source.select();
    } catch (error) {
      throw new KnowledgeError('E_FILE_PICKER_FAILED', '无法打开文档选择器', true);
    }
    if (uris.length === 0) {
      throw new KnowledgeError('E_FILE_SELECTION_CANCELLED', '未选择文档', true);
    }
    const selected: SelectedUserDocument[] = [];
    for (const uri of uris) {
      selected.push({ uri: uri, displayName: displayNameFromUri(uri) });
    }
    return selected;
  }
}
