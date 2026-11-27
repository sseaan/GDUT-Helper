/** 选课模块数据结构。字段命名与教务 `xsxklist` 返回保持一致，避免二次映射。 */

/** 可选课程行（`xsxklist!getDataList.action` 的 rows 元素）。 */
export interface SelectionCourse {
  /** 课程任务代码，选课提交的唯一键。 */
  kcrwdm: string;
  kcdm: string;
  name: string;
  teacher: string;
  category: string;
  /** 容量 `pkrs`，0 表示教务未给出。 */
  capacity: number;
  /** 已选人数 `jxbrs`。 */
  chosen: number;
  credit: number;
  note: string;
}

/** 单条排课（`xsxklist!getJxrlDataList.action` 的元素）。 */
export interface SelectionLesson {
  jxbmc: string;
  term: string;
  week: number;
  weekday: number;
  periods: number[];
  room: string;
  roomType: string;
  teacher: string;
  contentType: string;
}

/** 选课提交结果分类。 */
export enum SelectionOutcome {
  SUCCESS = 'SUCCESS',
  ALREADY = 'ALREADY',
  FULL = 'FULL',
  CONFLICT = 'CONFLICT',
  NOT_TIME = 'NOT_TIME',
  LIMIT = 'LIMIT',
  SESSION = 'SESSION',
  NETWORK = 'NETWORK',
  UNKNOWN = 'UNKNOWN'
}

export interface SelectionResult {
  outcome: SelectionOutcome;
  message: string;
  raw: string;
}

/** 与本地课表的时间冲突。 */
export interface SelectionConflict {
  name: string;
  weekday: number;
  periods: number[];
  weeks: number[];
}

/** 抢课队列项。 */
export interface SelectionQueueItem {
  id: number;
  taskId: number;
  kcrwdm: string;
  name: string;
  teacher: string;
  category: string;
  capacity: number;
  chosen: number;
  position: number;
  state: string;
  lastMessage: string;
  attempts: number;
  updatedAt: number;
}

export enum SelectionQueueState {
  PENDING = 'PENDING',
  SUCCESS = 'SUCCESS',
  ALREADY = 'ALREADY',
  FULL = 'FULL',
  CONFLICT = 'CONFLICT',
  LIMIT = 'LIMIT',
  ERROR = 'ERROR'
}

export enum SelectionRunPhase {
  IDLE = 'IDLE',
  ARMED = 'ARMED',
  RUNNING = 'RUNNING',
  DONE = 'DONE',
  PARTIAL = 'PARTIAL',
  STOPPED = 'STOPPED',
  FAILED = 'FAILED'
}

/** 抢课任务配置（单任务模型，id 恒为 1）。 */
export interface SelectionTask {
  id: number;
  termCode: string;
  startAt: number;
  intervalMs: number;
  priorityMode: boolean;
  autoRetry: boolean;
  syncAfter: boolean;
  status: string;
  createdAt: number;
  updatedAt: number;
}

export interface SelectionLogEntry {
  at: number;
  kcrwdm: string;
  name: string;
  outcome: string;
  message: string;
  rttMs: number;
}

/** 运行态快照，序列化后放入 AppStorage 供页面订阅。 */
export interface SelectionRunSnapshot {
  phase: string;
  startAt: number;
  offsetMs: number;
  rttMs: number;
  attempts: number;
  pending: number;
  total: number;
  success: number;
  message: string;
  logs: SelectionLogEntry[];
  clockCalibrated: boolean;
  updatedAt: number;
}

/** 一次性运行参数（由页面传入，避免引擎直接依赖 UI 状态）。 */
export interface SelectionRunPlan {
  task: SelectionTask;
  queue: SelectionQueueItem[];
}

export const SELECTION_RUN_KEY: string = 'selectionRunSnapshot';
export const SELECTION_QUEUE_REVISION_KEY: string = 'selectionQueueRevision';

export const SELECTION_MIN_INTERVAL_MS: number = 300;
export const SELECTION_MAX_INTERVAL_MS: number = 3000;
export const SELECTION_MAX_ATTEMPTS: number = 2400;
export const SELECTION_MAX_RUN_MS: number = 30 * 60 * 1000;
export const SELECTION_MAX_LOGS: number = 120;

/** 队列项剩余名额，容量缺失时返回 -1。 */
export function remainingSeats(item: SelectionCourse | SelectionQueueItem): number {
  if (item.capacity <= 0) {
    return -1;
  }
  return item.capacity - item.chosen;
}

export function defaultSelectionTask(): SelectionTask {
  const now: number = Date.now();
  return {
    id: 1,
    termCode: '',
    startAt: now,
    intervalMs: 500,
    priorityMode: true,
    autoRetry: true,
    syncAfter: true,
    status: SelectionRunPhase.IDLE,
    createdAt: now,
    updatedAt: now
  };
}

export function emptyRunSnapshot(): SelectionRunSnapshot {
  return {
    phase: SelectionRunPhase.IDLE,
    startAt: 0,
    offsetMs: 0,
    rttMs: 0,
    attempts: 0,
    pending: 0,
    total: 0,
    success: 0,
    message: '',
    logs: [],
    clockCalibrated: false,
    updatedAt: 0
  };
}
