export type KnowledgeErrorCode =
  'E_CONTRACT_VERSION_UNSUPPORTED' |
  'E_QUERY_INVALID' |
  'E_TOP_K_INVALID' |
  'E_PAYLOAD_BUDGET_INVALID' |
  'E_FILTER_INVALID' |
  'E_INDEX_NOT_READY' |
  'E_RETRIEVAL_FAILED' |
  'E_PAYLOAD_INVALID' |
  'E_FILE_TYPE_UNSUPPORTED' |
  'E_FILE_TOO_LARGE' |
  'E_IMPORT_TOTAL_TOO_LARGE' |
  'E_FILE_EMPTY' |
  'E_FILE_READ_FAILED' |
  'E_FILE_PICKER_FAILED' |
  'E_FILE_SELECTION_CANCELLED';

export class KnowledgeError extends Error {
  readonly code: KnowledgeErrorCode;
  readonly recoverable: boolean;
  readonly retryAfterMs?: number;

  constructor(code: KnowledgeErrorCode, message: string, recoverable: boolean, retryAfterMs?: number) {
    super(message);
    this.name = 'KnowledgeError';
    this.code = code;
    this.recoverable = recoverable;
    this.retryAfterMs = retryAfterMs;
  }
}
