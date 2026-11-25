export interface IcsEvent {
  externalId: string;
  title: string;
  startTime: number;
  endTime: number;
  allDay: boolean;
  location: string;
  note: string;
}

export interface IcsParseResult {
  events: IcsEvent[];
  warnings: string[];
}

function unescapeText(value: string): string {
  return value
    .replace(/\\n/gi, '\n')
    .replace(/\\,/g, ',')
    .replace(/\\;/g, ';')
    .replace(/\\\\/g, '\\')
    .trim();
}

function parseDateTime(value: string): number | null {
  const text: string = value.trim();
  const compact: RegExpExecArray | null =
    /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$/.exec(text);
  if (compact === null) {
    return null;
  }
  const year: number = Number.parseInt(compact[1], 10);
  const month: number = Number.parseInt(compact[2], 10) - 1;
  const day: number = Number.parseInt(compact[3], 10);
  const hour: number = compact[4] === undefined ? 0 : Number.parseInt(compact[4], 10);
  const minute: number = compact[5] === undefined ? 0 : Number.parseInt(compact[5], 10);
  const second: number = compact[6] === undefined ? 0 : Number.parseInt(compact[6], 10);
  if (compact[7] === 'Z') {
    return Date.UTC(year, month, day, hour, minute, second);
  }
  return new Date(year, month, day, hour, minute, second).getTime();
}

function isDateOnly(value: string): boolean {
  return /^\d{8}$/.test(value.trim());
}

function parseDuration(value: string): number {
  const text: string = value.trim().toUpperCase();
  if (text.length === 0) {
    return 0;
  }
  const dayMatch: RegExpExecArray | null = /(\d+)D/.exec(text);
  const hourMatch: RegExpExecArray | null = /(\d+)H/.exec(text);
  const minuteMatch: RegExpExecArray | null = /(\d+)M/.exec(text);
  const days: number = dayMatch === null ? 0 : Number.parseInt(dayMatch[1], 10);
  const hours: number = hourMatch === null ? 0 : Number.parseInt(hourMatch[1], 10);
  const minutes: number = minuteMatch === null ? 0 : Number.parseInt(minuteMatch[1], 10);
  return (days * 86400 + hours * 3600 + minutes * 60) * 1000;
}

function shortHash(value: string): string {
  let hash: number = 5381;
  for (let i = 0; i < value.length; i++) {
    hash = ((hash << 5) + hash) + value.charCodeAt(i);
    hash = hash & 0x7fffffff;
  }
  return hash.toString(16);
}

export class IcsParser {
  static parse(source: string): IcsParseResult {
    const events: IcsEvent[] = [];
    const warnings: string[] = [];
    const unfolded: string = source.replace(/\r?\n[ \t]/g, '');
    const lines: string[] = unfolded.split(/\r?\n/);
    let inEvent: boolean = false;
    let properties: Map<string, string> = new Map<string, string>();

    const flush = (): void => {
      if ((properties.get('STATUS') ?? '').toUpperCase() === 'CANCELLED') {
        return;
      }
      const title: string = unescapeText(properties.get('SUMMARY') ?? '');
      const startRaw: string = (properties.get('DTSTART') ?? '').trim();
      const endRaw: string = (properties.get('DTEND') ?? '').trim();
      if (title.length === 0) {
        warnings.push('跳过缺少 SUMMARY 的事件');
        return;
      }
      const start: number | null = parseDateTime(startRaw);
      if (start === null) {
        warnings.push(`跳过时间无效的事件：${title}`);
        return;
      }
      const allDay: boolean = isDateOnly(startRaw);
      let end: number = endRaw.length > 0 ? (parseDateTime(endRaw) ?? 0) : 0;
      if (end <= start) {
        const duration: number = parseDuration(properties.get('DURATION') ?? '');
        end = duration > 0 ? start + duration : (allDay ? start + 86400000 : start + 3600000);
      }
      const uid: string = unescapeText(properties.get('UID') ?? '');
      const externalId: string = `ics:${uid.length > 0 ? uid : shortHash(`${title}|${start}`)}`;
      events.push({
        externalId: externalId,
        title: title,
        startTime: start,
        endTime: end,
        allDay: allDay,
        location: unescapeText(properties.get('LOCATION') ?? ''),
        note: unescapeText(properties.get('DESCRIPTION') ?? '')
      });
    };

    for (const rawLine of lines) {
      const line: string = rawLine.trim();
      if (line.toUpperCase() === 'BEGIN:VEVENT') {
        inEvent = true;
        properties = new Map<string, string>();
        continue;
      }
      if (line.toUpperCase() === 'END:VEVENT') {
        if (inEvent) {
          flush();
        }
        inEvent = false;
        continue;
      }
      if (!inEvent) {
        continue;
      }
      const colon: number = line.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      const left: string = line.substring(0, colon);
      const value: string = line.substring(colon + 1);
      const name: string = left.split(';')[0].toUpperCase();
      if (name === 'DTSTART' || name === 'DTEND' || name === 'SUMMARY' || name === 'LOCATION' ||
        name === 'DESCRIPTION' || name === 'UID') {
        properties.set(name, value);
      }
    }
    return { events: events, warnings: warnings };
  }
}
