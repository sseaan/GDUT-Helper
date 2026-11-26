import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import {
  Course,
  CourseException,
  Event,
  ExceptionType,
  Period,
  Semester,
  formatWeeks,
  parseWeeks
} from '../domain/model/TimetableModels';
import { defaultPeriods } from '../domain/model/Periods';
import { Database } from './Database';

function text(rs: relationalStore.ResultSet, name: string): string {
  const index: number = rs.getColumnIndex(name);
  return index < 0 ? '' : rs.getString(index);
}

function numberValue(rs: relationalStore.ResultSet, name: string): number {
  const index: number = rs.getColumnIndex(name);
  return index < 0 ? 0 : rs.getLong(index);
}

function semesterFromRow(rs: relationalStore.ResultSet): Semester {
  return {
    id: text(rs, 'id'),
    name: text(rs, 'name'),
    startDate: text(rs, 'start_date'),
    totalWeeks: numberValue(rs, 'total_weeks'),
    termCode: text(rs, 'term_code'),
    isCurrent: numberValue(rs, 'is_current') === 1,
    createdAt: numberValue(rs, 'created_at'),
    updatedAt: numberValue(rs, 'updated_at')
  };
}

function courseFromRow(rs: relationalStore.ResultSet): Course {
  return {
    id: text(rs, 'id'),
    semesterId: text(rs, 'semester_id'),
    name: text(rs, 'name'),
    teacher: text(rs, 'teacher'),
    room: text(rs, 'room'),
    weekday: numberValue(rs, 'weekday'),
    startPeriod: numberValue(rs, 'start_period'),
    endPeriod: numberValue(rs, 'end_period'),
    weeks: parseWeeks(text(rs, 'weeks')),
    colorKey: numberValue(rs, 'color_key'),
    content: text(rs, 'content'),
    note: text(rs, 'note'),
    source: text(rs, 'source'),
    createdAt: numberValue(rs, 'created_at'),
    updatedAt: numberValue(rs, 'updated_at')
  };
}

function exceptionFromRow(rs: relationalStore.ResultSet): CourseException {
  return {
    id: text(rs, 'id'),
    courseId: text(rs, 'course_id'),
    week: numberValue(rs, 'week'),
    type: text(rs, 'type') === ExceptionType.CANCEL ? ExceptionType.CANCEL : ExceptionType.RESCHEDULE,
    newWeekday: numberValue(rs, 'new_weekday'),
    newStartPeriod: numberValue(rs, 'new_start_period'),
    newEndPeriod: numberValue(rs, 'new_end_period'),
    newRoom: text(rs, 'new_room'),
    note: text(rs, 'note'),
    source: text(rs, 'source'),
    createdAt: numberValue(rs, 'created_at'),
    updatedAt: numberValue(rs, 'updated_at')
  };
}

function eventFromRow(rs: relationalStore.ResultSet): Event {
  return {
    id: text(rs, 'id'),
    semesterId: text(rs, 'semester_id'),
    title: text(rs, 'title'),
    startTime: numberValue(rs, 'start_time'),
    endTime: numberValue(rs, 'end_time'),
    allDay: numberValue(rs, 'all_day') === 1,
    location: text(rs, 'location'),
    note: text(rs, 'note'),
    category: text(rs, 'category'),
    source: text(rs, 'source'),
    externalId: text(rs, 'external_id'),
    createdAt: numberValue(rs, 'created_at'),
    updatedAt: numberValue(rs, 'updated_at')
  };
}

export class TimetableRepository {
  static async getCurrentSemester(context: common.Context): Promise<Semester | null> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('semesters');
    predicates.equalTo('is_current', 1);
    const result: relationalStore.ResultSet = await store.query(predicates);
    try {
      if (result.goToFirstRow()) {
        return semesterFromRow(result);
      }
      return null;
    } finally {
      result.close();
    }
  }

  static async getSemester(context: common.Context, id: string): Promise<Semester | null> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('semesters');
    predicates.equalTo('id', id);
    const result: relationalStore.ResultSet = await store.query(predicates);
    try {
      return result.goToFirstRow() ? semesterFromRow(result) : null;
    } finally {
      result.close();
    }
  }

  static async findSemesterByTermCode(context: common.Context, termCode: string): Promise<Semester | null> {
    const code: string = termCode.trim();
    if (code.length === 0) {
      return null;
    }
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('semesters');
    predicates.equalTo('term_code', code);
    predicates.orderByDesc('is_current');
    predicates.orderByDesc('updated_at');
    const result: relationalStore.ResultSet = await store.query(predicates);
    try {
      return result.goToFirstRow() ? semesterFromRow(result) : null;
    } finally {
      result.close();
    }
  }

  static async listSemesters(context: common.Context): Promise<Semester[]> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('semesters');
    predicates.orderByDesc('is_current');
    predicates.orderByAsc('created_at');
    const result: relationalStore.ResultSet = await store.query(predicates);
    const semesters: Semester[] = [];
    try {
      while (result.goToNextRow()) {
        semesters.push(semesterFromRow(result));
      }
      return semesters;
    } finally {
      result.close();
    }
  }

  static async listPeriods(context: common.Context, semesterId: string): Promise<Period[]> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('periods');
    predicates.equalTo('semester_id', semesterId);
    predicates.orderByAsc('period_index');
    const result: relationalStore.ResultSet = await store.query(predicates);
    const periods: Period[] = [];
    try {
      while (result.goToNextRow()) {
        periods.push({
          semesterId: semesterId,
          index: numberValue(result, 'period_index'),
          startTime: text(result, 'start_time'),
          endTime: text(result, 'end_time')
        });
      }
      return periods;
    } finally {
      result.close();
    }
  }

  /** Restores a semester preserving its ID and current flag. */
  static async saveSemester(context: common.Context, semester: Semester): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const existing: Semester | null = await TimetableRepository.getSemester(context, semester.id);
    const values: relationalStore.ValuesBucket = {
      'id': semester.id,
      'name': semester.name,
      'start_date': semester.startDate,
      'total_weeks': semester.totalWeeks,
      'term_code': semester.termCode,
      'is_current': semester.isCurrent ? 1 : 0,
      'created_at': semester.createdAt > 0 ? semester.createdAt : Date.now(),
      'updated_at': Date.now()
    };
    if (existing !== null) {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('semesters');
      predicates.equalTo('id', semester.id);
      await store.update(values, predicates);
    } else {
      await store.insert('semesters', values);
    }
    const periods: Period[] = await TimetableRepository.listPeriods(context, semester.id);
    if (periods.length === 0) {
      for (const period of defaultPeriods(semester.id)) {
        const periodValues: relationalStore.ValuesBucket = {
          'semester_id': period.semesterId,
          'period_index': period.index,
          'start_time': period.startTime,
          'end_time': period.endTime
        };
        await store.insert('periods', periodValues);
      }
    }
  }

  static async savePeriod(context: common.Context, period: Period): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const values: relationalStore.ValuesBucket = {
      'semester_id': period.semesterId,
      'period_index': period.index,
      'start_time': period.startTime,
      'end_time': period.endTime
    };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('periods');
    predicates.equalTo('semester_id', period.semesterId);
    predicates.equalTo('period_index', period.index);
    const result: relationalStore.ResultSet = await store.query(predicates);
    let exists: boolean = false;
    try {
      exists = result.goToFirstRow();
    } finally {
      result.close();
    }
    if (exists) {
      await store.update(values, predicates);
    } else {
      await store.insert('periods', values);
    }
  }

  static async clearAllData(context: common.Context): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    await store.executeSql('DELETE FROM course_tombstones');
    await store.executeSql('DELETE FROM events');
    await store.executeSql('DELETE FROM course_exceptions');
    await store.executeSql('DELETE FROM courses');
    await store.executeSql('DELETE FROM periods');
    await store.executeSql('DELETE FROM semesters');
  }

  static async updateSemesterStartDate(
    context: common.Context,
    id: string,
    startDate: string
  ): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('semesters');
    predicates.equalTo('id', id);
    const values: relationalStore.ValuesBucket = { 'start_date': startDate, 'updated_at': Date.now() };
    await store.update(values, predicates);
  }

  static async updateSemesterTermCode(
    context: common.Context,
    id: string,
    termCode: string
  ): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('semesters');
    predicates.equalTo('id', id);
    const values: relationalStore.ValuesBucket = { 'term_code': termCode, 'updated_at': Date.now() };
    await store.update(values, predicates);
  }

  static async updateSemesterTotalWeeks(
    context: common.Context,
    id: string,
    totalWeeks: number
  ): Promise<void> {
    if (totalWeeks < 1 || totalWeeks > 30) {
      return;
    }
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('semesters');
    predicates.equalTo('id', id);
    const values: relationalStore.ValuesBucket = { 'total_weeks': totalWeeks, 'updated_at': Date.now() };
    await store.update(values, predicates);
  }

  /**
   * Finds or creates the local semester for a jxfw term code and makes it current.
   * Used by the sync page so importing a term no longer requires creating a
   * semester by hand. `id` is the preview semester id, reused for a new row.
   */
  static async ensureSemesterForTerm(
    context: common.Context,
    id: string,
    name: string,
    startDate: string,
    totalWeeks: number,
    termCode: string
  ): Promise<Semester> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const code: string = termCode.trim();
    let existing: Semester | null = await TimetableRepository.findSemesterByTermCode(context, code);
    if (existing === null && id.length > 0) {
      existing = await TimetableRepository.getSemester(context, id);
    }
    const now: number = Date.now();
    const actualId: string = existing !== null ? existing.id : id;
    const resolvedName: string = name.trim().length > 0
      ? name.trim() : (existing !== null ? existing.name : code);
    const resolvedStart: string = startDate.trim().length > 0
      ? startDate.trim() : (existing !== null ? existing.startDate : '');
    let resolvedWeeks: number = totalWeeks;
    if (resolvedWeeks < 1) {
      resolvedWeeks = existing !== null && existing.totalWeeks > 0 ? existing.totalWeeks : 20;
    }
    resolvedWeeks = Math.min(30, resolvedWeeks);
    const createdAt: number = existing !== null && existing.createdAt > 0 ? existing.createdAt : now;
    await store.executeSql('UPDATE semesters SET is_current = 0');
    const values: relationalStore.ValuesBucket = {
      'id': actualId,
      'name': resolvedName,
      'start_date': resolvedStart,
      'total_weeks': resolvedWeeks,
      'term_code': code,
      'is_current': 1,
      'created_at': createdAt,
      'updated_at': now
    };
    if (existing !== null) {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('semesters');
      predicates.equalTo('id', actualId);
      await store.update(values, predicates);
    } else {
      await store.insert('semesters', values);
    }
    const periods: Period[] = await TimetableRepository.listPeriods(context, actualId);
    if (periods.length === 0) {
      for (const period of defaultPeriods(actualId)) {
        const periodValues: relationalStore.ValuesBucket = {
          'semester_id': period.semesterId,
          'period_index': period.index,
          'start_time': period.startTime,
          'end_time': period.endTime
        };
        await store.insert('periods', periodValues);
      }
    }
    return {
      id: actualId,
      name: resolvedName,
      startDate: resolvedStart,
      totalWeeks: resolvedWeeks,
      termCode: code,
      isCurrent: true,
      createdAt: createdAt,
      updatedAt: now
    };
  }

  static async createSemester(
    context: common.Context,
    name: string,
    startDate: string,
    totalWeeks: number,
    termCode: string
  ): Promise<Semester> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const id: string = util.generateRandomUUID();
    const now: number = Date.now();
    await store.executeSql('UPDATE semesters SET is_current = 0');
    const values: relationalStore.ValuesBucket = {
      'id': id,
      'name': name,
      'start_date': startDate,
      'total_weeks': totalWeeks,
      'term_code': termCode,
      'is_current': 1,
      'created_at': now,
      'updated_at': now
    };
    await store.insert('semesters', values);
    for (const period of defaultPeriods(id)) {
      const periodValues: relationalStore.ValuesBucket = {
        'semester_id': period.semesterId,
        'period_index': period.index,
        'start_time': period.startTime,
        'end_time': period.endTime
      };
      await store.insert('periods', periodValues);
    }
    return {
      id: id,
      name: name,
      startDate: startDate,
      totalWeeks: totalWeeks,
      termCode: termCode,
      isCurrent: true,
      createdAt: now,
      updatedAt: now
    };
  }

  static async setCurrentSemester(context: common.Context, id: string): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    await store.executeSql('UPDATE semesters SET is_current = 0');
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('semesters');
    predicates.equalTo('id', id);
    const values: relationalStore.ValuesBucket = { 'is_current': 1, 'updated_at': Date.now() };
    await store.update(values, predicates);
  }

  static async listCourses(context: common.Context, semesterId: string): Promise<Course[]> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('courses');
    predicates.equalTo('semester_id', semesterId);
    predicates.orderByAsc('weekday');
    const result: relationalStore.ResultSet = await store.query(predicates);
    const resultList: Course[] = [];
    try {
      while (result.goToNextRow()) {
        resultList.push(courseFromRow(result));
      }
      return resultList;
    } finally {
      result.close();
    }
  }

  static async listAllCourses(context: common.Context): Promise<Course[]> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const result: relationalStore.ResultSet = await store.querySql('SELECT * FROM courses ORDER BY semester_id, weekday');
    const courses: Course[] = [];
    try {
      while (result.goToNextRow()) {
        courses.push(courseFromRow(result));
      }
      return courses;
    } finally {
      result.close();
    }
  }

  static async getCourse(context: common.Context, id: string): Promise<Course | null> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('courses');
    predicates.equalTo('id', id);
    const result: relationalStore.ResultSet = await store.query(predicates);
    try {
      return result.goToFirstRow() ? courseFromRow(result) : null;
    } finally {
      result.close();
    }
  }

  static async updateCourseContent(
    context: common.Context,
    courseId: string,
    content: string
  ): Promise<void> {
    if (content.length === 0) {
      return;
    }
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('courses');
    predicates.equalTo('id', courseId);
    const values: relationalStore.ValuesBucket = { 'content': content, 'updated_at': Date.now() };
    await store.update(values, predicates);
  }

  static async saveCourse(context: common.Context, course: Course): Promise<string> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const id: string = course.id.length > 0 ? course.id : util.generateRandomUUID();
    const now: number = Date.now();
    const values: relationalStore.ValuesBucket = {
      'id': id,
      'semester_id': course.semesterId,
      'name': course.name,
      'teacher': course.teacher,
      'room': course.room,
      'weekday': course.weekday,
      'start_period': course.startPeriod,
      'end_period': course.endPeriod,
      'weeks': formatWeeks(course.weeks),
      'color_key': course.colorKey,
      'content': course.content,
      'note': course.note,
      'source': course.source.length > 0 ? course.source : 'MANUAL',
      'created_at': course.createdAt > 0 ? course.createdAt : now,
      'updated_at': now
    };
    let exists: boolean = false;
    if (course.id.length > 0) {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('courses');
      predicates.equalTo('id', id);
      const result: relationalStore.ResultSet = await store.query(predicates);
      try {
        exists = result.goToFirstRow();
      } finally {
        result.close();
      }
    }
    if (exists) {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('courses');
      predicates.equalTo('id', id);
      await store.update(values, predicates);
    } else {
      await store.insert('courses', values);
    }
    return id;
  }


  /** Removes a synced course without creating a user tombstone. */
  static async deleteSyncedCourse(context: common.Context, courseId: string): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const exceptionPredicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('course_exceptions');
    exceptionPredicates.equalTo('course_id', courseId);
    await store.delete(exceptionPredicates);
    const coursePredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('courses');
    coursePredicates.equalTo('id', courseId);
    await store.delete(coursePredicates);
  }

  static async deleteExceptionsForWeek(
    context: common.Context,
    semesterId: string,
    week: number
  ): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const sql: string =
      'DELETE FROM course_exceptions WHERE week = ? AND source = ? AND course_id IN ' +
      '(SELECT id FROM courses WHERE semester_id = ? AND source = ?)';
    await store.executeSql(sql, [week, 'SYNC', semesterId, 'IMPORT']);
  }

  static async deleteExamEventsExcept(
    context: common.Context,
    semesterId: string,
    externalIds: string[]
  ): Promise<number> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('events');
    predicates.equalTo('semester_id', semesterId);
    predicates.equalTo('category', 'EXAM');
    predicates.equalTo('source', 'IMPORT');
    if (externalIds.length > 0) {
      predicates.notIn('external_id', externalIds);
    }
    return store.delete(predicates);
  }

  static async deleteCourse(context: common.Context, courseId: string): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const existing: Course | null = await TimetableRepository.getCourse(context, courseId);
    if (existing !== null && existing.source === 'IMPORT') {
      await TimetableRepository.addTombstone(context, existing.semesterId, existing.id);
    }
    const exceptionPredicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('course_exceptions');
    exceptionPredicates.equalTo('course_id', courseId);
    await store.delete(exceptionPredicates);
    const coursePredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('courses');
    coursePredicates.equalTo('id', courseId);
    await store.delete(coursePredicates);
  }

  static async listExceptions(context: common.Context, semesterId: string): Promise<CourseException[]> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const result: relationalStore.ResultSet = await store.querySql(
      'SELECT e.* FROM course_exceptions e INNER JOIN courses c ON e.course_id = c.id WHERE c.semester_id = ?',
      [semesterId]
    );
    const resultList: CourseException[] = [];
    try {
      while (result.goToNextRow()) {
        resultList.push(exceptionFromRow(result));
      }
      return resultList;
    } finally {
      result.close();
    }
  }

  static async getException(
    context: common.Context,
    courseId: string,
    week: number
  ): Promise<CourseException | null> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('course_exceptions');
    predicates.equalTo('course_id', courseId);
    predicates.equalTo('week', week);
    const result: relationalStore.ResultSet = await store.query(predicates);
    try {
      return result.goToFirstRow() ? exceptionFromRow(result) : null;
    } finally {
      result.close();
    }
  }

  static async saveException(
    context: common.Context,
    exception: CourseException
  ): Promise<string> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const existing: CourseException | null =
      await TimetableRepository.getException(context, exception.courseId, exception.week);
    const id: string = existing !== null ? existing.id : util.generateRandomUUID();
    const now: number = Date.now();
    const values: relationalStore.ValuesBucket = {
      'id': id,
      'course_id': exception.courseId,
      'week': exception.week,
      'type': exception.type,
      'new_weekday': exception.newWeekday,
      'new_start_period': exception.newStartPeriod,
      'new_end_period': exception.newEndPeriod,
      'new_room': exception.newRoom,
      'note': exception.note,
      'source': exception.source.length > 0 ? exception.source : 'MANUAL',
      'created_at': existing !== null ? existing.createdAt : now,
      'updated_at': now
    };
    if (existing !== null) {
      const predicates: relationalStore.RdbPredicates =
        new relationalStore.RdbPredicates('course_exceptions');
      predicates.equalTo('id', id);
      await store.update(values, predicates);
    } else {
      await store.insert('course_exceptions', values);
    }
    return id;
  }

  static async deleteExceptionById(context: common.Context, id: string): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('course_exceptions');
    predicates.equalTo('id', id);
    await store.delete(predicates);
  }

  static async listEvents(context: common.Context, semesterId: string): Promise<Event[]> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('events');
    predicates.equalTo('semester_id', semesterId);
    predicates.orderByAsc('start_time');
    const result: relationalStore.ResultSet = await store.query(predicates);
    const events: Event[] = [];
    try {
      while (result.goToNextRow()) {
        events.push(eventFromRow(result));
      }
      return events;
    } finally {
      result.close();
    }
  }

  static async getEvent(context: common.Context, id: string): Promise<Event | null> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('events');
    predicates.equalTo('id', id);
    const result: relationalStore.ResultSet = await store.query(predicates);
    try {
      return result.goToFirstRow() ? eventFromRow(result) : null;
    } finally {
      result.close();
    }
  }

  static async deleteEvent(context: common.Context, id: string): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('events');
    predicates.equalTo('id', id);
    await store.delete(predicates);
  }

  static async upsertEvent(context: common.Context, event: Event): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const now: number = Date.now();
    const values: relationalStore.ValuesBucket = {
      'id': event.id.length > 0 ? event.id : util.generateRandomUUID(),
      'semester_id': event.semesterId,
      'title': event.title,
      'start_time': event.startTime,
      'end_time': event.endTime,
      'all_day': event.allDay ? 1 : 0,
      'location': event.location,
      'note': event.note,
      'category': event.category,
      'source': event.source,
      'external_id': event.externalId.length > 0 ? event.externalId : `manual:${util.generateRandomUUID()}`,
      'created_at': event.createdAt > 0 ? event.createdAt : now,
      'updated_at': now
    };
    if (event.externalId.length > 0) {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('events');
      predicates.equalTo('semester_id', event.semesterId);
      predicates.equalTo('external_id', event.externalId);
      const result: relationalStore.ResultSet = await store.query(predicates);
      let existingId: string = '';
      try {
        if (result.goToFirstRow()) {
          existingId = text(result, 'id');
        }
      } finally {
        result.close();
      }
      if (existingId.length > 0) {
        values['id'] = existingId;
        const updatePredicates: relationalStore.RdbPredicates =
          new relationalStore.RdbPredicates('events');
        updatePredicates.equalTo('id', existingId);
        await store.update(values, updatePredicates);
        return;
      }
    }
    await store.insert('events', values);
  }

  static async addTombstone(
    context: common.Context,
    semesterId: string,
    courseKey: string
  ): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    await store.executeSql(
      'INSERT OR REPLACE INTO course_tombstones(semester_id, course_key, created_at) VALUES(?, ?, ?)',
      [semesterId, courseKey, Date.now()]
    );
  }

  static async clearTombstones(context: common.Context, semesterId: string): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('course_tombstones');
    predicates.equalTo('semester_id', semesterId);
    await store.delete(predicates);
  }

  static async listTombstones(context: common.Context, semesterId: string): Promise<string[]> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('course_tombstones');
    predicates.equalTo('semester_id', semesterId);
    const result: relationalStore.ResultSet = await store.query(predicates);
    const keys: string[] = [];
    try {
      while (result.goToNextRow()) {
        keys.push(text(result, 'course_key'));
      }
      return keys;
    } finally {
      result.close();
    }
  }

  static async listAllExceptions(context: common.Context): Promise<CourseException[]> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const result: relationalStore.ResultSet = await store.querySql('SELECT * FROM course_exceptions');
    const exceptions: CourseException[] = [];
    try {
      while (result.goToNextRow()) {
        exceptions.push(exceptionFromRow(result));
      }
      return exceptions;
    } finally {
      result.close();
    }
  }

  static async listAllEvents(context: common.Context): Promise<Event[]> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const result: relationalStore.ResultSet = await store.querySql('SELECT * FROM events ORDER BY start_time');
    const events: Event[] = [];
    try {
      while (result.goToNextRow()) {
        events.push(eventFromRow(result));
      }
      return events;
    } finally {
      result.close();
    }
  }


}
