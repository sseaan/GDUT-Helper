import {
  Course,
  CourseException,
  Event,
  ExpandedCourse,
  Semester
} from '../model/TimetableModels';
import { DEFAULT_PERIOD_TIMES } from '../model/Periods';
import { expandWeek, isoDate, weekOf } from '../timetable/TimetableEngine';

export enum AgendaKind {
  COURSE = 'COURSE',
  EXAM = 'EXAM',
  EVENT = 'EVENT'
}

export interface AgendaItem {
  id: string;
  kind: AgendaKind;
  title: string;
  subtitle: string;
  location: string;
  startTime: number;
  endTime: number;
  allDay: boolean;
  colorKey: number;
  course: ExpandedCourse | null;
  event: Event | null;
}

function parseTime(text: string): number[] {
  const parts: string[] = text.split(':');
  if (parts.length !== 2) {
    return [0, 0];
  }
  return [Number.parseInt(parts[0], 10), Number.parseInt(parts[1], 10)];
}

function localTimestamp(date: Date, hour: number, minute: number): number {
  return new Date(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate(), hour, minute).getTime();
}

function eventTimestamp(ms: number): number {
  const date: Date = new Date(ms);
  return new Date(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate(),
    date.getUTCHours(), date.getUTCMinutes()).getTime();
}

export function agendaForDate(
  courses: Course[],
  exceptions: CourseException[],
  events: Event[],
  semester: Semester,
  date: Date
): AgendaItem[] {
  const week: number = weekOf(semester.startDate, date);
  if (week < 1 || week > semester.totalWeeks) {
    return [];
  }
  const weekday: number = (date.getUTCDay() + 6) % 7 + 1;
  const expanded: ExpandedCourse[] = expandWeek(courses, exceptions, week)
    .filter((course: ExpandedCourse) => course.weekday === weekday);
  const items: AgendaItem[] = [];
  for (const course of expanded) {
    const startIndex: number = course.startPeriod - 1;
    const endIndex: number = course.endPeriod - 1;
    if (startIndex < 0 || endIndex < 0 ||
      startIndex >= DEFAULT_PERIOD_TIMES.length || endIndex >= DEFAULT_PERIOD_TIMES.length) {
      continue;
    }
    const startParts: number[] = parseTime(DEFAULT_PERIOD_TIMES[startIndex][0]);
    const endParts: number[] = parseTime(DEFAULT_PERIOD_TIMES[endIndex][1]);
    items.push({
      id: `course:${course.courseId}:${course.exceptionId}:${week}`,
      kind: AgendaKind.COURSE,
      title: course.name,
      subtitle: `第 ${course.startPeriod}–${course.endPeriod} 节${course.teacher.length > 0 ? ' · ' + course.teacher : ''}`,
      location: course.room,
      startTime: localTimestamp(date, startParts[0], startParts[1]),
      endTime: localTimestamp(date, endParts[0], endParts[1]),
      allDay: false,
      colorKey: course.colorKey,
      course: course,
      event: null
    });
  }

  const day: string = isoDate(date);
  for (const event of events) {
    const eventDate: Date = new Date(event.startTime);
    const key: string = `${eventDate.getUTCFullYear()}-${`${eventDate.getUTCMonth() + 1}`.padStart(2, '0')}-${`${eventDate.getUTCDate()}`.padStart(2, '0')}`;
    if (key !== day) {
      continue;
    }
    items.push({
      id: `event:${event.id}`,
      kind: event.category === 'EXAM' ? AgendaKind.EXAM : AgendaKind.EVENT,
      title: event.title,
      subtitle: event.category === 'EXAM' ? '考试' : '日程',
      location: event.location,
      startTime: eventTimestamp(event.startTime),
      endTime: eventTimestamp(event.endTime),
      allDay: event.allDay,
      colorKey: 0,
      course: null,
      event: event
    });
  }
  items.sort((a: AgendaItem, b: AgendaItem) => {
    if (a.allDay !== b.allDay) {
      return a.allDay ? -1 : 1;
    }
    return a.startTime - b.startTime;
  });
  return items;
}
