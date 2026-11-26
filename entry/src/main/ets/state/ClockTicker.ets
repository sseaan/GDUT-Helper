export const CLOCK_TICK_KEY: string = 'clockTick';

let timerId: number = -1;

/**
 * A single app-level minute-ish ticker. Pages that show time-dependent course
 * state subscribe to `clockTick` so "已结束 / 下一节" updates without waiting
 * for a tab switch or a data revision.
 */
export class ClockTicker {
  static start(): void {
    if (timerId >= 0) {
      return;
    }
    timerId = setInterval(() => ClockTicker.bump(), 30000);
  }

  static bump(): void {
    const value: number | undefined = AppStorage.get<number>(CLOCK_TICK_KEY);
    AppStorage.setOrCreate(CLOCK_TICK_KEY, (value === undefined ? 0 : value) + 1);
  }

  static stop(): void {
    if (timerId >= 0) {
      clearInterval(timerId);
      timerId = -1;
    }
  }
}
