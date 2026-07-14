export interface Scheduler {
  schedule(delayMs: number, callback: () => void): number;
  cancel(timerId: number): void;
}

export class SystemScheduler implements Scheduler {
  schedule(delayMs: number, callback: () => void): number {
    return setTimeout(callback, delayMs);
  }

  cancel(timerId: number): void {
    clearTimeout(timerId);
  }
}
