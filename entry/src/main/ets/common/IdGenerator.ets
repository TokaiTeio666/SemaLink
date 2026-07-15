export class SequenceIdGenerator {
  private sequence: number = 0;
  private readonly now: () => number;

  constructor(now: () => number = () => Date.now()) {
    this.now = now;
  }

  next(prefix: string): string {
    this.sequence += 1;
    return `${prefix}-${this.now()}-${this.sequence}`;
  }
}
