import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TimetableRepository } from '../../data/TimetableRepository';
import { Semester } from '../../domain/model/TimetableModels';
import { JxfwClient } from '../jxfw/JxfwClient';
import { JxfwError, JxfwErrorKind } from '../jxfw/JxfwModels';
import { LocalNotificationService } from '../notification/LocalNotificationService';
import { TimetableSyncService } from '../sync/TimetableSyncService';
import { TimetableState } from '../../state/TimetableState';
import { SelectionState } from '../../state/SelectionState';
import { SelectionClock } from './SelectionClock';
import {
  SELECTION_MAX_ATTEMPTS,
  SELECTION_MAX_LOGS,
  SELECTION_MAX_RUN_MS,
  SELECTION_RUN_KEY,
  SelectionLogEntry,
  SelectionOutcome,
  SelectionQueueItem,
  SelectionQueueState,
  SelectionResult,
  SelectionRunPhase,
  SelectionRunPlan,
  SelectionRunSnapshot,
  SelectionTask,
  emptyRunSnapshot
} from './SelectionModels';
import { SelectionParser } from './SelectionParser';
import { SelectionRepository } from './SelectionRepository';

const TAG: string = 'SelectionEngine';
const LEAD_MS: number = 120;
const END_SETTLE_MS: number = 2000;

interface AttemptRecord {
  result: SelectionResult;
  rttMs: number;
}

/** patch() 的可选字段集合；按需覆盖快照，避免整对象重建。 */
interface SnapshotPatch {
  phase?: string;
  startAt?: number;
  offsetMs?: number;
  rttMs?: number;
  attempts?: number;
  pending?: number;
  success?: number;
  message?: string;
  clockCalibrated?: boolean;
}

/**
 * 抢课引擎：单线程顺序提交、按服务器时钟准点发射、可随时中断。
 *
 * 生命周期与页面解耦（静态状态 + AppStorage 快照），页面退出或重进都能看到
 * 同一场运行；进程被杀后由 `SelectionRepository.markInterrupted` 收敛状态。
 */
export class SelectionEngine {
  private static active: boolean = false;
  private static cancelRequested: boolean = false;
  private static snapshot: SelectionRunSnapshot = emptyRunSnapshot();
  private static screenKept: boolean = false;
  private static suspendRequestId: number = -1;
  private static context: common.Context | null = null;
  private static runContext: common.UIAbilityContext | null = null;

  static isActive(): boolean {
    return SelectionEngine.active;
  }

  static current(): SelectionRunSnapshot {
    return SelectionEngine.snapshot;
  }

  /** 校准服务器时钟；失败时保留上次偏移或 0。 */
  static async calibrate(): Promise<boolean> {
    const ok: boolean = await SelectionClock.calibrate();
    SelectionEngine.patch({
      offsetMs: SelectionClock.getOffsetMs(),
      rttMs: SelectionClock.getRttMs(),
      clockCalibrated: SelectionClock.isCalibrated()
    });
    return ok;
  }

  static stop(message: string = '已手动停止'): void {
    if (!SelectionEngine.active) {
      return;
    }
    SelectionEngine.cancelRequested = true;
    SelectionEngine.patch({ message: message });
  }

  /**
   * 启动一次抢课。调用后立即返回（内部异步执行），结果通过 AppStorage 快照推送。
   * 页面不需要 await，避免阻塞 UI。
   */
  static start(context: common.UIAbilityContext, plan: SelectionRunPlan): void {
    if (SelectionEngine.active) {
      return;
    }
    SelectionEngine.active = true;
    SelectionEngine.cancelRequested = false;
    SelectionEngine.context = context;
    SelectionEngine.runContext = context;
    SelectionEngine.snapshot = emptyRunSnapshot();
    SelectionEngine.snapshot.total = plan.queue.filter((item: SelectionQueueItem) =>
      item.state === SelectionQueueState.PENDING).length;
    SelectionEngine.snapshot.startAt = plan.task.startAt;
    SelectionEngine.snapshot.phase = SelectionRunPhase.ARMED;
    SelectionEngine.publish();
    SelectionEngine.run(context, plan).catch((error: Error) => {
      hilog.error(0x0000, TAG, 'run failed: %{public}s', error.message);
      SelectionEngine.finish(context, SelectionRunPhase.FAILED, error.message);
    });
  }

  private static async run(context: common.UIAbilityContext, plan: SelectionRunPlan): Promise<void> {
    const task: SelectionTask = plan.task;
    let pending: SelectionQueueItem[] = plan.queue.filter((item: SelectionQueueItem) =>
      item.state === SelectionQueueState.PENDING);
    try {
      await SelectionRepository.setTaskStatus(context, SelectionRunPhase.ARMED);
      // 距离开始超过 1 分钟时先不常亮，避免一直亮屏耗电；进入最后一分钟再打开。
      if (SelectionClock.toLocal(task.startAt) - Date.now() <= 60000) {
        await SelectionEngine.keepScreenOn(context, true);
      }
      if (SelectionClock.isStale()) {
        await SelectionEngine.calibrate();
      }
      SelectionEngine.patch({
        offsetMs: SelectionClock.getOffsetMs(),
        rttMs: SelectionClock.getRttMs(),
        clockCalibrated: SelectionClock.isCalibrated(),
        message: '正在确认教务会话…'
      });
      try {
        await SelectionEngine.warmUp(pending);
      } catch (error) {
        SelectionEngine.finish(context, SelectionRunPhase.FAILED,
          '教务会话已失效，请回到「教务同步」重新登录后再试');
        return;
      }
      if (pending.length === 0) {
        SelectionEngine.finish(context, SelectionRunPhase.DONE, '队列为空，无需抢课');
        return;
      }
      const targetLocal: number = SelectionClock.toLocal(task.startAt) - LEAD_MS;
      const wait: boolean = await SelectionEngine.waitForTarget(targetLocal);
      if (!wait) {
        SelectionEngine.finish(context, SelectionRunPhase.STOPPED, '已手动停止');
        return;
      }
      await SelectionRepository.setTaskStatus(context, SelectionRunPhase.RUNNING);
      SelectionEngine.patch({ phase: SelectionRunPhase.RUNNING, message: '正在提交选课请求…' });

      const deadline: number = Date.now() + SELECTION_MAX_RUN_MS;
      let attempts: number = 0;
      let success: number = 0;
      let notTime: number = 0;
      let consecutiveErrors: number = 0;
      let unknownInRow: number = 0;
      let stopMessage: string = '';
      let fatal: boolean = false;

      while (!SelectionEngine.cancelRequested && pending.length > 0 &&
        attempts < SELECTION_MAX_ATTEMPTS && Date.now() < deadline) {
        const round: SelectionQueueItem[] = task.priorityMode ? [pending[0]] : pending.slice();
        for (const item of round) {
          if (SelectionEngine.cancelRequested) {
            break;
          }
          attempts++;
          const record: AttemptRecord = await SelectionEngine.attempt(item);
          const outcome: SelectionOutcome = record.result.outcome;
          item.attempts++;
          item.lastMessage = record.result.message;
          SelectionEngine.log(item, record);
          SelectionEngine.patch({ attempts: attempts, pending: pending.length, message: record.result.message });

          if (outcome === SelectionOutcome.SUCCESS || outcome === SelectionOutcome.ALREADY) {
            item.state = outcome === SelectionOutcome.SUCCESS
              ? SelectionQueueState.SUCCESS : SelectionQueueState.ALREADY;
            await SelectionRepository.updateQueueItem(context, item.id, item.state,
              record.result.message, item.attempts);
            pending = pending.filter((entry: SelectionQueueItem) => entry.id !== item.id);
            success++;
            SelectionState.bumpQueue();
            notTime = 0;
            consecutiveErrors = 0;
            unknownInRow = 0;
            SelectionEngine.patch({ success: success, pending: pending.length });
            await LocalNotificationService.notify(context, '抢课成功', `${item.name} 已选上`, 'selection-ok');
            continue;
          }
          if (outcome === SelectionOutcome.FULL) {
            item.state = SelectionQueueState.FULL;
            consecutiveErrors = 0;
            unknownInRow = 0;
            await SelectionRepository.updateQueueItem(context, item.id, item.state,
              record.result.message, item.attempts);
            SelectionEngine.patch({ pending: pending.length });
            continue;
          }
          if (outcome === SelectionOutcome.CONFLICT) {
            item.state = SelectionQueueState.CONFLICT;
            await SelectionRepository.updateQueueItem(context, item.id, item.state,
              record.result.message, item.attempts);
            pending = pending.filter((entry: SelectionQueueItem) => entry.id !== item.id);
            SelectionState.bumpQueue();
            continue;
          }
          if (outcome === SelectionOutcome.LIMIT) {
            item.state = SelectionQueueState.LIMIT;
            await SelectionRepository.updateQueueItem(context, item.id, item.state,
              record.result.message, item.attempts);
            pending = pending.filter((entry: SelectionQueueItem) => entry.id !== item.id);
            SelectionState.bumpQueue();
            stopMessage = `超出选课要求：${record.result.message}`;
            fatal = true;
            SelectionEngine.cancelRequested = true;
            break;
          }
          if (outcome === SelectionOutcome.NOT_TIME) {
            // 到点前 120ms 就会开始试，刚开放时前几发经常被判“不是选课时间”，
            // 因此这里只短暂停顿、保持高频逼近，而不是退避 2 秒错过开抢窗口。
            notTime++;
            if (notTime >= 20) {
              stopMessage = '连续 20 次返回“不是选课时间”，选课可能尚未开放';
              fatal = true;
              SelectionEngine.cancelRequested = true;
              break;
            }
            consecutiveErrors = 0;
            unknownInRow = 0;
            await SelectionRepository.updateQueueItem(context, item.id, item.state,
              record.result.message, item.attempts);
            await SelectionClock.sleep(Math.min(task.intervalMs, 400));
            continue;
          }
          if (outcome === SelectionOutcome.SESSION) {
            await SelectionRepository.updateQueueItem(context, item.id, item.state,
              record.result.message, item.attempts);
            stopMessage = '教务会话已失效，请回到「教务同步」重新登录后再试';
            fatal = true;
            SelectionEngine.cancelRequested = true;
            break;
          }
          if (outcome === SelectionOutcome.NETWORK) {
            await SelectionRepository.updateQueueItem(context, item.id, item.state,
              record.result.message, item.attempts);
            consecutiveErrors++;
            if (consecutiveErrors >= 8) {
              stopMessage = '连续 8 次网络失败，已停止';
              fatal = true;
              SelectionEngine.cancelRequested = true;
              break;
            }
            await SelectionClock.sleep(Math.min(1000 * consecutiveErrors, 5000));
            continue;
          }
          unknownInRow++;
          if (!task.autoRetry) {
            item.state = SelectionQueueState.ERROR;
            await SelectionRepository.updateQueueItem(context, item.id, item.state,
              record.result.message, item.attempts);
            pending = pending.filter((entry: SelectionQueueItem) => entry.id !== item.id);
            unknownInRow = 0;
            continue;
          }
          await SelectionRepository.updateQueueItem(context, item.id, item.state,
            record.result.message, item.attempts);
          if (unknownInRow >= 6) {
            stopMessage = `教务连续返回未知结果：${record.result.message}`;
            fatal = true;
            SelectionEngine.cancelRequested = true;
            break;
          }
          await SelectionClock.sleep(Math.min(task.intervalMs * 2, 3000));
        }
        if (SelectionEngine.cancelRequested) {
          break;
        }
        await SelectionClock.sleep(task.intervalMs);
      }

      if (SelectionEngine.cancelRequested) {
        SelectionEngine.finish(context, fatal ? SelectionRunPhase.FAILED : SelectionRunPhase.STOPPED,
          stopMessage.length > 0 ? stopMessage : '已手动停止');
        return;
      }
      if (pending.length === 0) {
        const remaining: SelectionQueueItem[] = await SelectionRepository.listQueue(context);
        const failed: number = remaining.filter((item: SelectionQueueItem) =>
          item.state !== SelectionQueueState.SUCCESS && item.state !== SelectionQueueState.ALREADY).length;
        await SelectionEngine.syncTimetable(context, task);
        SelectionEngine.finish(context,
          failed === 0 ? SelectionRunPhase.DONE : SelectionRunPhase.PARTIAL,
          failed === 0 ? '全部课程已选上' : `${success} 门已选上，${failed} 门未完成`);
        return;
      }
      SelectionEngine.finish(context, SelectionRunPhase.FAILED,
        stopMessage.length > 0 ? stopMessage : '已达到单次运行上限（30 分钟 / 2400 次请求）');
    } finally {
      SelectionEngine.active = false;
      const screenContext: common.UIAbilityContext =
        SelectionEngine.runContext === null ? context : SelectionEngine.runContext;
      await SelectionEngine.keepScreenOn(screenContext, false);
      try {
        await SelectionRepository.setTaskStatus(context,
          SelectionEngine.snapshot.phase === SelectionRunPhase.RUNNING
            ? SelectionRunPhase.STOPPED : SelectionEngine.snapshot.phase);
      } catch (error) {
        hilog.warn(0x0000, TAG, 'persist status failed: %{public}s', (error as Error).message);
      }
    }
  }

  /** 提交一次选课并归类结果。异常在这里被收敛成状态，不向外抛。 */
  private static async attempt(item: SelectionQueueItem): Promise<AttemptRecord> {
    const client: JxfwClient = new JxfwClient();
    const started: number = Date.now();
    try {
      const raw: string = await client.submitSelection(item.kcrwdm, item.name);
      const result: SelectionResult = SelectionParser.parseSubmit(raw);
      return { result: result, rttMs: Date.now() - started };
    } catch (error) {
      if (error instanceof JxfwError && error.kind === JxfwErrorKind.SESSION) {
        return {
          result: { outcome: SelectionOutcome.SESSION, message: '教务会话已失效', raw: '' },
          rttMs: Date.now() - started
        };
      }
      const message: string = error instanceof Error ? error.message : '网络请求失败';
      return {
        result: { outcome: SelectionOutcome.NETWORK, message: message, raw: '' },
        rttMs: Date.now() - started
      };
    }
  }

  /** 预热：确认会话可用 + 提前建立连接，缩短到点后的首字节时间。 */
  private static async warmUp(pending: SelectionQueueItem[]): Promise<void> {
    try {
      await new JxfwClient().fetchSelectionCourses(1, 1, '');
    } catch (error) {
      if (error instanceof JxfwError && error.kind === JxfwErrorKind.SESSION) {
        throw error;
      }
      // 预热失败不阻塞抢课，正式提交时会再试。
    }
    if (pending.length > 0) {
      try {
        await new JxfwClient().fetchSelectionLessons(pending[0].kcrwdm);
      } catch (error) {
        // 同上。
      }
    }
  }

  private static async waitForTarget(targetLocal: number): Promise<boolean> {
    for (;;) {
      if (SelectionEngine.cancelRequested) {
        return false;
      }
      const remain: number = targetLocal - Date.now();
      if (remain <= 0) {
        return true;
      }
      if (remain <= 30000 && SelectionEngine.runContext !== null && !SelectionEngine.screenKept) {
        await SelectionEngine.keepScreenOn(SelectionEngine.runContext, true);
      }
      const seconds: number = Math.ceil(remain / 1000);
      SelectionEngine.patch({
        message: remain > 1500 ? `等待开始 · 剩余 ${seconds} 秒` : '即将提交…'
      });
      if (remain > 1500) {
        await SelectionClock.sleep(Math.min(remain - 800, 1000));
      } else if (remain > 60) {
        await SelectionClock.sleep(Math.min(remain - 45, 50));
      } else {
        while (Date.now() < targetLocal) {
          // 末段忙等，误差控制在个位数毫秒。
        }
        return !SelectionEngine.cancelRequested;
      }
    }
  }

  private static log(item: SelectionQueueItem, record: AttemptRecord): void {
    const entry: SelectionLogEntry = {
      at: Date.now(),
      kcrwdm: item.kcrwdm,
      name: item.name,
      outcome: record.result.outcome,
      message: record.result.message,
      rttMs: record.rttMs
    };
    SelectionEngine.snapshot.logs.push(entry);
    if (SelectionEngine.snapshot.logs.length > SELECTION_MAX_LOGS) {
      SelectionEngine.snapshot.logs.splice(0, SelectionEngine.snapshot.logs.length - SELECTION_MAX_LOGS);
    }
    const context: common.Context | null = SelectionEngine.context;
    if (context !== null) {
      SelectionRepository.appendLog(context, entry).catch(() => {});
    }
  }

  private static finish(context: common.UIAbilityContext, phase: SelectionRunPhase,
    message: string): void {
    SelectionEngine.snapshot.phase = phase;
    SelectionEngine.patch({ message: message });
    SelectionEngine.publish();
    SelectionState.bumpQueue();
    const persistContext: common.Context | null = SelectionEngine.context;
    if (persistContext !== null) {
      SelectionRepository.setTaskStatus(persistContext, phase).catch(() => {});
    }
    if (phase === SelectionRunPhase.DONE || phase === SelectionRunPhase.PARTIAL) {
      LocalNotificationService.notify(context, '抢课任务完成', message, 'selection-done').catch(() => {});
    } else if (phase === SelectionRunPhase.FAILED) {
      LocalNotificationService.notify(context, '抢课任务已停止', message, 'selection-fail').catch(() => {});
    }
  }

  private static patch(fields: SnapshotPatch): void {
    SelectionEngine.snapshot.phase = fields.phase ?? SelectionEngine.snapshot.phase;
    SelectionEngine.snapshot.startAt = fields.startAt ?? SelectionEngine.snapshot.startAt;
    SelectionEngine.snapshot.offsetMs = fields.offsetMs ?? SelectionEngine.snapshot.offsetMs;
    SelectionEngine.snapshot.rttMs = fields.rttMs ?? SelectionEngine.snapshot.rttMs;
    SelectionEngine.snapshot.attempts = fields.attempts ?? SelectionEngine.snapshot.attempts;
    SelectionEngine.snapshot.pending = fields.pending ?? SelectionEngine.snapshot.pending;
    SelectionEngine.snapshot.success = fields.success ?? SelectionEngine.snapshot.success;
    SelectionEngine.snapshot.message = fields.message ?? SelectionEngine.snapshot.message;
    SelectionEngine.snapshot.clockCalibrated =
      fields.clockCalibrated ?? SelectionEngine.snapshot.clockCalibrated;
    SelectionEngine.publish();
  }

  private static publish(): void {
    SelectionEngine.snapshot.updatedAt = Date.now();
    AppStorage.setOrCreate(SELECTION_RUN_KEY, JSON.stringify(SelectionEngine.snapshot));
  }

  private static async syncTimetable(context: common.UIAbilityContext, task: SelectionTask): Promise<void> {
    if (!task.syncAfter) {
      return;
    }
    SelectionEngine.patch({ message: '正在同步课表…' });
    try {
      await SelectionClock.sleep(END_SETTLE_MS);
      const semester: Semester | null = await TimetableRepository.getCurrentSemester(context);
      if (semester === null) {
        return;
      }
      await TimetableSyncService.fullSync(context, semester);
      TimetableState.bump();
    } catch (error) {
      hilog.warn(0x0000, TAG, 'sync after selection failed: %{public}s', (error as Error).message);
    }
  }

  private static async keepScreenOn(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    if (SelectionEngine.screenKept === enabled) {
      return;
    }
    try {
      const mainWindow: window.Window = await window.getLastWindow(context);
      await mainWindow.setWindowKeepScreenOn(enabled);
      SelectionEngine.screenKept = enabled;
      SelectionEngine.context = context;
    } catch (error) {
      hilog.warn(0x0000, TAG, 'keep screen on failed: %{public}s', (error as Error).message);
    }
  }

  /**
   * 退到后台时申请短时任务（单次最多 3 分钟），尽量把这轮抢完；
   * 超过配额系统会挂起进程，回到前台后由快照显示实际状态。
   */
  static onAppBackground(context: common.Context): void {
    SelectionEngine.context = context;
    if (!SelectionEngine.active || SelectionEngine.suspendRequestId >= 0) {
      return;
    }
    try {
      const info: backgroundTaskManager.DelaySuspendInfo = backgroundTaskManager.requestSuspendDelay(
        '抢课任务进行中',
        () => {
          SelectionEngine.patch({ message: '后台时限将到，回到应用可继续查看结果' });
        });
      SelectionEngine.suspendRequestId = info.requestId;
      SelectionEngine.patch({ message: '已申请后台延时，请尽快回到应用' });
    } catch (error) {
      hilog.warn(0x0000, TAG, 'requestSuspendDelay failed: %{public}s', (error as Error).message);
    }
  }

  static onAppForeground(): void {
    if (SelectionEngine.suspendRequestId < 0) {
      return;
    }
    try {
      backgroundTaskManager.cancelSuspendDelay(SelectionEngine.suspendRequestId);
    } catch (error) {
      // 任务可能已自然结束。
    }
    SelectionEngine.suspendRequestId = -1;
  }
}
