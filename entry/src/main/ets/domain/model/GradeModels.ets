export interface JxfwGrade {
  term: string;
  code: string;
  name: string;
  credit: number;
  score: string;
  gpa: number;
  category: string;
  studyMode: string;
  examType: string;
  status: string;
}

export interface GradeSummary {
  totalCredits: number;
  earnedCredits: number;
  gpaCredits: number;
  weightedGpa: number;
  count: number;
}

export interface GradeCache {
  updatedAt: number;
  grades: JxfwGrade[];
}
