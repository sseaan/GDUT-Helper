import { Course, CourseException, Event, Period, Semester } from '../../domain/model/TimetableModels';
import { SelectionQueueItem, SelectionTask } from '../selection/SelectionModels';

export interface BackupTombstone {
  semesterId: string;
  courseKey: string;
}

export interface BackupSettings {
  themeMode: string;
  immersiveEnabled: boolean;
  handednessEnabled: boolean;
  showCourseContent: boolean;
  campusNewsEnabled?: boolean;
  campusDataEnabled?: boolean;
  localNotificationsEnabled?: boolean;
  selectionEnabled?: boolean;
  /** 电费查询（Beta，第三方接口），默认关闭。 */
  electricityEnabled?: boolean;
  themeColorId?: string;
  materialLevel?: number;
}

export interface BackupBundle {
  format: string;
  version: number;
  checksum: string;
  schemaVersion: number;
  exportedAt: number;
  semesters: Semester[];
  periods: Period[];
  courses: Course[];
  exceptions: CourseException[];
  events: Event[];
  tombstones: BackupTombstone[];
  grades: string;
  tzcs: string;
  settings: BackupSettings;
  selectionTask?: SelectionTask | null;
  selectionQueue?: SelectionQueueItem[];
}

export interface BackupPreview {
  semesters: number;
  courses: number;
  exceptions: number;
  events: number;
  tombstones: number;
  exportedAt: number;
}

export function previewOf(bundle: BackupBundle): BackupPreview {
  return {
    semesters: bundle.semesters.length,
    courses: bundle.courses.length,
    exceptions: bundle.exceptions.length,
    events: bundle.events.length,
    tombstones: bundle.tombstones.length,
    exportedAt: bundle.exportedAt
  };
}
