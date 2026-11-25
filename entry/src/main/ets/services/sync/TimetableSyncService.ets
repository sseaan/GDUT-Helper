import { common } from '@kit.AbilityKit';
import {
  Course,
  CourseException,
  Event,
  ExceptionType,
  Semester
} from '../../domain/model/TimetableModels';
import { JxfwParser } from '../jxfw/JxfwParser';
import { JxfwClient } from '../jxfw/JxfwClient';
import {
  JxfwError,
  JxfwErrorKind,
  JxfwExam,
  JxfwLesson,
  JxfwWeek,
  JxfwWeekLesson,
  SyncSummary
} from '../jxfw/JxfwModels';
import { TimetableRepository } from '../../data/TimetableRepository';
import { CoursePalette } from '../../common/CoursePalette';
import { SyncPlan } from '../../domain/model/SyncPlan';
import { weekOf } from '../../domain/timetable/TimetableEngine';

/** Imports the GDUT jxfw timetable and exams with deterministic IDs. */
export class TimetableSyncService {
  static async fullSync(context: common.Context, semester: Semester): Promise<SyncSummary> {
    const plan: SyncPlan = await TimetableSyncService.previewFullSync(context, semester);
    return TimetableSyncService.applyFullSync(context, semester, plan);
  }

  /** Fetches and diffs remote data without writing anything. */
  static async previewFullSync(context: common.Context, semester: Semester): Promise<SyncPlan> {
    const term: string = semester.termCode.trim();
    if (term.length === 0) {
      throw new JxfwError('请先填写教务学期代码', JxfwErrorKind.PROTOCOL);
    }
    const client: JxfwClient = new JxfwClient();
    const lessons: JxfwLesson[] = await client.fetchAllLessons(term);
    if (lessons.length === 0) {
      throw new JxfwError('教务系统未返回课表，请确认学期代码或登录状态', JxfwErrorKind.PROTOCOL);
    }

    let startDate: string = '';
    let weekData: JxfwWeek | null = null;
    const currentWeek: number = weekOf(semester.startDate, new Date());
    const contentWeek: number = currentWeek >= 1 && currentWeek <= semester.totalWeeks ? currentWeek : 1;
    try {
      weekData = await client.fetchWeekData(term, contentWeek);
      if (contentWeek === 1) {
        startDate = JxfwParser.firstMonday(weekData);
      }
    } catch (error) {
      if (contentWeek !== 1) {
        try {
          weekData = await client.fetchWeekData(term, 1);
          startDate = JxfwParser.firstMonday(weekData);
        } catch (fallbackError) {
          weekData = null;
        }
      }
    }

    const remoteCourses: Course[] = [];
    const remoteKeys: string[] = [];
    for (const lesson of lessons) {
      const course: Course | null = TimetableSyncService.toCourse(semester, term, lesson);
      if (course === null || remoteKeys.indexOf(course.id) >= 0) {
        continue;
      }
      remoteKeys.push(course.id);
      remoteCourses.push(course);
    }
    if (weekData !== null) {
      TimetableSyncService.mergeWeekContent(remoteCourses, weekData);
    }
    TimetableSyncService.assignColors(remoteCourses);

    const existing: Course[] = (await TimetableRepository.listCourses(context, semester.id))
      .filter((course: Course) => course.source === 'IMPORT');
    const tombstones: string[] = await TimetableRepository.listTombstones(context, semester.id);
    const add: Course[] = [];
    const update: Course[] = [];
    const remove: Course[] = [];

    for (const remote of remoteCourses) {
      if (tombstones.indexOf(remote.id) >= 0) {
        continue;
      }
      const current: Course | undefined =
        existing.find((course: Course) => course.id === remote.id);
      const contentMissing: boolean = current !== undefined &&
        current.content.length === 0 && remote.content.length > 0;
      if (current === undefined) {
        add.push(remote);
      } else if (!TimetableSyncService.sameCourse(current, remote) || contentMissing) {
        update.push({
          id: current.id,
          semesterId: current.semesterId,
          name: remote.name,
          teacher: remote.teacher,
          room: remote.room,
          weekday: remote.weekday,
          startPeriod: remote.startPeriod,
          endPeriod: remote.endPeriod,
          weeks: remote.weeks,
          colorKey: remote.colorKey,
          content: current.content.length > 0 ? current.content : remote.content,
          note: remote.note,
          source: 'IMPORT',
          createdAt: current.createdAt,
          updatedAt: current.updatedAt
        });
      }
    }

    for (const current of existing) {
      if (remoteKeys.indexOf(current.id) < 0 && tombstones.indexOf(current.id) < 0) {
        remove.push(current);
      }
    }

    const warnings: string[] = [];
    let exams: Event[] = [];
    let examsLoaded: boolean = false;
    try {
      const examList: JxfwExam[] = await client.fetchExamList(term);
      exams = [];
      for (const exam of examList) {
        const event: Event | null = TimetableSyncService.toExamEvent(semester.id, term, exam);
        if (event !== null) {
          exams.push(event);
        }
      }
      examsLoaded = true;
    } catch (error) {
      const message: string = error instanceof Error ? error.message : '考试数据同步失败';
      warnings.push(message);
    }

    return {
      add: add,
      update: update,
      remove: remove,
      exams: exams,
      examsLoaded: examsLoaded,
      hasRemoteCourses: remoteCourses.length > 0,
      startDate: startDate,
      warnings: warnings
    };
  }

  /** Writes a previewed plan and returns the stable summary used by the UI. */
  static async applyFullSync(
    context: common.Context,
    semester: Semester,
    plan: SyncPlan
  ): Promise<SyncSummary> {
    for (const course of plan.add) {
      await TimetableRepository.saveCourse(context, course);
    }
    for (const course of plan.update) {
      await TimetableRepository.saveCourse(context, course);
    }
    for (const course of plan.remove) {
      await TimetableRepository.deleteSyncedCourse(context, course.id);
    }
    if (plan.examsLoaded) {
      const externalIds: string[] = [];
      for (const event of plan.exams) {
        await TimetableRepository.upsertEvent(context, event);
        externalIds.push(event.externalId);
      }
      await TimetableRepository.deleteExamEventsExcept(context, semester.id, externalIds);
    }
    if (plan.hasRemoteCourses) {
    }
    if (plan.startDate.length > 0 && plan.startDate !== semester.startDate) {
      await TimetableRepository.updateSemesterStartDate(context, semester.id, plan.startDate);
    }
    return {
      added: plan.add.length,
      updated: plan.update.length,
      deleted: plan.remove.length,
      exams: plan.exams.length,
      startDate: plan.startDate,
      warnings: plan.warnings
    };
  }

  /**
   * Rebuilds this week's exceptions from the jxfw weekly endpoint.
   * Week-level exceptions for synced courses are replaced by server truth.
   */
  static async syncWeek(
    context: common.Context,
    semester: Semester,
    week: number
  ): Promise<SyncSummary> {
    const term: string = semester.termCode.trim();
    if (term.length === 0) {
      throw new JxfwError('请先填写教务学期代码', JxfwErrorKind.PROTOCOL);
    }
    const client: JxfwClient = new JxfwClient();
    const weekData: JxfwWeek = await client.fetchWeekData(term, week);
    if (weekData.lessons.length === 0) {
      throw new JxfwError(`第 ${week} 周没有返回课程数据`, JxfwErrorKind.PROTOCOL);
    }
    const courses: Course[] = (await TimetableRepository.listCourses(context, semester.id))
      .filter((course: Course) => course.source === 'IMPORT');
    const weekExceptions: CourseException[] =
      await TimetableRepository.listExceptions(context, semester.id);
    const manualCourseIds: string[] = weekExceptions
      .filter((item: CourseException) => item.week === week && item.source === 'MANUAL')
      .map((item: CourseException) => item.courseId);
    await TimetableRepository.deleteExceptionsForWeek(context, semester.id, week);

    let added: number = 0;
    let updated: number = 0;
    const warnings: string[] = [];
    const seenNames: string[] = [];
    for (const course of courses) {
      if (course.weeks.indexOf(week) < 0 || manualCourseIds.indexOf(course.id) >= 0) {
        continue;
      }
      const candidates: JxfwWeekLesson[] = weekData.lessons.filter((lesson) =>
        JxfwParser.normalizeCourseName(lesson.kcmc) === course.name);
      let match: JxfwWeekLesson | undefined = candidates.find((lesson) => {
        const p = JxfwParser.periods(lesson.jcdm2);
        const w = Number.parseInt(lesson.xq, 10);
        return p.length > 0 && w === course.weekday &&
          p[0] === course.startPeriod && p[p.length - 1] === course.endPeriod;
      });
      if (match === undefined && candidates.length === 1) {
        match = candidates[0];
      }
      if (match === undefined && candidates.length > 1) {
        if (warnings.indexOf(course.name) < 0) {
          warnings.push(`同名课程存在多个时段，跳过：${course.name}`);
        }
        continue;
      }
      if (match === undefined) {
        if (course.weeks.indexOf(week) >= 0) {
          await TimetableRepository.saveException(context, {
            id: '',
            courseId: course.id,
            week: week,
            type: ExceptionType.CANCEL,
            newWeekday: 0,
            newStartPeriod: 0,
            newEndPeriod: 0,
            newRoom: '',
            note: '教务按周同步',
            source: 'SYNC',
            createdAt: 0,
            updatedAt: 0
          });
          added++;
        }
        continue;
      }
      seenNames.push(JxfwParser.normalizeCourseName(match.kcmc));
      const periods: number[] = JxfwParser.periods(match.jcdm2);
      const weekday: number = Number.parseInt(match.xq, 10);
      const room: string = JxfwParser.normalizeRoom(match.jxcdmc);
      if (periods.length === 0 || weekday < 1 || weekday > 7) {
        continue;
      }
      if (match.sknrjj.length > 0 && match.sknrjj !== course.content) {
        await TimetableRepository.updateCourseContent(context, course.id, match.sknrjj);
      }
      const roomChanged: boolean = room.length > 0 && !TimetableSyncService.sameRoom(course.room, room);
      const changed: boolean = weekday !== course.weekday ||
        periods[0] !== course.startPeriod ||
        periods[periods.length - 1] !== course.endPeriod ||
        roomChanged;
      if (changed) {
        await TimetableRepository.saveException(context, {
          id: '',
          courseId: course.id,
          week: week,
          type: ExceptionType.RESCHEDULE,
          newWeekday: weekday,
          newStartPeriod: periods[0],
          newEndPeriod: periods[periods.length - 1],
          newRoom: room,
          note: '教务按周同步',
          source: 'SYNC',
          createdAt: 0,
          updatedAt: 0
        });
        updated++;
      }
    }
    for (const lesson of weekData.lessons) {
      const lessonName: string = JxfwParser.normalizeCourseName(lesson.kcmc);
      if (seenNames.indexOf(lessonName) < 0 && warnings.indexOf(lessonName) < 0) {
        warnings.push(`未匹配课程：${lessonName}`);
      }
    }
    return {
      added: added,
      updated: updated,
      deleted: 0,
      exams: 0,
      startDate: weekData.days.length > 0 ? weekData.days[0].rq : '',
      warnings: warnings
    };
  }

  private static mergeWeekContent(courses: Course[], week: JxfwWeek): void {
    for (const course of courses) {
      const match: JxfwWeekLesson | undefined = week.lessons.find((lesson) => {
        if (JxfwParser.normalizeCourseName(lesson.kcmc) !== course.name || lesson.sknrjj.length === 0) {
          return false;
        }
        const periods: number[] = JxfwParser.periods(lesson.jcdm2);
        const weekday: number = Number.parseInt(lesson.xq, 10);
        return periods.length > 0 && weekday === course.weekday &&
          periods[0] === course.startPeriod && periods[periods.length - 1] === course.endPeriod;
      });
      if (match !== undefined) {
        course.content = match.sknrjj.trim();
      }
    }
  }

  /** Distinct colors for distinct course names; same course keeps one color. */
  private static assignColors(courses: Course[]): void {
    const names: string[] = [];
    for (const course of courses) {
      if (names.indexOf(course.name) < 0) {
        names.push(course.name);
      }
    }
    names.sort();
    for (const course of courses) {
      course.colorKey = names.indexOf(course.name) % CoursePalette.SIZE;
    }
  }

  private static toCourse(
    semester: Semester,
    term: string,
    lesson: JxfwLesson
  ): Course | null {
    const periods: number[] = JxfwParser.periods(lesson.jcdm2);
    const weeks: number[] = JxfwParser.weeks(lesson.zcs);
    const weekday: number = Number.parseInt(lesson.xq, 10);
    if (periods.length === 0 || weeks.length === 0 || weekday < 1 || weekday > 7) {
      return null;
    }
    const slot: string = `${weekday}-${periods[0]}-${periods[periods.length - 1]}`;
    const key: string = lesson.kcrwdm.trim().length > 0
      ? `${lesson.kcrwdm.trim()}-${slot}`
      : `${lesson.kcmc}-${slot}`;
    return {
      id: `jxfw:${term}:${key}`,
      semesterId: semester.id,
      name: JxfwParser.normalizeCourseName(lesson.kcmc),
      teacher: JxfwParser.cleanTeacher(lesson.teaxms).replace(/[,，]+/g, ' / ').replace(/\s*\/\s*$/, ''),
      room: JxfwParser.normalizeRoom(lesson.jxcdmcs),
      weekday: weekday,
      startPeriod: periods[0],
      endPeriod: periods[periods.length - 1],
      weeks: weeks,
      colorKey: JxfwParser.colorKey(lesson.kcmc),
      content: lesson.sknrjj.trim(),
      note: lesson.jxbmc,
      source: 'IMPORT',
      createdAt: 0,
      updatedAt: 0
    };
  }

  private static toExamEvent(
    semesterId: string,
    term: string,
    exam: JxfwExam
  ): Event | null {
    const times: number[] = JxfwParser.examTimes(exam.ksrq, exam.kssj);
    if (times[0] === 0) {
      return null;
    }
    const place: string = exam.kscdmc.trim();
    return {
      id: '',
      semesterId: semesterId,
      title: `${exam.kcmc} 考试`,
      startTime: times[0],
      endTime: times[1],
      allDay: false,
      location: place,
      note: `${exam.ksaplxmc}${exam.xqmc.length > 0 ? ' · ' + exam.xqmc : ''}`,
      category: 'EXAM',
      source: 'IMPORT',
      externalId: `jxfw-exam:${term}:${exam.ksrcdm}`,
      createdAt: 0,
      updatedAt: 0
    };
  }

  private static sameCourse(a: Course, b: Course): boolean {
    return a.name === b.name &&
      a.teacher === b.teacher &&
      a.room === b.room &&
      a.weekday === b.weekday &&
      a.startPeriod === b.startPeriod &&
      a.endPeriod === b.endPeriod &&
      a.note === b.note &&
      a.colorKey === b.colorKey &&
      TimetableSyncService.sameNumbers(a.weeks, b.weeks);
  }

  private static sameRoom(base: string, weekly: string): boolean {
    if (weekly.length === 0) {
      return true;
    }
    const baseRooms: string[] = base.split(' / ');
    const weeklyRooms: string[] = weekly.split(' / ');
    for (const room of weeklyRooms) {
      if (room.length > 0 && baseRooms.indexOf(room) < 0) {
        return false;
      }
    }
    return true;
  }

  private static sameNumbers(a: number[], b: number[]): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }
}
