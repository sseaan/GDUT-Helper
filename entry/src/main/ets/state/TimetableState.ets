export const TIMETABLE_REVISION_KEY: string = 'timetableRevision';

export class TimetableState {
  static revision(): number {
    const value: number | undefined = AppStorage.get<number>(TIMETABLE_REVISION_KEY);
    return value === undefined ? 0 : value;
  }

  static bump(): void {
    AppStorage.setOrCreate(TIMETABLE_REVISION_KEY, TimetableState.revision() + 1);
  }
}
