/**
 * M1 timetable domain models.
 *
 * These types are persistence-agnostic. Dates are ISO `YYYY-MM-DD` strings,
 * weeks are 1-based semester weeks, weekdays are 1=Mon .. 7=Sun.
 */
export interface Semester {
  id: string;
  name: string;
  startDate: string;
  totalWeeks: number;
  termCode: string;
  isCurrent: boolean;
  createdAt: number;
  updatedAt: number;
}

export interface Period {
  semesterId: string;
  index: number;
  startTime: string;
  endTime: string;
}

export interface Course {
  id: string;
  semesterId: string;
  name: string;
  teacher: string;
  room: string;
  weekday: number;
  startPeriod: number;
  endPeriod: number;
  weeks: number[];
  colorKey: number;
  content: string;
  note: string;
  source: string;
  createdAt: number;
  updatedAt: number;
}

export enum ExceptionType {
  CANCEL = 'CANCEL',
  RESCHEDULE = 'RESCHEDULE'
}

export interface CourseException {
  id: string;
  courseId: string;
  week: number;
  type: ExceptionType;
  newWeekday: number;
  newStartPeriod: number;
  newEndPeriod: number;
  newRoom: string;
  note: string;
  source: string;
  createdAt: number;
  updatedAt: number;
}

/** A course after applying the exception for one week. */
export interface ExpandedCourse {
  courseId: string;
  exceptionId: string;
  week: number;
  name: string;
  teacher: string;
  room: string;
  weekday: number;
  startPeriod: number;
  endPeriod: number;
  colorKey: number;
  content: string;
  isException: boolean;
  exceptionType: string;
  note: string;
}

export interface Conflict {
  weekday: number;
  period: number;
  first: ExpandedCourse;
  second: ExpandedCourse;
}

export interface Event {
  id: string;
  semesterId: string;
  title: string;
  startTime: number;
  endTime: number;
  allDay: boolean;
  location: string;
  note: string;
  category: string;
  source: string;
  externalId: string;
  createdAt: number;
  updatedAt: number;
}

export const COURSE_SOURCE_MANUAL: string = 'MANUAL';
export const COURSE_SOURCE_IMPORT: string = 'IMPORT';

export function parseWeeks(text: string): number[] {
  const result: number[] = [];
  const parts: string[] = text.split(',');
  for (const part of parts) {
    const value: number = Number.parseInt(part.trim(), 10);
    if (!Number.isNaN(value) && value > 0 && result.indexOf(value) < 0) {
      result.push(value);
    }
  }
  result.sort((a: number, b: number) => a - b);
  return result;
}

export function formatWeeks(weeks: number[]): string {
  const sorted: number[] = weeks.slice().sort((a: number, b: number) => a - b);
  return sorted.join(',');
}

export function weekdayLabel(weekday: number): string {
  const labels: string[] = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return weekday >= 1 && weekday <= 7 ? labels[weekday] : '';
}

/**
 * Display-only course name cleanup. Jxfw keeps the class sequence in the
 * official name (高等数学（1）), but the timetable reads better without it.
 * Stored names stay untouched so week matching and deterministic IDs are stable.
 */
export function displayCourseName(name: string): string {
  let result: string = name.trim();
  let previous: string = '';
  while (previous !== result) {
    previous = result;
    result = result.replace(/\s*[（(]\s*\d{1,2}\s*[)）]\s*$/, '').trim();
  }
  return result.length > 0 ? result : name.trim();
}
