/**
 * 电精灵返回的是服务端渲染的 Vue 页面，读数写在
 * `const yffye = ref('17.07')` 这类表达式里，没有 JSON 接口。
 * 这里只做两件事：抽 `ref('...')`、抽月账单里的 `key:'value'` 对。
 */

const REF_PATTERN: RegExp = /(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*ref\(\s*['"]([^'"]*)['"]\s*\)/g;
const BILL_PAIR_PATTERN: RegExp = /([A-Za-z_$][\w$]*)\s*:\s*['"]([^'"]*)['"]/g;
const MONTH_PATTERN: RegExp = /month\s*=\s*ref\(\s*['"]([^'"]+)['"]\s*\)/;
const BILL_WINDOW: number = 2400;

export class ElectricParser {
  /** 抽取页面里所有 `const x = ref('v')` 的字符串常量。 */
  static refs(html: string): Record<string, string> {
    const result: Record<string, string> = {};
    const pattern = new RegExp(REF_PATTERN.source, 'g');
    let match: RegExpExecArray | null = pattern.exec(html);
    while (match !== null) {
      const key: string = match[1];
      const value: string = ElectricParser.clean(match[2]);
      if (value.length > 0) {
        result[key] = value;
      }
      match = pattern.exec(html);
    }
    return result;
  }

  /** 月账单页里 `billData = ref({qcdl:"..", ydl:".."})` 的键值对。 */
  static billValues(html: string): Record<string, string> {
    const result: Record<string, string> = {};
    // 必须定位到赋值语句：模板里还有 `{{ billData.qcdl }}`。
    const start: number = html.search(/billData\s*=\s*ref\(\s*\{/);
    if (start < 0) {
      return result;
    }
    const segment: string = html.substring(start, Math.min(html.length, start + BILL_WINDOW));
    const pattern = new RegExp(BILL_PAIR_PATTERN.source, 'g');
    let match: RegExpExecArray | null = pattern.exec(segment);
    while (match !== null) {
      const key: string = match[1];
      const value: string = ElectricParser.clean(match[2]);
      if (value.length > 0 && result[key] === undefined) {
        result[key] = value;
      }
      match = pattern.exec(segment);
    }
    return result;
  }

  /** 账单页顶部的默认月份。 */
  static billMonth(html: string): string {
    const match: RegExpExecArray | null = MONTH_PATTERN.exec(html);
    return match === null ? '' : ElectricParser.clean(match[1]);
  }

  /** 站点会把 `undefined` / `null` 原样渲染成字符串。 */
  static clean(value: string | undefined): string {
    if (value === undefined || value === null) {
      return '';
    }
    const trimmed: string = value.trim();
    const lower: string = trimmed.toLowerCase();
    if (trimmed.length === 0 || lower === 'undefined' || lower === 'null' || lower === 'none') {
      return '';
    }
    return trimmed;
  }
}
