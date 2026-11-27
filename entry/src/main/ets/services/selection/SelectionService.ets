import { common } from '@kit.AbilityKit';
import { TimetableRepository } from '../../data/TimetableRepository';
import {
  Course,
  CourseException,
  ExpandedCourse,
  Semester
} from '../../domain/model/TimetableModels';
import { expandWeek } from '../../domain/timetable/TimetableEngine';
import { JxfwClient } from '../jxfw/JxfwClient';
import { JxfwError, JxfwErrorKind } from '../jxfw/JxfwModels';
import { SelectionClock } from './SelectionClock';
import { SelectionEngine } from './SelectionEngine';
import {
  SELECTION_MIN_INTERVAL_MS,
  SelectionConflict,
  SelectionCourse,
  SelectionLesson,
  SelectionQueueItem,
  SelectionQueueState,
  SelectionRunPhase,
  SelectionTask
} from './SelectionModels';
import { SelectionParser } from './SelectionParser';
import { SelectionRepository } from './SelectionRepository';

export interface SelectionPageResult {
  courses: SelectionCourse[];
  hasMore: boolean;
}

export interface SelectionPrepareResult {
  ok: boolean;
  message: string;
}

const PAGE_ROWS: number = 20;

/** 选课页面与服务层之间的门面：网络、冲突预检、队列与运行控制。 */
export class SelectionService {
  static async loadCourses(page: number, keyword: string): Promise<SelectionPageResult> {
    const text: string = await new JxfwClient().fetchSelectionCourses(page, PAGE_ROWS, keyword);
    if (SelectionParser.isLoginPage(text)) {
      throw new JxfwError('教务会话已失效，请先到教务同步重新登录', JxfwErrorKind.SESSION);
    }
    const courses: SelectionCourse[] = SelectionParser.parseCourses(text);
    return { courses: courses, hasMore: courses.length >= PAGE_ROWS };
  }

  static async loadLessons(kcrwdm: string): Promise<SelectionLesson[]> {
    const text: string = await new JxfwClient().fetchSelectionLessons(kcrwdm);
    if (SelectionParser.isLoginPage(text)) {
      throw new JxfwError('教务会话已失效，请先到教务同步重新登录', JxfwErrorKind.SESSION);
    }
    return SelectionParser.parseLessons(text);
  }

  /**
   * 与本地当前学期课表做冲突预检。候选课程的周次与本地课程周次有交集、
   * 星期相同且节次重叠时算冲突；停课/调课异常已通过 `expandWeek` 展开。
   */
  static async conflictsFor(context: common.Context,
    lessons: SelectionLesson[]): Promise<SelectionConflict[]> {
    const semester: Semester | null = await TimetableRepository.getCurrentSemester(context);
    if (semester === null) {
      return [];
    }
    const courses: Course[] = await TimetableRepository.listCourses(context, semester.id);
    const exceptions: CourseException[] = await TimetableRepository.listExceptions(context, semester.id);
    const weeks: number[] = [];
    for (const lesson of lessons) {
      if (lesson.week > 0 && weeks.indexOf(lesson.week) < 0) {
        weeks.push(lesson.week);
      }
    }
    const merged: SelectionConflict[] = [];
    for (const week of weeks) {
      const expanded: ExpandedCourse[] = expandWeek(courses, exceptions, week);
      for (const lesson of lessons) {
        if (lesson.week !== week || lesson.periods.length === 0) {
          continue;
        }
        const start: number = SelectionService.minOf(lesson.periods);
        const end: number = SelectionService.maxOf(lesson.periods);
        for (const existing of expanded) {
          if (existing.weekday !== lesson.weekday) {
            continue;
          }
          if (existing.startPeriod > end || start > existing.endPeriod) {
            continue;
          }
          const from: number = Math.max(existing.startPeriod, start);
          const to: number = Math.min(existing.endPeriod, end);
          SelectionService.mergeConflict(merged, existing.name, lesson.weekday, from, to, week);
        }
      }
    }
    return merged;
  }

  private static mergeConflict(target: SelectionConflict[], name: string, weekday: number,
    start: number, end: number, week: number): void {
    let found: SelectionConflict | null = null;
    for (const item of target) {
      if (item.name === name && item.weekday === weekday) {
        found = item;
        break;
      }
    }
    if (found === null) {
      const periods: number[] = [];
      for (let i = start; i <= end; i++) {
        periods.push(i);
      }
      target.push({ name: name, weekday: weekday, periods: periods, weeks: [week] });
      return;
    }
    for (let i = start; i <= end; i++) {
      if (found.periods.indexOf(i) < 0) {
        found.periods.push(i);
      }
    }
    found.periods.sort((a: number, b: number) => a - b);
    if (found.weeks.indexOf(week) < 0) {
      found.weeks.push(week);
    }
    found.weeks.sort((a: number, b: number) => a - b);
  }

  private static minOf(values: number[]): number {
    let min: number = values[0];
    for (const value of values) {
      if (value < min) {
        min = value;
      }
    }
    return min;
  }

  private static maxOf(values: number[]): number {
    let max: number = values[0];
    for (const value of values) {
      if (value > max) {
        max = value;
      }
    }
    return max;
  }

  static async queue(context: common.Context): Promise<SelectionQueueItem[]> {
    return SelectionRepository.listQueue(context);
  }

  static async addToQueue(context: common.Context, course: SelectionCourse): Promise<boolean> {
    return SelectionRepository.addToQueue(context, course);
  }

  static async removeFromQueue(context: common.Context, id: number): Promise<void> {
    await SelectionRepository.removeFromQueue(context, id);
  }

  static async clearQueue(context: common.Context): Promise<void> {
    await SelectionRepository.clearQueue(context);
  }

  static async moveQueueItem(context: common.Context, id: number, delta: number): Promise<void> {
    await SelectionRepository.moveItem(context, id, delta);
  }

  static async loadTask(context: common.Context): Promise<SelectionTask> {
    return SelectionRepository.loadTask(context);
  }

  static async saveTask(context: common.Context, task: SelectionTask): Promise<void> {
    const interval: number = Math.max(SELECTION_MIN_INTERVAL_MS, Math.round(task.intervalMs));
    task.intervalMs = interval;
    await SelectionRepository.saveTask(context, task);
  }

  /** 开抢前的会话检查 + 时钟校准。失败不阻塞（抢课时会自动重登）。 */
  static async prepare(context: common.Context): Promise<SelectionPrepareResult> {
    let message: string = '';
    let ok: boolean = true;
    try {
      await new JxfwClient().fetchSelectionCourses(1, 1, '');
    } catch (error) {
      ok = false;
      if (error instanceof JxfwError) {
        message = error.kind === JxfwErrorKind.SESSION
          ? '教务会话已失效，请先到教务同步重新登录' : error.message;
      } else {
        message = '无法连接教务系统，请检查网络';
      }
    }
    const calibrated: boolean = await SelectionClock.calibrate();
    if (!calibrated && ok) {
      message = '服务器时间校准失败，将按本机时间提交';
    }
    return { ok: ok, message: message };
  }

  /** 启动抢课：把失败项重置为待抢，然后交给引擎。 */
  static async start(context: common.UIAbilityContext): Promise<void> {
    if (SelectionEngine.isActive()) {
      return;
    }
    const task: SelectionTask = await SelectionRepository.loadTask(context);
    const queue: SelectionQueueItem[] = await SelectionRepository.listQueue(context);
    if (queue.length === 0) {
      throw new Error('抢课队列为空，请先添加课程');
    }
    for (const item of queue) {
      if (item.state === SelectionQueueState.FULL || item.state === SelectionQueueState.ERROR) {
        item.state = SelectionQueueState.PENDING;
        await SelectionRepository.updateQueueItem(context, item.id, item.state, '重新排队', item.attempts);
      }
    }
    const refreshed: SelectionQueueItem[] = await SelectionRepository.listQueue(context);
    task.status = SelectionRunPhase.ARMED;
    await SelectionRepository.saveTask(context, task);
    SelectionEngine.start(context, { task: task, queue: refreshed });
  }

  static stop(): void {
    SelectionEngine.stop();
  }

  static isRunning(): boolean {
    return SelectionEngine.isActive();
  }

  /** 进程重启后的收敛：把遗留的“进行中”状态改为已停止。 */
  static async recover(context: common.Context): Promise<void> {
    if (SelectionEngine.isActive()) {
      return;
    }
    await SelectionRepository.markInterrupted(context);
  }
}
