import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';

export interface XlsxRow {
  name: string;
  teacher: string;
  room: string;
  weekday: number;
  startPeriod: number;
  endPeriod: number;
  weeks: number[];
}

export interface XlsxParseResult {
  rows: XlsxRow[];
  warnings: string[];
}

function decodeEntities(value: string): string {
  return value
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

function textOf(xml: string): string {
  return decodeEntities(xml.replace(/<[^>]+>/g, '')).trim();
}

function readFile(path: string): string {
  try {
    return fs.readTextSync(path);
  } catch (error) {
    return '';
  }
}

function parseSharedStrings(xml: string): string[] {
  const result: string[] = [];
  const siRegex: RegExp = /<si\b[^>]*>([\s\S]*?)<\/si>/gi;
  let match: RegExpExecArray | null = siRegex.exec(xml);
  while (match !== null) {
    const texts: string[] = [];
    const tRegex: RegExp = /<t\b[^>]*>([\s\S]*?)<\/t>/gi;
    let textMatch: RegExpExecArray | null = tRegex.exec(match[1]);
    while (textMatch !== null) {
      texts.push(textOf(textMatch[1]));
      textMatch = tRegex.exec(match[1]);
    }
    result.push(texts.join(''));
    match = siRegex.exec(xml);
  }
  return result;
}

function columnIndex(reference: string): number {
  const letters: string = (reference.match(/^[A-Z]+/) ?? [''])[0];
  let value: number = 0;
  for (let i = 0; i < letters.length; i++) {
    value = value * 26 + (letters.charCodeAt(i) - 64);
  }
  return value - 1;
}

function parseSheet(xml: string, shared: string[]): string[][] {
  const rows: string[][] = [];
  const rowRegex: RegExp = /<row\b[^>]*>([\s\S]*?)<\/row>/gi;
  let rowMatch: RegExpExecArray | null = rowRegex.exec(xml);
  while (rowMatch !== null) {
    const cells: string[] = [];
    const cellRegex: RegExp = /<c\b([^>]*)>([\s\S]*?)<\/c>/gi;
    let cellMatch: RegExpExecArray | null = cellRegex.exec(rowMatch[1]);
    while (cellMatch !== null) {
      const attrs: string = cellMatch[1];
      const body: string = cellMatch[2];
      const reference: string = (/\br\s*=\s*["']([A-Z]+\d+)["']/i.exec(attrs) ?? ['', ''])[1];
      const type: string = (/\bt\s*=\s*["']([^"']+)["']/i.exec(attrs) ?? ['', ''])[1];
      let value: string = '';
      if (type === 'inlineStr') {
        value = textOf(body);
      } else {
        const valueMatch: RegExpExecArray | null = /<v>([\s\S]*?)<\/v>/i.exec(body);
        value = valueMatch === null ? '' : textOf(valueMatch[1]);
        if (type === 's') {
          const index: number = Number.parseInt(value, 10);
          value = Number.isNaN(index) || index < 0 || index >= shared.length ? '' : shared[index];
        }
      }
      const column: number = reference.length > 0 ? columnIndex(reference) : cells.length;
      while (cells.length <= column) {
        cells.push('');
      }
      cells[column] = value;
      cellMatch = cellRegex.exec(rowMatch[1]);
    }
    rows.push(cells);
    rowMatch = rowRegex.exec(xml);
  }
  return rows;
}

function normalizeHeader(value: string): string {
  return value.replace(/\s+/g, '').replace(/[：:]/g, '').toLowerCase();
}

function findColumn(headers: string[], names: string[]): number {
  for (let i = 0; i < headers.length; i++) {
    if (names.indexOf(headers[i]) >= 0) {
      return i;
    }
  }
  return -1;
}

function parseWeekday(value: string): number {
  const text: string = value.trim();
  const map: string[] = ['', '一', '二', '三', '四', '五', '六', '日'];
  const numeric: number = Number.parseInt(text.replace(/[^0-9]/g, ''), 10);
  if (!Number.isNaN(numeric) && numeric >= 1 && numeric <= 7) {
    return numeric;
  }
  for (let i = 1; i < map.length; i++) {
    if (text.includes(map[i]) || text.includes(`星期${map[i]}`) || text.includes(`周${map[i]}`)) {
      return i;
    }
  }
  const upper: string = text.toUpperCase();
  const english: string[] = ['', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  for (let i = 1; i < english.length; i++) {
    if (upper.startsWith(english[i])) {
      return i;
    }
  }
  return 0;
}

function parsePeriodPart(value: string): number {
  const digits: string = value.replace(/[^0-9]/g, '');
  if (digits.length === 0) {
    return 0;
  }
  const parsed: number = Number.parseInt(digits, 10);
  return Number.isNaN(parsed) ? 0 : parsed;
}

function parsePeriodRange(value: string): number[] {
  const text: string = value.replace(/\s/g, '').replace(/节/g, '');
  const range: RegExpExecArray | null = /^(\d+)[-~—至](\d+)$/.exec(text);
  if (range !== null) {
    return [Number.parseInt(range[1], 10), Number.parseInt(range[2], 10)];
  }
  const compact: RegExpExecArray | null = /^(\d{2})(\d{2})$/.exec(text);
  if (compact !== null) {
    return [Number.parseInt(compact[1], 10), Number.parseInt(compact[2], 10)];
  }
  const single: number = parsePeriodPart(text);
  return single > 0 ? [single, single] : [0, 0];
}

function parseWeeks(value: string): number[] {
  let text: string = value.replace(/[周\s]/g, '').replace(/（/g, '(').replace(/）/g, ')');
  let odd: boolean = text.includes('单');
  let even: boolean = text.includes('双');
  text = text.replace(/\(?[单双]周?\)?/g, '');
  const result: number[] = [];
  for (const part of text.split(/[,，、;；]/)) {
    const token: string = part.trim();
    if (token.length === 0) {
      continue;
    }
    const range: RegExpExecArray | null = /^(\d+)[-~—至](\d+)$/.exec(token);
    if (range !== null) {
      const start: number = Number.parseInt(range[1], 10);
      const end: number = Number.parseInt(range[2], 10);
      for (let week = start; week <= end; week++) {
        if ((!odd && !even) || (odd && week % 2 === 1) || (even && week % 2 === 0)) {
          result.push(week);
        }
      }
    } else {
      const single: number = Number.parseInt(token, 10);
      if (!Number.isNaN(single) && single > 0) {
        if ((!odd && !even) || (odd && single % 2 === 1) || (even && single % 2 === 0)) {
          result.push(single);
        }
      }
    }
  }
  return result.filter((week: number, index: number) => week > 0 && result.indexOf(week) === index)
    .sort((a: number, b: number) => a - b);
}

export class XlsxParser {
  static async parse(context: common.UIAbilityContext, uri: string): Promise<XlsxParseResult> {
    const stat = fs.statSync(uri);
    if (stat.size > 15 * 1024 * 1024) {
      throw new Error('表格超过 15MB 限制');
    }
    const stamp: string = `${Date.now()}`;
    const sourcePath: string = `${context.cacheDir}/import-${stamp}.xlsx`;
    const outputDir: string = `${context.cacheDir}/xlsx-${stamp}`;
    const sourceFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const destination = fs.openSync(sourcePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
    try {
      fs.copyFileSync(sourceFile.fd, destination.fd);
    } finally {
      fs.closeSync(sourceFile);
      fs.closeSync(destination);
    }
    try {
      fs.mkdirSync(outputDir);
    } catch (error) {
      // Directory may already exist.
    }
    await zlib.decompressFile(sourcePath, outputDir, {});
    const shared: string[] = parseSharedStrings(readFile(`${outputDir}/xl/sharedStrings.xml`));
    let sheetPath: string = `${outputDir}/xl/worksheets/sheet1.xml`;
    try {
      const files: string[] = fs.listFileSync(`${outputDir}/xl/worksheets`);
      const sheet: string | undefined = files.find((name: string) => name.startsWith('sheet') && name.endsWith('.xml'));
      if (sheet !== undefined) {
        sheetPath = `${outputDir}/xl/worksheets/${sheet}`;
      }
    } catch (error) {
      // Fall back to sheet1.xml.
    }
    const rows: string[][] = parseSheet(readFile(sheetPath), shared);
    return XlsxParser.fromRows(rows);
  }

  private static fromRows(rows: string[][]): XlsxParseResult {
    const warnings: string[] = [];
    if (rows.length === 0) {
      throw new Error('表格为空');
    }
    if (rows.length > 5000) {
      throw new Error('表格行数超过 5000 行限制');
    }
    let headerIndex: number = -1;
    let headers: string[] = [];
    let nameColumn: number = -1;
    let weekdayColumn: number = -1;
    let weeksColumn: number = -1;
    let roomColumn: number = -1;
    let teacherColumn: number = -1;
    let startColumn: number = -1;
    let endColumn: number = -1;
    let periodsColumn: number = -1;
    for (let i = 0; i < Math.min(12, rows.length); i++) {
      const normalized: string[] = rows[i].map((cell: string) => normalizeHeader(cell));
      const name = findColumn(normalized, ['课程名称', '课程名', '课程', '科目', '名称']);
      const weekday = findColumn(normalized, ['星期', '周几', '上课星期', '星期几', 'day', 'weekday']);
      const weeks = findColumn(normalized, ['周次', '上课周次', '教学周', '周']);
      if (name >= 0 && (weekday >= 0 || weeks >= 0)) {
        headerIndex = i;
        headers = normalized;
        nameColumn = name;
        weekdayColumn = weekday;
        weeksColumn = weeks;
        roomColumn = findColumn(normalized, ['教室', '地点', '上课地点', 'room']);
        teacherColumn = findColumn(normalized, ['教师', '老师', '任课教师', 'teacher']);
        startColumn = findColumn(normalized, ['开始节次', '起始节次', '开始节', 'start']);
        endColumn = findColumn(normalized, ['结束节次', '终止节次', '结束节', 'end']);
        periodsColumn = findColumn(normalized, ['节次', '上课节次', '节']);
        break;
      }
    }
    if (headerIndex < 0) {
      throw new Error('未找到课程/星期/周次表头');
    }
    const parsedRows: XlsxRow[] = [];
    for (let i = headerIndex + 1; i < rows.length; i++) {
      const row: string[] = rows[i];
      const name: string = row[nameColumn] ?? '';
      if (name.trim().length === 0 || name.includes('合计') || name.includes('备注')) {
        continue;
      }
      const weekday: number = weekdayColumn >= 0 ? parseWeekday(row[weekdayColumn] ?? '') : 0;
      if (weekday < 1 || weekday > 7) {
        warnings.push(`第 ${i + 1} 行星期无效，已跳过：${name}`);
        continue;
      }
      let periods: number[] = [0, 0];
      if (startColumn >= 0) {
        periods[0] = parsePeriodPart(row[startColumn] ?? '');
        periods[1] = endColumn >= 0 ? parsePeriodPart(row[endColumn] ?? '') : periods[0];
      } else if (periodsColumn >= 0) {
        periods = parsePeriodRange(row[periodsColumn] ?? '');
      }
      if (periods[0] <= 0) {
        warnings.push(`第 ${i + 1} 行节次无效，已跳过：${name}`);
        continue;
      }
      if (periods[1] < periods[0] || periods[1] > 12) {
        periods[1] = periods[0];
      }
      let weeks: number[] = weeksColumn >= 0 ? parseWeeks(row[weeksColumn] ?? '') : [];
      if (weeks.length === 0) {
        for (let week = 1; week <= 16; week++) {
          weeks.push(week);
        }
        warnings.push(`第 ${i + 1} 行周次为空，按 1-16 周导入：${name}`);
      }
      parsedRows.push({
        name: name.trim(),
        teacher: teacherColumn >= 0 ? (row[teacherColumn] ?? '').trim() : '',
        room: roomColumn >= 0 ? (row[roomColumn] ?? '').trim() : '',
        weekday: weekday,
        startPeriod: periods[0],
        endPeriod: periods[1],
        weeks: weeks
      });
    }
    return { rows: XlsxParser.mergeRows(parsedRows), warnings: warnings };
  }

  private static mergeRows(rows: XlsxRow[]): XlsxRow[] {
    const result: XlsxRow[] = [];
    for (const row of rows) {
      const existing: XlsxRow | undefined = result.find((item: XlsxRow) =>
        item.name === row.name && item.weekday === row.weekday && item.room === row.room &&
        item.teacher === row.teacher && item.weeks.join(',') === row.weeks.join(',') &&
        (row.startPeriod === item.endPeriod + 1 || row.endPeriod === item.startPeriod - 1));
      if (existing !== undefined) {
        existing.startPeriod = Math.min(existing.startPeriod, row.startPeriod);
        existing.endPeriod = Math.max(existing.endPeriod, row.endPeriod);
      } else {
        result.push({
          name: row.name,
          teacher: row.teacher,
          room: row.room,
          weekday: row.weekday,
          startPeriod: row.startPeriod,
          endPeriod: row.endPeriod,
          weeks: row.weeks.slice()
        });
      }
    }
    return result;
  }
}
