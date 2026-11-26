import { JxfwExam, JxfwLesson, JxfwWeek, JxfwWeekDay, JxfwWeekLesson } from './JxfwModels';

interface LessonRaw {
  kcmc?: string;
  kcbh?: string;
  jxbmc?: string;
  jcdm2?: string;
  zcs?: string;
  xq?: string;
  jxcdmcs?: string;
  teaxms?: string;
  kcrwdm?: string;
  sknrjj?: string;
}

interface WeekLessonRaw {
  kcmc?: string;
  kcbh?: string;
  jxbmc?: string;
  jcdm2?: string;
  xq?: string;
  jxcdmc?: string;
  teaxms?: string;
  zc?: string;
  sknrjj?: string;
}

interface WeekDayRaw {
  rq?: string;
  xq?: string;
  xqmc?: string;
}

interface ExamRaw {
  ksrcdm?: string;
  kcmc?: string;
  kcbh?: string;
  ksrq?: string;
  kssj?: string;
  zc?: string;
  xq?: string;
  jcdm2?: string;
  kscdmc?: string;
  xqmc?: string;
  kslbmc?: string;
  ksaplxmc?: string;
  jkteaxms?: string;
}

interface WeekEnvelope {
  data?: Object[];
}

interface ExamEnvelope {
  total?: number;
  rows?: ExamRaw[];
}

export class JxfwParser {
  static parseLessons(html: string): JxfwLesson[] {
    const clean: string = html.replace(/<!--[\s\S]*?-->/g, '');
    const match: RegExpExecArray | null = /var\s+kbxx\s*=\s*(\[[\s\S]*?\]);/.exec(clean);
    if (match === null) {
      return [];
    }
    try {
      const raw: LessonRaw[] = JSON.parse(match[1]) as LessonRaw[];
      const lessons: JxfwLesson[] = [];
      for (const item of raw) {
        if ((item.kcmc ?? '').length === 0) {
          continue;
        }
        lessons.push({
          kcmc: item.kcmc ?? '',
          kcbh: item.kcbh ?? '',
          jxbmc: item.jxbmc ?? '',
          jcdm2: item.jcdm2 ?? '',
          zcs: item.zcs ?? '',
          xq: item.xq ?? '',
          jxcdmcs: item.jxcdmcs ?? '',
          teaxms: item.teaxms ?? '',
          kcrwdm: item.kcrwdm ?? '',
          sknrjj: JxfwParser.cleanContent(item.sknrjj ?? '')
        });
      }
      return lessons;
    } catch (error) {
      return [];
    }
  }

  static parseWeek(json: string): JxfwWeek {
    try {
      const parsed: Object = JSON.parse(json) as Object;
      let raw: Object[] = [];
      if (Array.isArray(parsed)) {
        raw = parsed as Object[];
      } else {
        raw = (parsed as WeekEnvelope).data ?? [];
      }
      if (raw.length < 1) {
        return { lessons: [], days: [] };
      }
      const rawLessons: WeekLessonRaw[] = raw[0] as WeekLessonRaw[];
      const rawDays: WeekDayRaw[] = raw.length > 1 ? raw[1] as WeekDayRaw[] : [];
      const lessons: JxfwWeekLesson[] = [];
      for (const item of rawLessons) {
        if ((item.kcmc ?? '').length === 0) {
          continue;
        }
        lessons.push({
          kcmc: item.kcmc ?? '',
          kcbh: item.kcbh ?? '',
          jxbmc: item.jxbmc ?? '',
          jcdm2: item.jcdm2 ?? '',
          xq: item.xq ?? '',
          jxcdmc: item.jxcdmc ?? '',
          teaxms: item.teaxms ?? '',
          zc: item.zc ?? '',
          sknrjj: JxfwParser.cleanContent(item.sknrjj ?? '')
        });
      }
      const days: JxfwWeekDay[] = [];
      for (const item of rawDays) {
        days.push({ rq: item.rq ?? '', xq: item.xq ?? '', xqmc: item.xqmc ?? '' });
      }
      return { lessons: lessons, days: days };
    } catch (error) {
      return { lessons: [], days: [] };
    }
  }

  static parseExams(json: string): JxfwExam[] {
    try {
      const envelope: ExamEnvelope = JSON.parse(json) as ExamEnvelope;
      const rows: ExamRaw[] = envelope.rows ?? [];
      const exams: JxfwExam[] = [];
      for (const row of rows) {
        if ((row.ksrcdm ?? '').length === 0 || (row.kcmc ?? '').length === 0) {
          continue;
        }
        exams.push({
          ksrcdm: row.ksrcdm ?? '',
          kcmc: row.kcmc ?? '',
          kcbh: row.kcbh ?? '',
          ksrq: row.ksrq ?? '',
          kssj: row.kssj ?? '',
          zc: row.zc ?? '',
          xq: row.xq ?? '',
          jcdm2: row.jcdm2 ?? '',
          kscdmc: row.kscdmc ?? '',
          xqmc: row.xqmc ?? '',
          kslbmc: row.kslbmc ?? '',
          ksaplxmc: row.ksaplxmc ?? '',
          jkteaxms: row.jkteaxms ?? ''
        });
      }
      return exams;
    } catch (error) {
      return [];
    }
  }

  static firstMonday(week: JxfwWeek): string {
    for (const day of week.days) {
      if ((day.xqmc === '1' || day.xq === '1') && /^\d{4}-\d{2}-\d{2}$/.test(day.rq)) {
        return day.rq;
      }
    }
    return '';
  }

  static periods(text: string): number[] {
    return JxfwParser.numberList(text, 1, 12);
  }

  static weeks(text: string): number[] {
    return JxfwParser.numberList(text, 1, 30);
  }

  /** Accepts both "01,02" and "01-04" forms; returns sorted unique values. */
  private static numberList(text: string, min: number, max: number): number[] {
    const result: number[] = [];
    for (const part of text.split(',')) {
      const token: string = part.trim();
      if (token.length === 0) {
        continue;
      }
      const dash: number = token.indexOf('-');
      const start: number = Number.parseInt(dash > 0 ? token.substring(0, dash) : token, 10);
      const end: number = dash > 0 ? Number.parseInt(token.substring(dash + 1), 10) : start;
      if (Number.isNaN(start) || Number.isNaN(end)) {
        continue;
      }
      const from: number = Math.max(min, Math.min(start, end));
      const to: number = Math.min(max, Math.max(start, end));
      for (let value = from; value <= to; value++) {
        if (result.indexOf(value) < 0) {
          result.push(value);
        }
      }
    }
    result.sort((a: number, b: number) => a - b);
    return result;
  }

  static cleanTeacher(text: string): string {
    return text.replace(/\[[^\]]*\]/g, '').trim();
  }

  static normalizeRoom(text: string): string {
    const rooms: string[] = [];
    for (const item of text.split(',')) {
      const room: string = item.trim();
      if (room.length > 0 && rooms.indexOf(room) < 0) {
        rooms.push(room);
      }
    }
    rooms.sort();
    return rooms.join(' / ');
  }

  /** sknrjj is HTML-ish; strip tags/entities before it reaches cards. */
  static cleanContent(value: string): string {
    let text: string = value.replace(/<[^>]*>/g, ' ');
    text = text.replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&sect;/g, '§')
      .replace(/&hellip;/g, '…')
      .replace(/&mdash;/g, '—')
      .replace(/&ndash;/g, '–');
    text = text.replace(/&#(\d+);/g, (match: string, code: string) => {
      return String.fromCharCode(Number.parseInt(code, 10));
    });
    return text.replace(/\s+/g, ' ').trim();
  }

  /** Remove the class sequence suffix from PE course names: 体育（1）→ 体育. */
  static normalizeCourseName(name: string): string {
    return name.trim().replace(/^体育[（(]\d+[)）]$/, '体育');
  }

  /**
   * Extracts the student name from jxfw pages. Different pages expose it as an
   * input value, a labelled cell, or plain text; try the common shapes and keep
   * only Han-character names so labels such as 学号/性别 are never shown.
   */
  static studentName(html: string): string {
    if (html.length === 0) {
      return '';
    }
    const inputPatterns: RegExp[] = [
      /<input[^>]*(?:id|name)\s*=\s*["'](?:xm|xsxm|sname|studentName|cnname|xm_zh)["'][^>]*value\s*=\s*["']([^"']{2,20})["']/i,
      /<input[^>]*value\s*=\s*["']([^"']{2,20})["'][^>]*(?:id|name)\s*=\s*["'](?:xm|xsxm|sname|studentName|cnname|xm_zh)["']/i,
      /<(?:span|div|td|label)[^>]*(?:id|name)\s*=\s*["'](?:xm|xsxm|sname|studentName|cnname)["'][^>]*>([^<]{2,20})</i
    ];
    for (const pattern of inputPatterns) {
      const match: RegExpExecArray | null = pattern.exec(html);
      if (match !== null) {
        const name: string = JxfwParser.validStudentName(match[1]);
        if (name.length > 0) {
          return name;
        }
      }
    }
    const text: string = html
      .replace(/<script[\s\S]*?<\/script>/gi, ' ')
      .replace(/<style[\s\S]*?<\/style>/gi, ' ')
      .replace(/<!--[\s\S]*?-->/g, ' ')
      .replace(/<[^>]+>/g, ' ')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/\s+/g, ' ');
    const textPatterns: RegExp[] = [
      /(?:学生姓名|姓\s*名)\s*[：:]\s*([\u3400-\u9fff·]{2,12})/,
      /(?:学生姓名|姓\s*名)\s+([\u3400-\u9fff·]{2,12})/,
      /(?:欢迎[您你]?)\s*[：:，,\s]+([\u3400-\u9fff·]{2,12})/
    ];
    for (const pattern of textPatterns) {
      const match: RegExpExecArray | null = pattern.exec(text);
      if (match !== null) {
        const name: string = JxfwParser.validStudentName(match[1]);
        if (name.length > 0) {
          return name;
        }
      }
    }
    return '';
  }

  private static validStudentName(value: string): string {
    const name: string = value.replace(/\s+/g, '').trim();
    if (!/^[\u3400-\u9fff·]{2,12}$/.test(name)) {
      return '';
    }
    const blocked: string[] = ['姓名', '学生姓名', '学号', '性别', '出生', '民族', '学院',
      '专业', '班级', '校区', '学籍', '在读', '欢迎'];
    for (const word of blocked) {
      if (name.includes(word)) {
        return '';
      }
    }
    return name;
  }

  static colorKey(name: string): number {
    let hash: number = 0;
    for (let i = 0; i < name.length; i++) {
      hash = (hash * 31 + name.charCodeAt(i)) & 0x7fffffff;
    }
    return hash % 7;
  }

  static examTimes(date: string, time: string): number[] {
    const dateParts: string[] = date.split('-');
    if (dateParts.length !== 3) {
      return [0, 0];
    }
    const times: string[] = time.split('--');
    const startParts: string[] = (times[0] ?? '00:00').trim().split(':');
    const endParts: string[] = (times.length > 1 ? times[1] : times[0]).trim().split(':');
    const year: number = Number.parseInt(dateParts[0], 10);
    const month: number = Number.parseInt(dateParts[1], 10) - 1;
    const day: number = Number.parseInt(dateParts[2], 10);
    const startHour: number = Number.parseInt(startParts[0] ?? '0', 10);
    const startMinute: number = Number.parseInt(startParts[1] ?? '0', 10);
    const endHour: number = Number.parseInt(endParts[0] ?? '0', 10);
    const endMinute: number = Number.parseInt(endParts[1] ?? '0', 10);
    return [
      Date.UTC(year, month, day, startHour, startMinute),
      Date.UTC(year, month, day, endHour, endMinute)
    ];
  }
}
