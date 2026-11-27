import {
  SelectionCourse,
  SelectionLesson,
  SelectionOutcome,
  SelectionResult
} from './SelectionModels';

interface SelectionRowRaw {
  kcrwdm?: string | number;
  kcdm?: string | number;
  kcmc?: string;
  teaxm?: string;
  kcflmc?: string;
  jxbrs?: string | number;
  pkrs?: string | number;
  xf?: string | number;
  bz?: string;
}

interface SelectionListEnvelope {
  rows?: SelectionRowRaw[];
  total?: number | string;
}

interface SelectionLessonEnvelope {
  rows?: Object[];
  total?: number | string;
}

interface SelectionLessonRaw {
  jxbmc?: string;
  xnxqmc?: string;
  zc?: string | number;
  xq?: string | number;
  jcdm2?: string | number;
  zdjxcdmc?: string;
  zdgnqmc?: string;
  teaxms?: string;
  jxhjmc?: string;
}

/** 解析 `xsxklist` 的课程列表与节次，并把提交结果映射为可判定状态。 */
export class SelectionParser {
  private static text(value: string | number | undefined): string {
    if (value === undefined || value === null) {
      return '';
    }
    return `${value}`.trim();
  }

  private static numberValue(value: string | number | undefined): number {
    if (value === undefined || value === null) {
      return 0;
    }
    const parsed: number = typeof value === 'number' ? value : Number.parseInt(`${value}`.trim(), 10);
    return Number.isNaN(parsed) ? 0 : parsed;
  }

  private static splitNumbers(value: string): number[] {
    const trimmed: string = value.trim();
    if (trimmed.length === 0) {
      return [];
    }
    const result: number[] = [];
    for (const part of trimmed.split(',')) {
      const token: string = part.trim();
      if (token.length === 0) {
        continue;
      }
      const range: string[] = token.split('-');
      if (range.length === 2) {
        const start: number = Number.parseInt(range[0], 10);
        const end: number = Number.parseInt(range[1], 10);
        if (!Number.isNaN(start) && !Number.isNaN(end) && end >= start && end - start <= 30) {
          for (let i = start; i <= end; i++) {
            result.push(i);
          }
          continue;
        }
      }
      const single: number = Number.parseInt(token, 10);
      if (!Number.isNaN(single)) {
        result.push(single);
      }
    }
    result.sort((a: number, b: number) => a - b);
    return result;
  }

  /** 未登录时 jxfw 返回 200 + 登录页 HTML，必须识别出来以免误判为接口异常。 */
  static isLoginPage(text: string): boolean {
    const head: string = text.trimStart();
    if (head.length === 0) {
      return false;
    }
    if (text.includes('使用统一认证中心登录') || text.includes('请输入学号或工号')) {
      return true;
    }
    return head.startsWith('<!DOCTYPE') || head.startsWith('<html');
  }

  static parseCourses(text: string): SelectionCourse[] {
    const trimmed: string = text.trim();
    if (trimmed.length === 0) {
      return [];
    }
    let envelope: SelectionListEnvelope | null = null;
    try {
      envelope = JSON.parse(trimmed) as SelectionListEnvelope;
    } catch (error) {
      return [];
    }
    if (envelope === null || envelope.rows === undefined || !Array.isArray(envelope.rows)) {
      return [];
    }
    const courses: SelectionCourse[] = [];
    for (const row of envelope.rows) {
      const code: string = SelectionParser.text(row.kcrwdm);
      const name: string = SelectionParser.text(row.kcmc);
      if (code.length === 0 || name.length === 0) {
        continue;
      }
      courses.push({
        kcrwdm: code,
        kcdm: SelectionParser.text(row.kcdm),
        name: name,
        teacher: SelectionParser.text(row.teaxm),
        category: SelectionParser.text(row.kcflmc),
        capacity: SelectionParser.numberValue(row.pkrs),
        chosen: SelectionParser.numberValue(row.jxbrs),
        credit: SelectionParser.numberValue(row.xf),
        note: SelectionParser.text(row.bz)
      });
    }
    return courses;
  }

  static parseLessons(text: string): SelectionLesson[] {
    const trimmed: string = text.trim();
    if (trimmed.length === 0) {
      return [];
    }
    let rows: SelectionLessonRaw[] = [];
    try {
      const parsed: Object = JSON.parse(trimmed) as Object;
      if (Array.isArray(parsed)) {
        rows = parsed as SelectionLessonRaw[];
      } else {
        const envelope: SelectionLessonEnvelope = parsed as SelectionLessonEnvelope;
        if (envelope.rows !== undefined && Array.isArray(envelope.rows)) {
          rows = envelope.rows as SelectionLessonRaw[];
        }
      }
    } catch (error) {
      return [];
    }
    const lessons: SelectionLesson[] = [];
    for (const row of rows) {
      const periods: number[] = SelectionParser.splitNumbers(SelectionParser.text(row.jcdm2));
      const day: number = SelectionParser.numberValue(row.xq);
      if (day < 1 || day > 7) {
        continue;
      }
      lessons.push({
        jxbmc: SelectionParser.text(row.jxbmc),
        term: SelectionParser.text(row.xnxqmc),
        week: SelectionParser.numberValue(row.zc),
        weekday: day,
        periods: periods,
        room: SelectionParser.text(row.zdjxcdmc),
        roomType: SelectionParser.text(row.zdgnqmc),
        teacher: SelectionParser.text(row.teaxms),
        contentType: SelectionParser.text(row.jxhjmc)
      });
    }
    lessons.sort((a: SelectionLesson, b: SelectionLesson) => {
      if (a.week !== b.week) {
        return a.week - b.week;
      }
      if (a.weekday !== b.weekday) {
        return a.weekday - b.weekday;
      }
      return (a.periods[0] ?? 0) - (b.periods[0] ?? 0);
    });
    return lessons;
  }

  /**
   * 提交选课的结果判定。教务成功只返回 `1`，失败返回中文原因；
   * 少数版本返回 JSON，这里一并兼容。
   */
  static parseSubmit(text: string): SelectionResult {
    const raw: string = text.trim();
    if (raw.length === 0) {
      return { outcome: SelectionOutcome.UNKNOWN, message: '教务返回空响应', raw: raw };
    }
    if (raw === '1' || raw === '"1"' || raw.toLowerCase() === 'true') {
      return { outcome: SelectionOutcome.SUCCESS, message: '选课成功', raw: raw };
    }
    if (SelectionParser.isLoginPage(raw)) {
      return { outcome: SelectionOutcome.SESSION, message: '教务会话已失效', raw: raw };
    }
    if (raw.startsWith('{')) {
      const envelope: Record<string, Object> | null = SelectionParser.tryJsonObject(raw);
      if (envelope !== null) {
        const success: Object | undefined = envelope['success'];
        const message: Object | undefined = envelope['msg'] ?? envelope['message'];
        const successText: string = success === undefined ? '' : `${success}`.toLowerCase();
        if (successText === 'true' || successText === '1') {
          return { outcome: SelectionOutcome.SUCCESS, message: '选课成功', raw: raw };
        }
        if (message !== undefined) {
          return SelectionParser.classify(`${message}`);
        }
      }
    }
    return SelectionParser.classify(raw);
  }

  private static tryJsonObject(raw: string): Record<string, Object> | null {
    try {
      return JSON.parse(raw) as Record<string, Object>;
    } catch (error) {
      return null;
    }
  }

  /** 中文错误文案 → 稳定状态。 */
  static classify(message: string): SelectionResult {
    const raw: string = message.trim();
    const text: string = raw.length > 120 ? raw.substring(0, 120) : raw;
    if (text === '1') {
      return { outcome: SelectionOutcome.SUCCESS, message: '选课成功', raw: raw };
    }
    if (text.includes('已经选了该门课程') || text.includes('已选该门') ||
      text.includes('已经选过')) {
      return { outcome: SelectionOutcome.ALREADY, message: '已经选上该门课程', raw: raw };
    }
    if (text.includes('人数超出') || text.includes('人数已满') || text.includes('已满') ||
      text.includes('人数达到上限')) {
      return { outcome: SelectionOutcome.FULL, message: '课程已满，继续等待名额', raw: raw };
    }
    if (text.includes('冲突')) {
      return { outcome: SelectionOutcome.CONFLICT, message: text, raw: raw };
    }
    if (text.includes('超出选课要求') || text.includes('超出学分') || text.includes('门数') ||
      text.includes('学分上限')) {
      return { outcome: SelectionOutcome.LIMIT, message: text, raw: raw };
    }
    // 「当前不是选课时间」「未到选课时间」「选课时间未到」「选课已结束」等变体统一归到这里。
    if (text.includes('选课时间') || text.includes('尚未开放') || text.includes('选课未开始') ||
      text.includes('选课已结束')) {
      return { outcome: SelectionOutcome.NOT_TIME, message: '当前不是选课时间', raw: raw };
    }
    if (text.includes('登录') || text.includes('会话')) {
      return { outcome: SelectionOutcome.SESSION, message: '教务会话已失效', raw: raw };
    }
    return { outcome: SelectionOutcome.UNKNOWN, message: text, raw: raw };
  }
}
