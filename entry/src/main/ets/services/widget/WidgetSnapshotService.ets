import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { AgendaItem, AgendaKind, agendaForDate } from '../../domain/agenda/AgendaEngine';
import { Course, CourseException, Event, Semester, weekdayLabel } from '../../domain/model/TimetableModels';
import { TimetableRepository } from '../../data/TimetableRepository';

const FILE_NAME: string = 'widget_today.json';

export interface WidgetCourse {
  time: string;
  name: string;
  room: string;
}

export interface WidgetWeekDay {
  label: string;
  courses: WidgetCourse[];
}

export interface WidgetSnapshot {
  date: string;
  weekday: string;
  week: string;
  courses: WidgetCourse[];
  next: WidgetCourse;
  weekDays: WidgetWeekDay[];
  updatedAt: string;
}

function timeText(ms: number): string {
  const date: Date = new Date(ms);
  return `${`${date.getHours()}`.padStart(2, '0')}:${`${date.getMinutes()}`.padStart(2, '0')}`;
}

function courseItem(item: AgendaItem): WidgetCourse {
  return {
    time: timeText(item.startTime),
    name: item.title,
    room: item.location
  };
}

export class WidgetSnapshotService {
  static path(context: common.Context): string {
    return `${context.filesDir}/${FILE_NAME}`;
  }

  static async write(context: common.Context): Promise<void> {
    try {
      const semester: Semester | null = await TimetableRepository.getCurrentSemester(context);
      const now: Date = new Date();
      if (semester === null) {
        const empty: WidgetSnapshot = {
          date: `${now.getMonth() + 1}月${now.getDate()}日`,
          weekday: weekdayLabel(now.getDay()),
          week: '未设置学期',
          courses: [],
          next: { time: '', name: '暂无课程', room: '' },
          weekDays: [],
          updatedAt: timeText(now.getTime())
        };
        WidgetSnapshotService.writeText(context, JSON.stringify(empty));
        return;
      }
      const courses: Course[] = await TimetableRepository.listCourses(context, semester.id);
      const exceptions: CourseException[] =
        await TimetableRepository.listExceptions(context, semester.id);
      const events: Event[] = await TimetableRepository.listEvents(context, semester.id);
      const today: Date = new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
      const agenda: AgendaItem[] = agendaForDate(courses, exceptions, events, semester, today);
      const courseItems: WidgetCourse[] = [];
      let next: WidgetCourse = { time: '', name: '今日暂无课程', room: '' };
      for (const item of agenda) {
        if (item.kind === AgendaKind.COURSE) {
          const mapped: WidgetCourse = courseItem(item);
          if (courseItems.length < 3) {
            courseItems.push(mapped);
          }
          if (next.time.length === 0 && item.endTime > now.getTime()) {
            next = mapped;
          }
        }
      }
      if (next.time.length === 0) {
        for (let offset = 1; offset <= 7 && next.time.length === 0; offset++) {
          const date: Date = new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate() + offset));
          const items: AgendaItem[] = agendaForDate(courses, exceptions, events, semester, date);
          const course: AgendaItem | undefined = items.find((item: AgendaItem) => item.kind === AgendaKind.COURSE);
          if (course !== undefined) {
            next = courseItem(course);
            const day: number = new Date(course.startTime).getDay();
            next.name = `${weekdayLabel(day)} ${next.name}`;
          }
        }
      }
      const weekDays: WidgetWeekDay[] = [];
      const weekdayIndex: number = (today.getUTCDay() + 6) % 7;
      const labels: string[] = ['一', '二', '三', '四', '五', '六', '日'];
      for (let dayIndex = 0; dayIndex < 7; dayIndex++) {
        const date: Date = new Date(Date.UTC(now.getFullYear(), now.getMonth(),
          now.getDate() - weekdayIndex + dayIndex));
        const items: AgendaItem[] = agendaForDate(courses, exceptions, events, semester, date);
        const dayCourses: WidgetCourse[] = [];
        for (const item of items) {
          if (item.kind === AgendaKind.COURSE && dayCourses.length < 3) {
            dayCourses.push(courseItem(item));
          }
        }
        weekDays.push({ label: labels[dayIndex], courses: dayCourses });
      }
      const week: string = currentWeekLabel(semester, today);
      const snapshot: WidgetSnapshot = {
        date: `${now.getMonth() + 1}月${now.getDate()}日`,
        weekday: weekdayLabel(now.getDay()),
        week: week,
        courses: courseItems,
        next: next,
        weekDays: weekDays,
        updatedAt: timeText(now.getTime())
      };
      WidgetSnapshotService.writeText(context, JSON.stringify(snapshot));
    } catch (error) {
      // Widget snapshot is best effort; never block app startup.
    }
  }

  private static writeText(context: common.Context, text: string): void {
    const file = fs.openSync(WidgetSnapshotService.path(context),
      fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, text);
    } finally {
      fs.closeSync(file);
    }
  }

  static clear(context: common.Context): void {
    try {
      const path: string = WidgetSnapshotService.path(context);
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (error) {
      // Widget snapshot cleanup is best effort.
    }
  }

  static read(context: common.Context): WidgetSnapshot | null {
    try {
      const path: string = WidgetSnapshotService.path(context);
      if (!fs.accessSync(path)) {
        return null;
      }
      return JSON.parse(fs.readTextSync(path)) as WidgetSnapshot;
    } catch (error) {
      return null;
    }
  }
}

function currentWeekLabel(semester: Semester, today: Date): string {
  const start: Date = new Date(Date.UTC(
    Number.parseInt(semester.startDate.substring(0, 4), 10),
    Number.parseInt(semester.startDate.substring(5, 7), 10) - 1,
    Number.parseInt(semester.startDate.substring(8, 10), 10)
  ));
  const diff: number = Math.floor((today.getTime() - start.getTime()) / (7 * 86400000));
  const week: number = diff + 1;
  return week >= 1 && week <= semester.totalWeeks ? `第 ${week} 周` : '假期';
}
