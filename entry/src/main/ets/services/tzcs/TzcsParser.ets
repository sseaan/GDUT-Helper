import { TzcsItem, TzcsReport } from './TzcsModels';

function clean(html: string): string {
  return html.replace(/<[^>]*>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'").replace(/\s+/g, ' ').trim();
}

function spanById(html: string, id: string): string {
  const regex: RegExp = new RegExp(`<span[^>]*id=["']${id}["'][^>]*>([\\s\\S]*?)</span>`, 'i');
  const match: RegExpExecArray | null = regex.exec(html);
  return match === null ? '' : clean(match[1]);
}

interface Field {
  action: string;
  hidden: Record<string, string>;
  schoolNo: string;
  schoolCode: string;
}

export class TzcsParser {
  static isLogin(html: string): boolean {
    return html.includes('LAY-user-login') || html.includes('GetCheckCode.aspx') || html.includes('BtnSubmit');
  }

  static loginForm(html: string): Field | null {
    const actionMatch: RegExpExecArray | null = /<form[^>]*\baction\s*=\s*["']([^"']*)["']/i.exec(html);
    const hidden: Record<string, string> = {};
    const inputRegex: RegExp = /<input\b[^>]*>/gi;
    let match: RegExpExecArray | null = inputRegex.exec(html);
    while (match !== null) {
      const tag: string = match[0];
      const typeMatch: RegExpExecArray | null = /type\s*=\s*["']([^"']+)["']/i.exec(tag);
      const type: string = typeMatch === null ? '' : typeMatch[1].toLowerCase();
      if (type === 'hidden') {
        const nameMatch: RegExpExecArray | null = /name\s*=\s*["']([^"']+)["']/i.exec(tag);
        const valueMatch: RegExpExecArray | null = /value\s*=\s*["']([^"']*)["']/i.exec(tag);
        if (nameMatch !== null) {
          hidden[nameMatch[1]] = valueMatch === null ? '' : valueMatch[1];
        }
      }
      match = inputRegex.exec(html);
    }
    const schoolNo: string = hidden['hidSchoolNo'] ?? '';
    const schoolCode: string = hidden['hidCode'] ?? '';
    if (schoolNo.length === 0 || schoolCode.length === 0) {
      return null;
    }
    return {
      action: actionMatch === null ? '' : actionMatch[1].replace(/&amp;/g, '&'),
      hidden: hidden,
      schoolNo: schoolNo,
      schoolCode: schoolCode
    };
  }

  static loginError(html: string): string {
    const divMatch: RegExpExecArray | null =
      /<div[^>]*id=["']divMessage1["'][^>]*>[\s\S]*?<i[^>]*>([\s\S]*?)<\/i>/i.exec(html);
    if (divMatch !== null) {
      const message: string = clean(divMatch[1]);
      if (message.length > 0) {
        return message;
      }
    }
    const alertMatch: RegExpExecArray | null = /alert\s*\(\s*(['"])([\s\S]*?)\1\s*\)/i.exec(html);
    return alertMatch === null ? '' : clean(alertMatch[2]);
  }

  static redirectTarget(html: string): string {
    const match: RegExpExecArray | null =
      /(?:window\.)?location(?:\.href)?\s*=\s*(['"])(.*?)\1/i.exec(html);
    return match === null ? '' : match[2].trim();
  }

  static parseReport(html: string, fallbackYear: number = 0): TzcsReport | null {
    if (TzcsParser.isLogin(html)) {
      return null;
    }
    const titleMatch: RegExpExecArray | null = /<title>\s*(\d{4})年体测成绩\s*<\/title>/i.exec(html);
    const year: number = titleMatch === null ? fallbackYear : Number.parseInt(titleMatch[1], 10);
    if (year === 0) {
      return null;
    }
    const items: TzcsItem[] = [];
    const tableMatch: RegExpExecArray | null =
      /<table[^>]*class\s*=\s*["'][^"']*layui-table[^"']*["'][^>]*>([\s\S]*?)<\/table>/i.exec(html);
    if (tableMatch !== null) {
      const rowRegex: RegExp = /<tr\b[^>]*>([\s\S]*?)<\/tr>/gi;
      let row: RegExpExecArray | null = rowRegex.exec(tableMatch[1]);
      while (row !== null) {
        const cells: string[] = [];
        const cellRegex: RegExp = /<td\b[^>]*>([\s\S]*?)<\/td>/gi;
        let cell: RegExpExecArray | null = cellRegex.exec(row[1]);
        while (cell !== null) {
          cells.push(cell[1]);
          cell = cellRegex.exec(row[1]);
        }
        if (cells.length >= 2) {
          const name: string = clean(cells[0]);
          if (name.length > 0 && name !== '测试项目' && name !== '总分') {
            const valueMatch: RegExpExecArray | null =
              /<span[^>]*class=["'][^"']*div-scroe-value[^"']*["'][^>]*>([\s\S]*?)<\/span>([\s\S]*)/i.exec(cells[1]);
            const rawValue: string = valueMatch === null ? clean(cells[1]) : clean(valueMatch[1]) + clean(valueMatch[2]);
            const scoreMatch: RegExpExecArray | null =
              /<span[^>]*class=["'][^"']*layui-btn-score[^"']*["'][^>]*>([\s\S]*?)<\/span>/i.exec(cells[2] ?? '');
            const gradeMatch: RegExpExecArray | null =
              /<span[^>]*class=["'][^"']*layui-btn-grade[^"']*["'][^>]*>([\s\S]*?)<\/span>/i.exec(cells[2] ?? '');
            const weightedMatch: RegExpExecArray | null =
              /id=["']lbl[^"']*SingleScore["'][^>]*>([\s\S]*?)<\/span>/i.exec(cells[3] ?? '');
            items.push({
              name: name,
              rawValue: rawValue,
              score: scoreMatch === null ? '' : clean(scoreMatch[1]),
              grade: gradeMatch === null ? '' : clean(gradeMatch[1]),
              weightedScore: weightedMatch === null ? 0 : (Number.isNaN(Number.parseFloat(clean(weightedMatch[1]))) ? 0 : Number.parseFloat(clean(weightedMatch[1]))),
              bonusScore: 0
            });
          }
        }
        row = rowRegex.exec(tableMatch[1]);
      }
    }
    const totalScore: string = spanById(html, 'lblTotalScore').replace(/分$/, '').trim();
    const totalGrade: string = spanById(html, 'lblTotalGrade');
    if (items.length === 0 && totalScore.length === 0 && totalGrade.length === 0) {
      return null;
    }
    const years: number[] = [];
    const yearRegex: RegExp = /PHTest_StudentScore_H\.aspx\?DataYear=(\d{4})/gi;
    let yearMatch: RegExpExecArray | null = yearRegex.exec(html);
    while (yearMatch !== null) {
      const value: number = Number.parseInt(yearMatch[1], 10);
      if (years.indexOf(value) < 0) {
        years.push(value);
      }
      yearMatch = yearRegex.exec(html);
    }
    years.sort((a: number, b: number) => b - a);
    return {
      year: year,
      studentName: spanById(html, 'lblStudentName'),
      studentNo: spanById(html, 'lblStudentNO'),
      totalScore: totalScore,
      totalGrade: totalGrade,
      items: items,
      historyYears: years
    };
  }
}
