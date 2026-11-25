import { GradeSummary, JxfwGrade } from '../../domain/model/GradeModels';

interface GradeRaw {
  xnxqdm?: string;
  kcbh?: string;
  kcmc?: string;
  xf?: string | number;
  zcj?: string | number;
  cjjd?: string | number | null;
  kcdlmc?: string;
  kcxzmc?: string;
  xdfsmc?: string;
  ksxzmc?: string;
  cjfsmc?: string;
  cjztmc?: string;
  cjzt?: string;
  ksqkmc?: string;
  ksqk?: string;
  bz?: string;
}

interface GradeEnvelope {
  total?: number;
  rows?: GradeRaw[];
}

function text(value: string | number | null | undefined): string {
  if (value === null || value === undefined) {
    return '';
  }
  return `${value}`.trim();
}

function numberValue(value: string | number | null | undefined): number {
  if (value === null || value === undefined || `${value}`.trim().length === 0) {
    return 0;
  }
  const parsed: number = Number.parseFloat(`${value}`);
  return Number.isNaN(parsed) ? 0 : parsed;
}

export class JxfwGradeParser {
  static parsePage(raw: string): JxfwGrade[] {
    try {
      const envelope: GradeEnvelope = JSON.parse(raw) as GradeEnvelope;
      const rows: GradeRaw[] = envelope.rows ?? [];
      const result: JxfwGrade[] = [];
      for (const row of rows) {
        const name: string = text(row.kcmc);
        if (name.length === 0) {
          continue;
        }
        result.push({
          term: text(row.xnxqdm),
          code: text(row.kcbh),
          name: name,
          credit: numberValue(row.xf),
          score: text(row.zcj),
          gpa: numberValue(row.cjjd),
          category: text(row.kcdlmc).length > 0 ? text(row.kcdlmc) : text(row.kcxzmc),
          studyMode: text(row.xdfsmc),
          examType: text(row.ksxzmc).length > 0 ? text(row.ksxzmc) : text(row.cjfsmc),
          status: text(row.cjztmc).length > 0 ? text(row.cjztmc)
            : (text(row.cjzt).length > 0 ? text(row.cjzt)
              : (text(row.ksqkmc).length > 0 ? text(row.ksqkmc)
                : (text(row.ksqk).length > 0 ? text(row.ksqk) : text(row.bz))))
        });
      }
      return result;
    } catch (error) {
      return [];
    }
  }

  static isDeferred(grade: JxfwGrade): boolean {
    return grade.status.includes('缓考') || grade.examType.includes('缓考') ||
      grade.score.trim() === '缓考';
  }

  static isUngraded(grade: JxfwGrade): boolean {
    return grade.score.length === 0 && grade.gpa === 0;
  }

  static isPassed(grade: JxfwGrade): boolean {
    if (JxfwGradeParser.isDeferred(grade)) {
      return false;
    }
    if (grade.credit <= 0) {
      return false;
    }
    if (grade.gpa > 0) {
      return true;
    }
    const numeric: number = Number.parseFloat(grade.score);
    if (!Number.isNaN(numeric)) {
      return numeric >= 60;
    }
    return ['不及格', '不合格', '不通过', '未通过', '缺考', '旷考', '作弊', '违纪', '取消资格']
      .indexOf(grade.score) < 0 && grade.score.length > 0;
  }

  static supersededKeys(grades: JxfwGrade[]): string[] {
    const result: string[] = [];
    const groups: string[] = [];
    for (const grade of grades) {
      const key: string = grade.code.length > 0 ? grade.code : grade.name;
      if (!groups.includes(key)) {
        groups.push(key);
      }
    }
    for (const key of groups) {
      const group: JxfwGrade[] = grades.filter((grade: JxfwGrade) =>
        (grade.code.length > 0 ? grade.code : grade.name) === key);
      if (group.length < 2 || !group.some((grade: JxfwGrade) => JxfwGradeParser.isPassed(grade))) {
        continue;
      }
      for (const grade of group) {
        const zeroPlaceholder: boolean = grade.gpa === 0 &&
          ['', '0', '0.0', '缓考', '缺考', '旷考'].indexOf(grade.score.trim()) >= 0;
        if (JxfwGradeParser.isDeferred(grade) || JxfwGradeParser.isUngraded(grade) || zeroPlaceholder) {
          result.push(`${grade.term}|${grade.code}|${grade.name}`);
        }
      }
    }
    return result;
  }

  static summary(grades: JxfwGrade[]): GradeSummary {
    const superseded: string[] = JxfwGradeParser.supersededKeys(grades);
    let totalCredits: number = 0;
    let earnedCredits: number = 0;
    let gpaCredits: number = 0;
    let weightedPoints: number = 0;
    for (const grade of grades) {
      if (superseded.indexOf(`${grade.term}|${grade.code}|${grade.name}`) >= 0) {
        continue;
      }
      if (JxfwGradeParser.isDeferred(grade) || JxfwGradeParser.isUngraded(grade)) {
        continue;
      }
      if (grade.credit <= 0) {
        continue;
      }
      totalCredits += grade.credit;
      if (JxfwGradeParser.isPassed(grade)) {
        earnedCredits += grade.credit;
      }
      if (grade.gpa > 0) {
        gpaCredits += grade.credit;
        weightedPoints += grade.credit * grade.gpa;
      }
    }
    return {
      totalCredits: totalCredits,
      earnedCredits: earnedCredits,
      gpaCredits: gpaCredits,
      weightedGpa: gpaCredits > 0 ? weightedPoints / gpaCredits : 0,
      count: grades.length
    };
  }

  static termLabel(term: string): string {
    const trimmed: string = term.trim();
    if (trimmed.length !== 6) {
      return trimmed.length > 0 ? trimmed : '未知学期';
    }
    const year: number = Number.parseInt(trimmed.substring(0, 4), 10);
    const half: string = trimmed.substring(4);
    if (half === '01') {
      return `${year}-${year + 1} 学年 第一学期`;
    }
    if (half === '02') {
      return `${year}-${year + 1} 学年 第二学期`;
    }
    return term;
  }
}
