export interface JxfwLesson {
  kcmc: string;
  kcbh: string;
  jxbmc: string;
  jcdm2: string;
  zcs: string;
  xq: string;
  jxcdmcs: string;
  teaxms: string;
  kcrwdm: string;
  sknrjj: string;
}

export interface JxfwWeekLesson {
  kcmc: string;
  kcbh: string;
  jxbmc: string;
  jcdm2: string;
  xq: string;
  jxcdmc: string;
  teaxms: string;
  zc: string;
  sknrjj: string;
}

export interface JxfwWeekDay {
  rq: string;
  xq: string;
  xqmc: string;
}

export interface JxfwWeek {
  lessons: JxfwWeekLesson[];
  days: JxfwWeekDay[];
}

export interface JxfwExam {
  ksrcdm: string;
  kcmc: string;
  kcbh: string;
  ksrq: string;
  kssj: string;
  zc: string;
  xq: string;
  jcdm2: string;
  kscdmc: string;
  xqmc: string;
  kslbmc: string;
  ksaplxmc: string;
  jkteaxms: string;
}

export enum JxfwErrorKind {
  NETWORK = 'NETWORK',
  CREDENTIALS = 'CREDENTIALS',
  CAPTCHA = 'CAPTCHA',
  SMS = 'SMS',
  SESSION = 'SESSION',
  PROTOCOL = 'PROTOCOL'
}

export class JxfwError extends Error {
  readonly kind: JxfwErrorKind;

  constructor(message: string, kind: JxfwErrorKind = JxfwErrorKind.PROTOCOL) {
    super(message);
    this.kind = kind;
  }
}

export interface SyncSummary {
  added: number;
  updated: number;
  deleted: number;
  exams: number;
  startDate: string;
  warnings: string[];
}
