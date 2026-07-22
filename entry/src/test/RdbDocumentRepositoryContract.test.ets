import { describe, expect, it } from '@ohos/hypium';
import { KnowledgeError } from '../main/ets/contracts/knowledge/KnowledgeError';
import {
  parseStoredModality,
  parseStoredStringArray,
  storageOperationError
} from '../main/ets/knowledge/storage/RdbDocumentRepository';

function capturedError(action: () => void): KnowledgeError | undefined {
  try {
    action();
  } catch (error) {
    if (error instanceof KnowledgeError) {
      return error;
    }
  }
  return undefined;
}

export default function rdbDocumentRepositoryContractTest() {
  describe('RdbDocumentRepositoryContract', () => {
    it('maps invalid stored rows to E_STORAGE_FAILED', 0, () => {
      expect(capturedError((): void => { parseStoredStringArray('{bad json'); })?.code)
        .assertEqual('E_STORAGE_FAILED');
      expect(capturedError((): void => { parseStoredModality('sql_column'); })?.code)
        .assertEqual('E_STORAGE_FAILED');
      expect(capturedError((): void => { parseStoredStringArray('{"tag":"os"}'); })?.code)
        .assertEqual('E_STORAGE_FAILED');
      expect(capturedError((): void => { parseStoredStringArray('["os",1]'); })?.code)
        .assertEqual('E_STORAGE_FAILED');
    });

    it('creates a retryable safe storage error without leaking lower-level details', 0, () => {
      const error = storageOperationError();
      const message = error.message.toLowerCase();
      expect(error.code).assertEqual('E_STORAGE_FAILED');
      expect(error.recoverable).assertTrue();
      expect(message.includes('sql')).assertFalse();
      expect(message.includes('file://')).assertFalse();
      expect(message.includes('/data/')).assertFalse();
      expect(message.includes('stack')).assertFalse();
    });
  });
}
