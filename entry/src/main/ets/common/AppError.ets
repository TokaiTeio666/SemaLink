export enum ErrorStage {
  SELECTION = 'SELECTION',
  CONNECTION = 'CONNECTION',
  PROTOCOL = 'PROTOCOL',
  QUERY = 'QUERY',
  LIFECYCLE = 'LIFECYCLE'
}

export const P4_ERROR_CODES: string[] = [
  'INSUFFICIENT_EVIDENCE',
  'E_BACKGROUND_INTERRUPTED',
  'E_PROFILE_STALE',
  'E_SEMANTIC_PROTOCOL_INVALID',
  'E_EVIDENCE_TOO_LARGE',
  'E_EVIDENCE_PAGE_LIMIT',
  'E_EVIDENCE_PAGE_TIMEOUT'
];

export function calculatePercentile(samples: number[], percentile: number): number {
  if (samples.length === 0) {
    return 0;
  }
  const ordered: number[] = samples.slice().sort((left: number, right: number) => left - right);
  const bounded: number = Math.max(0, Math.min(1, percentile));
  const index: number = Math.min(ordered.length - 1, Math.ceil(bounded * ordered.length) - 1);
  return ordered[Math.max(0, index)];
}

export class AppError extends Error {
  readonly code: string;
  readonly stage: ErrorStage;
  readonly recoverable: boolean;
  readonly systemCode?: number;

  constructor(
    code: string,
    message: string,
    stage: ErrorStage,
    recoverable: boolean,
    systemCode?: number
  ) {
    super(message);
    this.name = 'AppError';
    this.code = code;
    this.stage = stage;
    this.recoverable = recoverable;
    this.systemCode = systemCode;
  }
}
