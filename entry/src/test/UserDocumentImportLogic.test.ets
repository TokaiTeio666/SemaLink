import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeError } from '../main/ets/contracts/knowledge/KnowledgeError';
import { KeywordExtractor } from '../main/ets/knowledge/import/KeywordExtractor';
import {
  checksumUserText,
  validateUserDocument,
  validateUserText
} from '../main/ets/knowledge/import/UserDocumentPolicy';

function capturedCode(action: () => void): string {
  try {
    action();
  } catch (error) {
    if (error instanceof KnowledgeError) {
      return error.code;
    }
  }
  return '';
}

export default function userDocumentImportLogicTest() {
  describe('UserDocumentImportLogic', () => {
    it('accepts txt md and markdown but rejects unsupported extensions', 0, () => {
      validateUserDocument('notes.TXT', 100, 0);
      validateUserDocument('design.md', 100, 100);
      validateUserDocument('readme.markdown', 100, 200);
      expect(capturedCode((): void => validateUserDocument('private.pdf', 100, 0)))
        .assertEqual('E_FILE_TYPE_UNSUPPORTED');
    });

    it('rejects oversized files and total selections', 0, () => {
      expect(capturedCode((): void => validateUserDocument('large.txt', 2 * 1024 * 1024 + 1, 0)))
        .assertEqual('E_FILE_TOO_LARGE');
      expect(capturedCode((): void => validateUserDocument('last.md', 1024, 10 * 1024 * 1024)))
        .assertEqual('E_IMPORT_TOTAL_TOO_LARGE');
    });

    it('rejects empty normalized text', 0, () => {
      expect(capturedCode((): void => { validateUserText(' \r\n\t '); })).assertEqual('E_FILE_EMPTY');
    });

    it('extracts at most eight stable discriminating keywords', 0, () => {
      const extractor = new KeywordExtractor();
      const first = extractor.extract('TCP 粘包说明', 'TCP 字节流需要长度前缀处理粘包和半包。有哪些数据内容？');
      const second = extractor.extract('TCP 粘包说明', 'TCP 字节流需要长度前缀处理粘包和半包。有哪些数据内容？');
      expect(first.length > 0).assertTrue();
      expect(first.length <= 8).assertTrue();
      expect(first.indexOf('内容')).assertEqual(-1);
      expect(JSON.stringify(first)).assertEqual(JSON.stringify(second));
    });

    it('uses content-only stable checksums for duplicate detection', 0, () => {
      expect(checksumUserText('same content')).assertEqual(checksumUserText('same content'));
      expect(checksumUserText('same content') === checksumUserText('different content')).assertFalse();
    });
  });
}
