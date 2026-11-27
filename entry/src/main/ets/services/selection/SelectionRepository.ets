import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Database } from '../../data/Database';
import {
  SelectionCourse,
  SelectionLogEntry,
  SelectionQueueItem,
  SelectionQueueState,
  SelectionRunPhase,
  SelectionTask,
  defaultSelectionTask
} from './SelectionModels';

const TASK_ID: number = 1;
const MAX_LOGS: number = 600;

function text(rs: relationalStore.ResultSet, name: string): string {
  const index: number = rs.getColumnIndex(name);
  return index < 0 ? '' : rs.getString(index);
}

function numberValue(rs: relationalStore.ResultSet, name: string): number {
  const index: number = rs.getColumnIndex(name);
  return index < 0 ? 0 : rs.getLong(index);
}

function taskFromRow(rs: relationalStore.ResultSet): SelectionTask {
  return {
    id: numberValue(rs, 'id'),
    termCode: text(rs, 'term_code'),
    startAt: numberValue(rs, 'start_at'),
    intervalMs: numberValue(rs, 'interval_ms'),
    priorityMode: numberValue(rs, 'priority_mode') === 1,
    autoRetry: numberValue(rs, 'auto_retry') === 1,
    syncAfter: numberValue(rs, 'sync_after') === 1,
    status: text(rs, 'status'),
    createdAt: numberValue(rs, 'created_at'),
    updatedAt: numberValue(rs, 'updated_at')
  };
}

function queueFromRow(rs: relationalStore.ResultSet): SelectionQueueItem {
  return {
    id: numberValue(rs, 'id'),
    taskId: numberValue(rs, 'task_id'),
    kcrwdm: text(rs, 'kcrwdm'),
    name: text(rs, 'kcmc'),
    teacher: text(rs, 'teacher'),
    category: text(rs, 'category'),
    capacity: numberValue(rs, 'capacity'),
    chosen: numberValue(rs, 'chosen'),
    position: numberValue(rs, 'position'),
    state: text(rs, 'state'),
    lastMessage: text(rs, 'last_message'),
    attempts: numberValue(rs, 'attempts'),
    updatedAt: numberValue(rs, 'updated_at')
  };
}

/** 选课任务、抢课队列与运行日志的持久化。所有方法共用 `Database` 单例。 */
export class SelectionRepository {
  static async findTask(context: common.Context): Promise<SelectionTask | null> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const result: relationalStore.ResultSet =
      await store.querySql('SELECT * FROM selection_task WHERE id = ?', [TASK_ID]);
    try {
      return result.goToFirstRow() ? taskFromRow(result) : null;
    } finally {
      result.close();
    }
  }

  static async loadTask(context: common.Context): Promise<SelectionTask> {
    const existing: SelectionTask | null = await SelectionRepository.findTask(context);
    if (existing !== null) {
      return existing;
    }
    const task: SelectionTask = defaultSelectionTask();
    await SelectionRepository.saveTask(context, task);
    return task;
  }

  static async saveTask(context: common.Context, task: SelectionTask): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const now: number = Date.now();
    const values: relationalStore.ValuesBucket = {
      'id': TASK_ID,
      'term_code': task.termCode,
      'start_at': task.startAt,
      'interval_ms': task.intervalMs,
      'priority_mode': task.priorityMode ? 1 : 0,
      'auto_retry': task.autoRetry ? 1 : 0,
      'sync_after': task.syncAfter ? 1 : 0,
      'status': task.status,
      'created_at': task.createdAt > 0 ? task.createdAt : now,
      'updated_at': now
    };
    await store.insert('selection_task', values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  static async setTaskStatus(context: common.Context, status: string): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('selection_task');
    predicates.equalTo('id', TASK_ID);
    const values: relationalStore.ValuesBucket = { 'status': status, 'updated_at': Date.now() };
    await store.update(values, predicates);
  }

  static async listQueue(context: common.Context): Promise<SelectionQueueItem[]> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const result: relationalStore.ResultSet =
      await store.querySql('SELECT * FROM selection_queue ORDER BY position ASC, id ASC');
    const items: SelectionQueueItem[] = [];
    try {
      while (result.goToNextRow()) {
        items.push(queueFromRow(result));
      }
      return items;
    } finally {
      result.close();
    }
  }

  static async listPending(context: common.Context): Promise<SelectionQueueItem[]> {
    const items: SelectionQueueItem[] = await SelectionRepository.listQueue(context);
    return items.filter((item: SelectionQueueItem) => item.state === SelectionQueueState.PENDING);
  }

  /** 队列按 kcrwdm 去重，避免重复提交同一门课。 */
  static async addToQueue(context: common.Context, course: SelectionCourse): Promise<boolean> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const existing: relationalStore.ResultSet =
      await store.querySql('SELECT id FROM selection_queue WHERE kcrwdm = ?', [course.kcrwdm]);
    try {
      if (existing.goToFirstRow()) {
        return false;
      }
    } finally {
      existing.close();
    }
    const maxResult: relationalStore.ResultSet =
      await store.querySql('SELECT IFNULL(MAX(position), 0) AS max_pos FROM selection_queue');
    let position: number = 1;
    try {
      if (maxResult.goToFirstRow()) {
        position = numberValue(maxResult, 'max_pos') + 1;
      }
    } finally {
      maxResult.close();
    }
    const values: relationalStore.ValuesBucket = {
      'task_id': TASK_ID,
      'kcrwdm': course.kcrwdm,
      'kcmc': course.name,
      'teacher': course.teacher,
      'category': course.category,
      'capacity': course.capacity,
      'chosen': course.chosen,
      'position': position,
      'state': SelectionQueueState.PENDING,
      'last_message': '',
      'attempts': 0,
      'updated_at': Date.now()
    };
    await store.insert('selection_queue', values);
    return true;
  }

  static async removeFromQueue(context: common.Context, id: number): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    await store.executeSql('DELETE FROM selection_queue WHERE id = ?', [id]);
  }

  static async clearQueue(context: common.Context): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    await store.executeSql('DELETE FROM selection_queue');
  }

  static async moveItem(context: common.Context, id: number, delta: number): Promise<void> {
    const items: SelectionQueueItem[] = await SelectionRepository.listQueue(context);
    const index: number = items.findIndex((item: SelectionQueueItem) => item.id === id);
    const target: number = index + delta;
    if (index < 0 || target < 0 || target >= items.length) {
      return;
    }
    const swapped: SelectionQueueItem[] = items.slice();
    const current: SelectionQueueItem = swapped[index];
    swapped[index] = swapped[target];
    swapped[target] = current;
    const store: relationalStore.RdbStore = await Database.get(context);
    for (let i = 0; i < swapped.length; i++) {
      const values: relationalStore.ValuesBucket = { 'position': i + 1 };
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('selection_queue');
      predicates.equalTo('id', swapped[i].id);
      await store.update(values, predicates);
    }
  }

  static async updateQueueItem(context: common.Context, id: number, state: string,
    message: string, attempts: number): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const values: relationalStore.ValuesBucket = {
      'state': state,
      'last_message': message.length > 200 ? message.substring(0, 200) : message,
      'attempts': attempts,
      'updated_at': Date.now()
    };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('selection_queue');
    predicates.equalTo('id', id);
    await store.update(values, predicates);
  }

  /** 备份恢复用：按原有顺序与状态整条写回。 */
  static async importQueueItem(context: common.Context, item: SelectionQueueItem): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const values: relationalStore.ValuesBucket = {
      'task_id': TASK_ID,
      'kcrwdm': item.kcrwdm,
      'kcmc': item.name,
      'teacher': item.teacher,
      'category': item.category,
      'capacity': item.capacity,
      'chosen': item.chosen,
      'position': item.position,
      'state': item.state,
      'last_message': item.lastMessage,
      'attempts': item.attempts,
      'updated_at': Date.now()
    };
    await store.insert('selection_queue', values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  static async resetQueue(context: common.Context): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    await store.executeSql(
      "UPDATE selection_queue SET state = ?, last_message = '', attempts = 0, updated_at = ?",
      [SelectionQueueState.PENDING, Date.now()]
    );
  }

  static async appendLog(context: common.Context, entry: SelectionLogEntry): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const values: relationalStore.ValuesBucket = {
      'task_id': TASK_ID,
      'at': entry.at,
      'kcrwdm': entry.kcrwdm,
      'name': entry.name,
      'outcome': entry.outcome,
      'message': entry.message.length > 200 ? entry.message.substring(0, 200) : entry.message,
      'rtt_ms': entry.rttMs
    };
    await store.insert('selection_logs', values);
    const countResult: relationalStore.ResultSet =
      await store.querySql('SELECT COUNT(*) AS total FROM selection_logs');
    try {
      if (countResult.goToFirstRow()) {
        const total: number = numberValue(countResult, 'total');
        if (total > MAX_LOGS) {
          await store.executeSql(
            'DELETE FROM selection_logs WHERE id IN (SELECT id FROM selection_logs ORDER BY id ASC LIMIT ?)',
            [total - MAX_LOGS]
          );
        }
      }
    } finally {
      countResult.close();
    }
  }

  static async listLogs(context: common.Context, limit: number): Promise<SelectionLogEntry[]> {
    const store: relationalStore.RdbStore = await Database.get(context);
    const result: relationalStore.ResultSet =
      await store.querySql('SELECT * FROM selection_logs ORDER BY id DESC LIMIT ?', [limit]);
    const logs: SelectionLogEntry[] = [];
    try {
      while (result.goToNextRow()) {
        logs.push({
          at: numberValue(result, 'at'),
          kcrwdm: text(result, 'kcrwdm'),
          name: text(result, 'name'),
          outcome: text(result, 'outcome'),
          message: text(result, 'message'),
          rttMs: numberValue(result, 'rtt_ms')
        });
      }
      return logs;
    } finally {
      result.close();
    }
  }

  static async clearLogs(context: common.Context): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    await store.executeSql('DELETE FROM selection_logs');
  }

  /** 清空本地数据 / 恢复备份前调用。 */
  static async clearAll(context: common.Context): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    await store.executeSql('DELETE FROM selection_logs');
    await store.executeSql('DELETE FROM selection_queue');
    await store.executeSql('DELETE FROM selection_task');
  }

  /** 进程被杀后恢复：把未完成的运行态标记为中断，避免误显示“进行中”。 */
  static async markInterrupted(context: common.Context): Promise<void> {
    const task: SelectionTask = await SelectionRepository.loadTask(context);
    if (task.status === SelectionRunPhase.RUNNING || task.status === SelectionRunPhase.ARMED) {
      await SelectionRepository.setTaskStatus(context, SelectionRunPhase.STOPPED);
    }
  }
}
