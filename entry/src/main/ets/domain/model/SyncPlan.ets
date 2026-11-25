import { Course, Event } from './TimetableModels';

/** A fully computed full-sync change set, applied only after user confirmation. */
export interface SyncPlan {
  add: Course[];
  update: Course[];
  remove: Course[];
  exams: Event[];
  examsLoaded: boolean;
  hasRemoteCourses: boolean;
  startDate: string;
  warnings: string[];
}
