import {
  ClassroomBuilding,
  ClassroomOccupancy,
  ClassroomRoom,
  JwcwxError,
  JwcwxErrorKind,
  OccupancyType
} from './JwcwxModels';

interface RawBuilding {
  jzwdm?: string;
  jzwbh?: string;
  jzwmc?: string;
  szxqdm?: string;
  xqmc?: string;
}

interface RawBuildingResponse {
  code?: number;
  message?: string;
  data?: RawBuilding[];
}

interface RawOccupancy {
  dm?: string;
  jxcddm?: string;
  jxcdmc?: string;
  jcdm?: string;
  jcdm2?: string;
  kcmc?: string;
  teaxms?: string;
  jxbmc?: string;
  sknrjj?: string;
  sytype?: string;
  rs?: number;
}

interface RawOccupancyResponse {
  code?: number;
  message?: string;
  data?: RawOccupancy[];
}

function clean(value: string | null | undefined): string {
  return value === null || value === undefined ? '' : value.trim();
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

function stripTags(value: string): string {
  return decodeEntities(value.replace(/<[^>]+>/g, '')).trim();
}

function parsePeriods(jcdm2: string, jcdm: string): number[] {
  const fromComma: number[] = [];
  for (const part of jcdm2.split(',')) {
    const value: number = Number.parseInt(part.trim(), 10);
    if (!Number.isNaN(value) && value >= 1 && value <= 12 && !fromComma.includes(value)) {
      fromComma.push(value);
    }
  }
  if (fromComma.length > 0) {
    return fromComma.sort((a: number, b: number) => a - b);
  }
  const result: number[] = [];
  const text: string = jcdm.trim();
  for (let i = 0; i + 2 <= text.length; i += 2) {
    const value: number = Number.parseInt(text.substring(i, i + 2), 10);
    if (!Number.isNaN(value) && value >= 1 && value <= 12 && !result.includes(value)) {
      result.push(value);
    }
  }
  return result.sort((a: number, b: number) => a - b);
}

function parseType(raw: string): OccupancyType {
  if (raw === '1') {
    return OccupancyType.COURSE;
  }
  if (raw === '2') {
    return OccupancyType.BORROWED;
  }
  if (raw === '3') {
    return OccupancyType.LOCKED;
  }
  if (raw === '4') {
    return OccupancyType.EXAM;
  }
  return OccupancyType.OTHER;
}

function errorMessage(code: number, message: string): JwcwxError {
  return new JwcwxError(`教室查询失败（${code}${message.length > 0 ? ' ' + message : ''}）`,
    JwcwxErrorKind.PROTOCOL);
}

export class JwcwxParser {
  static parseBuildings(json: string): ClassroomBuilding[] {
    let response: RawBuildingResponse;
    try {
      response = JSON.parse(json) as RawBuildingResponse;
    } catch (error) {
      throw new JwcwxError('教学楼数据格式异常', JwcwxErrorKind.PROTOCOL);
    }
    const code: number = response.code ?? -1;
    if (code !== 0) {
      throw errorMessage(code, clean(response.message));
    }
    const rows: RawBuilding[] = response.data ?? [];
    const result: ClassroomBuilding[] = [];
    for (const row of rows) {
      const buildingCode: string = clean(row.jzwdm);
      const name: string = clean(row.jzwmc);
      if (buildingCode.length === 0 || name.length === 0) {
        continue;
      }
      result.push({
        code: buildingCode,
        number: clean(row.jzwbh),
        name: name,
        campusCode: clean(row.szxqdm),
        campusName: clean(row.xqmc)
      });
    }
    return result;
  }

  static parseRooms(html: string): ClassroomRoom[] {
    const result: ClassroomRoom[] = [];
    const seen: string[] = [];
    const trRegex: RegExp = /<tr\b[^>]*>([\s\S]*?)<\/tr>/gi;
    let rowMatch: RegExpExecArray | null = trRegex.exec(html);
    while (rowMatch !== null) {
      const rowHtml: string = rowMatch[1];
      const nameMatch: RegExpExecArray | null =
        /<th\b[^>]*class\s*=\s*["'][^"']*\bjs\b[^"']*["'][^>]*>([\s\S]*?)<\/th>/i.exec(rowHtml);
      if (nameMatch !== null) {
        const name: string = stripTags(nameMatch[1]);
        if (name.length > 0) {
          let roomCode: string = '';
          let capacity: number = 0;
          const tdRegex: RegExp = /<td\b([^>]*)>/gi;
          let tdMatch: RegExpExecArray | null = tdRegex.exec(rowHtml);
          while (tdMatch !== null) {
            const attrs: string = tdMatch[1];
            if (roomCode.length === 0) {
              const codeMatch: RegExpExecArray | null = /\bqk-([^-]+)-/.exec(attrs);
              if (codeMatch !== null) {
                roomCode = codeMatch[1].trim();
              }
            }
            if (capacity === 0) {
              const capacityMatch: RegExpExecArray | null = /\bdata-rnrs\s*=\s*["']?(\d+)["']?/i.exec(attrs);
              if (capacityMatch !== null) {
                capacity = Number.parseInt(capacityMatch[1], 10);
              }
            }
            if (roomCode.length > 0 && capacity > 0) {
              break;
            }
            tdMatch = tdRegex.exec(rowHtml);
          }
          if (roomCode.length > 0 && !seen.includes(roomCode)) {
            seen.push(roomCode);
            result.push({ code: roomCode, name: name, capacity: capacity });
          }
        }
      }
      rowMatch = trRegex.exec(html);
    }
    return result;
  }

  static parseOccupancy(json: string): ClassroomOccupancy[] {
    let response: RawOccupancyResponse;
    try {
      response = JSON.parse(json) as RawOccupancyResponse;
    } catch (error) {
      throw new JwcwxError('教室占用数据格式异常', JwcwxErrorKind.PROTOCOL);
    }
    const code: number = response.code ?? -1;
    if (code !== 0) {
      throw errorMessage(code, clean(response.message));
    }
    const rows: RawOccupancy[] = response.data ?? [];
    const result: ClassroomOccupancy[] = [];
    for (const row of rows) {
      const roomCode: string = clean(row.jxcddm);
      const id: string = clean(row.dm);
      if (roomCode.length === 0 || id.length === 0) {
        continue;
      }
      result.push({
        id: id,
        roomCode: roomCode,
        roomName: clean(row.jxcdmc),
        periods: parsePeriods(clean(row.jcdm2), clean(row.jcdm)),
        periodCode: clean(row.jcdm),
        courseName: clean(row.kcmc),
        teacher: clean(row.teaxms),
        className: clean(row.jxbmc),
        note: clean(row.sknrjj),
        type: parseType(clean(row.sytype)),
        count: row.rs ?? 0
      });
    }
    return result;
  }
}
