import {
  Conflict,
  Course,
  CourseException,
  ExceptionType,
  ExpandedCourse
} from '../model/TimetableModels';

/** Date-only helpers; all arithmetic uses UTC to avoid DST shifts. */
export function parseIsoDate(value: string): Date {
  const parts: string[] = value.split('-');
  if (parts.length !== 3) {
    return new Date(Date.UTC(1970, 0, 1));
  }
  return new Date(Date.UTC(Number.parseInt(parts[0], 10), Number.parseInt(parts[1], 10) - 1,
    Number.parseInt(parts[2], 10)));
}

export function isoDate(date: Date): string {
  const year: string = `${date.getUTCFullYear()}`.padStart(4, '0');
  const month: string = `${date.getUTCMonth() + 1}`.padStart(2, '0');
  const day: string = `${date.getUTCDate()}`.padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export function todayIso(): string {
  const now: Date = new Date();
  return isoDate(new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate())));
}

export function mondayOf(date: Date): Date {
  const day: number = date.getUTCDay();
  const offset: number = (day + 6) % 7;
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() - offset));
}

export function daysBetween(start: Date, end: Date): number {
  return Math.round((end.getTime() - start.getTime()) / 86400000);
}

export function weekOf(semesterStart: string, date: Date): number {
  const startMonday: Date = mondayOf(parseIsoDate(semesterStart));
  const targetMonday: Date = mondayOf(date);
  return Math.floor(daysBetween(startMonday, targetMonday) / 7) + 1;
}

export function dateForWeekDay(semesterStart: string, week: number, weekday: number): Date {
  const startMonday: Date = mondayOf(parseIsoDate(semesterStart));
  return new Date(Date.UTC(startMonday.getUTCFullYear(), startMonday.getUTCMonth(),
    startMonday.getUTCDate() + (week - 1) * 7 + (weekday - 1)));
}

export function weekDateRange(semesterStart: string, week: number): string {
  const start: Date = dateForWeekDay(semesterStart, week, 1);
  const end: Date = dateForWeekDay(semesterStart, week, 7);
  return `${start.getUTCMonth() + 1}/${start.getUTCDate()} – ${end.getUTCMonth() + 1}/${end.getUTCDate()}`;
}

/**
 * Expands all courses for one week, applying CANCEL and RESCHEDULE exceptions.
 * A RESCHEDULE exception for a week outside the course's normal week set is a
 * makeup class and is included.
 */
export function expandWeek(
  courses: Course[],
  exceptions: CourseException[],
  week: number
): ExpandedCourse[] {
  const result: ExpandedCourse[] = [];
  for (const course of courses) {
    let exception: CourseException | undefined = undefined;
    for (const item of exceptions) {
      if (item.courseId === course.id && item.week === week) {
        exception = item;
        break;
      }
    }

    if (exception !== undefined && exception.type === ExceptionType.CANCEL) {
      continue;
    }

    const normallyActive: boolean = course.weeks.indexOf(week) >= 0;
    if (!normallyActive && exception === undefined) {
      continue;
    }

    if (exception !== undefined && exception.type === ExceptionType.RESCHEDULE) {
      result.push({
        courseId: course.id,
        exceptionId: exception.id,
        week: week,
        name: course.name,
        teacher: course.teacher,
        room: exception.newRoom.length > 0 ? exception.newRoom : course.room,
        weekday: exception.newWeekday > 0 ? exception.newWeekday : course.weekday,
        startPeriod: exception.newStartPeriod > 0 ? exception.newStartPeriod : course.startPeriod,
        endPeriod: exception.newEndPeriod > 0 ? exception.newEndPeriod : course.endPeriod,
        colorKey: course.colorKey,
        content: course.content,
        isException: true,
        exceptionType: exception.type,
        note: exception.note
      });
    } else {
      result.push({
        courseId: course.id,
        exceptionId: '',
        week: week,
        name: course.name,
        teacher: course.teacher,
        room: course.room,
        weekday: course.weekday,
        startPeriod: course.startPeriod,
        endPeriod: course.endPeriod,
        colorKey: course.colorKey,
        content: course.content,
        isException: false,
        exceptionType: '',
        note: course.note
      });
    }
  }
  return result;
}

export function coursesOnDate(
  courses: Course[],
  exceptions: CourseException[],
  semesterStart: string,
  date: Date,
  totalWeeks: number
): ExpandedCourse[] {
  const week: number = weekOf(semesterStart, date);
  if (week < 1 || week > totalWeeks) {
    return [];
  }
  const weekday: number = (date.getUTCDay() + 6) % 7 + 1;
  const expanded: ExpandedCourse[] = expandWeek(courses, exceptions, week);
  return expanded.filter((course: ExpandedCourse) => course.weekday === weekday);
}

/** Pairs of overlapping courses on the same weekday. */
export function detectConflicts(courses: ExpandedCourse[]): Conflict[] {
  const result: Conflict[] = [];
  for (let i = 0; i < courses.length; i++) {
    for (let j = i + 1; j < courses.length; j++) {
      const first: ExpandedCourse = courses[i];
      const second: ExpandedCourse = courses[j];
      if (first.weekday !== second.weekday) {
        continue;
      }
      if (first.startPeriod <= second.endPeriod && second.startPeriod <= first.endPeriod) {
        const period: number = Math.max(first.startPeriod, second.startPeriod);
        result.push({
          weekday: first.weekday,
          period: period,
          first: first,
          second: second
        });
      }
    }
  }
  return result;
}
