export enum ErrorStage {
  SELECTION = 'SELECTION',
  CONNECTION = 'CONNECTION',
  PROTOCOL = 'PROTOCOL',
  QUERY = 'QUERY',
  LIFECYCLE = 'LIFECYCLE'
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
