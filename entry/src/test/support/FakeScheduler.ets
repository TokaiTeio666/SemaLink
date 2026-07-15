import { Scheduler } from '../../main/ets/common/Scheduler';

interface TimerEntry {
  id: number;
  callback: () => void;
  fireAt: number;
}

export class FakeScheduler implements Scheduler {
  private currentTime: number = 0;
  private nextId: number = 1;
  private timers: Array<TimerEntry> = [];

  schedule(delayMs: number, callback: () => void): number {
    const id = this.nextId;
    this.nextId += 1;
    this.timers.push({ id: id, callback: callback, fireAt: this.currentTime + delayMs });
    return id;
  }

  cancel(timerId: number): void {
    this.timers = this.timers.filter((entry) => entry.id !== timerId);
  }

  advanceBy(ms: number): void {
    const target = this.currentTime + ms;
    while (this.currentTime < target) {
      this.currentTime = target;
      const ready = this.timers
        .filter((entry) => entry.fireAt <= this.currentTime)
        .sort((a, b) => a.fireAt - b.fireAt);
      for (const entry of ready) {
        this.timers = this.timers.filter((t) => t.id !== entry.id);
        entry.callback();
      }
    }
  }

  pendingCount(): number {
    return this.timers.length;
  }
}
