export interface TzcsItem {
  name: string;
  rawValue: string;
  score: string;
  grade: string;
  weightedScore: number;
  bonusScore: number;
}

export interface TzcsReport {
  year: number;
  studentName: string;
  studentNo: string;
  totalScore: string;
  totalGrade: string;
  items: TzcsItem[];
  historyYears: number[];
}

export interface TzcsCache {
  updatedAt: number;
  reports: TzcsReport[];
}

export interface TzcsChallenge {
  captchaBase64: string;
}

export class TzcsError extends Error {
  kind: string;

  constructor(message: string, kind: string = 'OTHER') {
    super(message);
    this.kind = kind;
  }
}
