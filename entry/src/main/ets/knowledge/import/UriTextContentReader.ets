import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { KnowledgeError } from '../../contracts/knowledge/KnowledgeError';
import { SelectedUserDocument } from './UserDocumentPicker';
import { validateUserDocument, validateUserText } from './UserDocumentPolicy';

export interface UserTextDocument {
  displayName: string;
  normalizedText: string;
  byteSize: number;
}

export interface UriTextFileAccess {
  getSize(uri: string): Promise<number>;
  openReadOnly(uri: string): Promise<number>;
  read(fd: number, maximumBytes: number): Promise<Uint8Array>;
  close(fd: number): Promise<void>;
}

export interface UriTextDecoder {
  decode(bytes: Uint8Array): string;
}

class SystemUriTextFileAccess implements UriTextFileAccess {
  async getSize(uri: string): Promise<number> {
    const stat: fileIo.Stat = await fileIo.stat(uri);
    return stat.size;
  }

  async openReadOnly(uri: string): Promise<number> {
    const opened: fileIo.File = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    return opened.fd;
  }

  async read(fd: number, maximumBytes: number): Promise<Uint8Array> {
    const buffer = new ArrayBuffer(maximumBytes);
    const count: number = await fileIo.read(fd, buffer);
    return new Uint8Array(buffer, 0, count);
  }

  async close(fd: number): Promise<void> {
    await fileIo.close(fd);
  }
}

class SystemUriTextDecoder implements UriTextDecoder {
  decode(bytes: Uint8Array): string {
    const decoder = new util.TextDecoder('utf-8', { fatal: true, ignoreBOM: false });
    return decoder.decodeToString(bytes);
  }
}

export class UriTextContentReader {
  private readonly fileAccess: UriTextFileAccess;
  private readonly decoder: UriTextDecoder;

  constructor(fileAccess?: UriTextFileAccess, decoder?: UriTextDecoder) {
    this.fileAccess = fileAccess === undefined ? new SystemUriTextFileAccess() : fileAccess;
    this.decoder = decoder === undefined ? new SystemUriTextDecoder() : decoder;
  }

  async read(selected: SelectedUserDocument, accumulatedBytes: number): Promise<UserTextDocument> {
    let openedFd: number | undefined = undefined;
    let result: UserTextDocument | undefined = undefined;
    let primaryFailure: KnowledgeError | undefined = undefined;
    try {
      const size: number = await this.fileAccess.getSize(selected.uri);
      validateUserDocument(selected.displayName, size, accumulatedBytes);
      openedFd = await this.fileAccess.openReadOnly(selected.uri);
      const bytes: Uint8Array = await this.readAll(openedFd, size);
      const normalized: string = validateUserText(this.decoder.decode(bytes));
      result = { displayName: selected.displayName, normalizedText: normalized, byteSize: size };
    } catch (error) {
      if (error instanceof KnowledgeError) {
        primaryFailure = error;
      } else {
        primaryFailure = new KnowledgeError('E_FILE_READ_FAILED', '无法读取所选文档', true);
      }
    }
    if (openedFd !== undefined) {
      try {
        await this.fileAccess.close(openedFd);
      } catch (closeError) {
        if (primaryFailure === undefined) {
          primaryFailure = new KnowledgeError('E_FILE_READ_FAILED', '无法读取所选文档', true);
        }
      }
    }
    if (primaryFailure !== undefined) {
      throw primaryFailure;
    }
    if (result === undefined) {
      throw new KnowledgeError('E_FILE_READ_FAILED', '无法读取所选文档', true);
    }
    return result;
  }

  private async readAll(fd: number, size: number): Promise<Uint8Array> {
    const target = new Uint8Array(size);
    let offset = 0;
    while (offset < size) {
      const bytes: Uint8Array = await this.fileAccess.read(fd, size - offset);
      if (bytes.length === 0) {
        break;
      }
      target.set(bytes, offset);
      offset += bytes.length;
    }
    if (offset !== size) {
      throw new KnowledgeError('E_FILE_READ_FAILED', '文档读取不完整', true);
    }
    return target;
  }
}
