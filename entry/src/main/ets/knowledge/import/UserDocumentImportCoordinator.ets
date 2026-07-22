import { ImportReport } from '../../contracts/knowledge/KnowledgeModels';
import { UserDocumentImporter } from './UserDocumentImporter';
import { SelectedUserDocument, UserDocumentPicker } from './UserDocumentPicker';
import { UriTextContentReader, UserTextDocument } from './UriTextContentReader';

export class UserDocumentImportCoordinator {
  private readonly picker: UserDocumentPicker;
  private readonly reader: UriTextContentReader;
  private readonly importer: UserDocumentImporter;

  constructor(picker: UserDocumentPicker, reader: UriTextContentReader, importer: UserDocumentImporter) {
    this.picker = picker;
    this.reader = reader;
    this.importer = importer;
  }

  async selectAndImport(): Promise<ImportReport> {
    const selected: SelectedUserDocument[] = await this.picker.select();
    const documents: UserTextDocument[] = [];
    let accumulatedBytes = 0;
    for (const item of selected) {
      const document: UserTextDocument = await this.reader.read(item, accumulatedBytes);
      documents.push(document);
      accumulatedBytes += document.byteSize;
    }
    return this.importer.importDocuments(documents);
  }
}
