import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { TimetableRepository } from '../../data/TimetableRepository';
import { Course, CourseException, Event, Semester } from '../../domain/model/TimetableModels';
import { AgendaItem, AgendaKind, agendaForDate } from '../../domain/agenda/AgendaEngine';
import { parseIsoDate } from '../../domain/timetable/TimetableEngine';
import { stableHash } from '../../common/StableHash';

function pad(value: number): string {
  return `${value}`.padStart(2, '0');
}

function escapeText(value: string): string {
  return value
    .replace(/\\/g, '\\\\')
    .replace(/\r?\n/g, '\\n')
    .replace(/,/g, '\\,')
    .replace(/;/g, '\\;');
}

function formatLocalDateTime(ms: number): string {
  const date: Date = new Date(ms);
  return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}T` +
    `${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`;
}

function formatLocalDate(ms: number): string {
  const date: Date = new Date(ms);
  return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}`;
}

function formatUtcStamp(): string {
  const date: Date = new Date();
  return `${date.getUTCFullYear()}${pad(date.getUTCMonth() + 1)}${pad(date.getUTCDate())}T` +
    `${pad(date.getUTCHours())}${pad(date.getUTCMinutes())}${pad(date.getUTCSeconds())}Z`;
}

function nextDate(ms: number): string {
  const date: Date = new Date(ms);
  date.setDate(date.getDate() + 1);
  return formatLocalDate(date.getTime());
}

/** RFC 5545 line folding using UTF-8 byte lengths (Chinese text is folded safely). */
function foldLine(line: string): string {
  const encoder: util.TextEncoder = new util.TextEncoder();
  const bytes: Uint8Array = encoder.encode(line);
  if (bytes.length <= 73) {
    return line;
  }
  const chunks: string[] = [];
  let current: string = '';
  let currentBytes: number = 0;
  for (const char of line) {
    const charBytes: number = encoder.encode(char).length;
    if (currentBytes + charBytes > 73 && current.length > 0) {
      chunks.push(current);
      current = '';
      currentBytes = 0;
    }
    current += char;
    currentBytes += charBytes;
  }
  if (current.length > 0) {
    chunks.push(current);
  }
  return chunks.join('\r\n ');
}

function withLine(value: string): string {
  return foldLine(value);
}

export interface IcsExportResult {
  uri: string;
  count: number;
}

/** 单个事件的完整 iCalendar 文档，供 CalDAV「一个资源一个组件」的服务器使用。 */
export interface IcsEventItem {
  uid: string;
  summary: string;
  body: string;
  /** 去掉 DTSTAMP 后的内容指纹，用于判断远端是否需要重推。 */
  hash: string;
}

/** Exports expanded timetable occurrences as a portable RFC 5545 calendar. */
interface IcsPlan {
  calendarName: string;
  stamp: string;
  items: AgendaItem[];
}

export class IcsExportService {
  /** 导出用：整学期一个文档（`METHOD:PUBLISH`，可直接分享或导入）。 */
  static async build(context: common.Context): Promise<string> {
    const plan: IcsPlan = await IcsExportService.plan(context);
    const buffer: string[] = IcsExportService.calendarHeader(plan.calendarName, true);
    for (const item of plan.items) {
      for (const line of IcsExportService.eventLines(item, plan.stamp, '@gdut-helper')) {
        buffer.push(line);
      }
    }
    buffer.push('END:VCALENDAR');
    buffer.push('');
    return buffer.join('\r\n');
  }

  /**
   * CalDAV 用：一个事件一个文档。
   *
   * Radicale 这类服务器要求「一个资源只能有一个组件」（多 VEVENT 会 400），
   * 所以整学期文档没法直接 PUT 上去，必须拆成单事件资源。
   * UID 后缀和导出脚本区分开，避免用户把导出的 ICS 导入同一日历后 409 冲突。
   */
  static async buildEvents(context: common.Context): Promise<IcsEventItem[]> {
    const plan: IcsPlan = await IcsExportService.plan(context);
    const result: IcsEventItem[] = [];
    for (const item of plan.items) {
      const uid: string = `${item.id}@gdut-helper-caldav`;
      const buffer: string[] = IcsExportService.calendarHeader(plan.calendarName, false);
      for (const line of IcsExportService.eventLines(item, plan.stamp, '@gdut-helper-caldav')) {
        buffer.push(line);
      }
      buffer.push('END:VCALENDAR');
      buffer.push('');
      const body: string = buffer.join('\r\n');
      result.push({
        uid: uid,
        summary: item.title,
        body: body,
        hash: stableHash(IcsExportService.stableContent(body))
      });
    }
    return result;
  }

  /** DTSTAMP 每次构建都会变，比对内容时必须剔除，否则每次都全量重推。 */
  private static stableContent(body: string): string {
    const lines: string[] = body.split('\r\n');
    const kept: string[] = [];
    for (const line of lines) {
      if (!line.startsWith('DTSTAMP:')) {
        kept.push(line);
      }
    }
    return kept.join('\n');
  }

  private static calendarHeader(name: string, publish: boolean): string[] {
    const buffer: string[] = [];
    buffer.push('BEGIN:VCALENDAR');
    buffer.push('VERSION:2.0');
    buffer.push('PRODID:-//GDUT Helper//Timetable Export 1.0//CN');
    buffer.push('CALSCALE:GREGORIAN');
    if (publish) {
      buffer.push('METHOD:PUBLISH');
      buffer.push('X-WR-CALNAME:' + escapeText(name));
      buffer.push('X-WR-TIMEZONE:Asia/Shanghai');
    }
    buffer.push('BEGIN:VTIMEZONE');
    buffer.push('TZID:Asia/Shanghai');
    buffer.push('BEGIN:STANDARD');
    buffer.push('DTSTART:16010101T000000');
    buffer.push('TZOFFSETFROM:+0800');
    buffer.push('TZOFFSETTO:+0800');
    buffer.push('END:STANDARD');
    buffer.push('END:VTIMEZONE');
    return buffer;
  }

  private static async plan(context: common.Context): Promise<IcsPlan> {
    const semester: Semester | null = await TimetableRepository.getCurrentSemester(context);
    if (semester === null) {
      throw new Error('请先设置当前学期');
    }
    if (semester.startDate.length === 0) {
      throw new Error('当前学期缺少开学日期，请先同步或设置学期');
    }
    const courses: Course[] = await TimetableRepository.listCourses(context, semester.id);
    const exceptions: CourseException[] = await TimetableRepository.listExceptions(context, semester.id);
    const events: Event[] = await TimetableRepository.listEvents(context, semester.id);
    const start: Date = parseIsoDate(semester.startDate);
    const weeks: number = Math.max(1, semester.totalWeeks > 0 ? semester.totalWeeks : 20);
    const items: AgendaItem[] = [];
    for (let offset = 0; offset < weeks * 7; offset++) {
      const date: Date = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth(),
        start.getUTCDate() + offset));
      const dayItems: AgendaItem[] = agendaForDate(courses, exceptions, events, semester, date);
      for (const item of dayItems) {
        items.push(item);
      }
    }
    items.sort((a: AgendaItem, b: AgendaItem) => a.startTime - b.startTime);
    return {
      calendarName: `${semester.name} 课程表`,
      stamp: formatUtcStamp(),
      items: items
    };
  }

  private static eventLines(item: AgendaItem, stamp: string, uidSuffix: string): string[] {
    const buffer: string[] = [];
    const isExam: boolean = item.kind === AgendaKind.EXAM;
    const isCourse: boolean = item.kind === AgendaKind.COURSE;
    const alarmMinutes: number = isExam ? 30 : 10;
    buffer.push('BEGIN:VEVENT');
    buffer.push(withLine(`UID:${escapeText(item.id)}${uidSuffix}`));
    buffer.push(`DTSTAMP:${stamp}`);
    if (item.allDay) {
      buffer.push(`DTSTART;VALUE=DATE:${formatLocalDate(item.startTime)}`);
      buffer.push(`DTEND;VALUE=DATE:${nextDate(item.startTime)}`);
    } else {
      buffer.push(`DTSTART;TZID=Asia/Shanghai:${formatLocalDateTime(item.startTime)}`);
      buffer.push(`DTEND;TZID=Asia/Shanghai:${formatLocalDateTime(item.endTime)}`);
    }
    buffer.push(withLine(`SUMMARY:${escapeText(item.title)}`));
    if (item.location.length > 0) {
      buffer.push(withLine(`LOCATION:${escapeText(item.location)}`));
    }
    const description: string = item.subtitle.length > 0
      ? `${item.subtitle}\nGDUT Helper` : 'GDUT Helper';
    buffer.push(withLine(`DESCRIPTION:${escapeText(description)}`));
    buffer.push(`CATEGORIES:${isExam ? '考试' : (isCourse ? '课程' : '日程')}`);
    buffer.push('STATUS:CONFIRMED');
    buffer.push('SEQUENCE:0');
    if (!item.allDay) {
      buffer.push('BEGIN:VALARM');
      buffer.push(`TRIGGER:-PT${alarmMinutes}M`);
      buffer.push('ACTION:DISPLAY');
      buffer.push(withLine(`DESCRIPTION:${escapeText(item.title)}`));
      buffer.push('END:VALARM');
    }
    buffer.push('END:VEVENT');
    return buffer;
  }

  static async exportToFile(context: common.UIAbilityContext): Promise<IcsExportResult> {
    const content: string = await IcsExportService.build(context);
    const pickerInstance = new picker.DocumentViewPicker(context);
    const options = new picker.DocumentSaveOptions();
    const date: Date = new Date();
    const stamp: string = `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}-` +
      `${pad(date.getHours())}${pad(date.getMinutes())}`;
    options.newFileNames = [`gdut-helper-timetable-${stamp}.ics`];
    options.fileSuffixChoices = ['ICS 日历|.ics'];
    const uris: string[] = await pickerInstance.save(options);
    if (uris.length === 0) {
      throw new Error('未选择保存位置');
    }
    const file = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, content);
    } finally {
      fs.closeSync(file);
    }
    let count: number = 0;
    for (const line of content.split('\r\n')) {
      if (line === 'BEGIN:VEVENT') {
        count++;
      }
    }
    return { uri: uris[0], count: count };
  }
}
