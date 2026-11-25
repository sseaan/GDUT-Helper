import { Period } from './TimetableModels';

export const DEFAULT_PERIOD_TIMES: string[][] = [
  ['08:30', '09:15'],
  ['09:20', '10:05'],
  ['10:25', '11:10'],
  ['11:15', '12:00'],
  ['13:50', '14:35'],
  ['14:40', '15:25'],
  ['15:30', '16:15'],
  ['16:30', '17:15'],
  ['17:20', '18:05'],
  ['18:30', '19:15'],
  ['19:20', '20:05'],
  ['20:10', '20:55']
];

export function defaultPeriods(semesterId: string): Period[] {
  const result: Period[] = [];
  for (let i = 0; i < DEFAULT_PERIOD_TIMES.length; i++) {
    result.push({
      semesterId: semesterId,
      index: i + 1,
      startTime: DEFAULT_PERIOD_TIMES[i][0],
      endTime: DEFAULT_PERIOD_TIMES[i][1]
    });
  }
  return result;
}
