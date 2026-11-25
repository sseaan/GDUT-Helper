import { common } from '@kit.AbilityKit';
import { TimetableRepository } from '../../data/TimetableRepository';
import { Course, Semester, formatWeeks } from '../../domain/model/TimetableModels';
import { XlsxParseResult, XlsxParser, XlsxRow } from './XlsxParser';

export interface XlsxPreview {
  semester: Semester;
  courses: Course[];
  duplicates: number;
  warnings: string[];
}

function hash(value: string): string {
  let result: number = 5381;
  for (let i = 0; i < value.length; i++) {
    result = ((result << 5) + result) + value.charCodeAt(i);
    result = result & 0x7fffffff;
  }
  return result.toString(16);
}

function signature(course: Course): string {
  return [course.name, course.weekday, course.startPeriod, course.endPeriod,
    course.weeks.join(','), course.room].join('|');
}

function fromRow(row: XlsxRow, semester: Semester, index: number): Course {
  const now: number = Date.now();
  const key: string = `${semester.id}:${row.weekday}:${row.startPeriod}-${row.endPeriod}:${hash(`${row.name}|${row.room}|${row.weeks.join(',')}`)}`;
  return {
    id: `xlsx:${key}`,
    semesterId: semester.id,
    name: row.name,
    teacher: row.teacher,
    room: row.room,
    weekday: row.weekday,
    startPeriod: row.startPeriod,
    endPeriod: row.endPeriod,
    weeks: row.weeks,
    colorKey: Math.abs(Number.parseInt(hash(row.name), 16)) % 12,
    content: '',
    note: 'XLSX 导入',
    source: 'XLSX',
    createdAt: now,
    updatedAt: now
  };
}

export class XlsxImportService {
  static async preview(context: common.UIAbilityContext, uri: string): Promise<XlsxPreview> {
    const semester: Semester | null = await TimetableRepository.getCurrentSemester(context);
    if (semester === null) {
      throw new Error('请先设置当前学期');
    }
    const parsed: XlsxParseResult = await XlsxParser.parse(context, uri);
    const existing: Course[] = await TimetableRepository.listCourses(context, semester.id);
    const existingSignatures: string[] = existing.map((course: Course) => signature(course));
    const courses: Course[] = [];
    let duplicates: number = 0;
    for (let i = 0; i < parsed.rows.length; i++) {
      const course: Course = fromRow(parsed.rows[i], semester, i);
      course.weeks = course.weeks.filter((week: number) => week >= 1 && week <= semester.totalWeeks);
      if (existingSignatures.indexOf(signature(course)) >= 0) {
        duplicates++;
      } else {
        courses.push(course);
      }
    }
    return {
      semester: semester,
      courses: courses,
      duplicates: duplicates,
      warnings: parsed.warnings
    };
  }

  static async apply(context: common.Context, preview: XlsxPreview): Promise<number> {
    for (const course of preview.courses) {
      course.weeks = formatWeeks(course.weeks).split(',').map((value: string) => Number.parseInt(value, 10));
      await TimetableRepository.saveCourse(context, course);
    }
    return preview.courses.length;
  }
}
