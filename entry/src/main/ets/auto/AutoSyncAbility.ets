import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TimetableRepository } from '../data/TimetableRepository';
import { Semester } from '../domain/model/TimetableModels';
import { TimetableSyncService } from '../services/sync/TimetableSyncService';
import { SystemCalendarSyncService } from '../services/calendar/SystemCalendarSyncService';
import { WidgetSnapshotService } from '../services/widget/WidgetSnapshotService';
import { TimetableState } from '../state/TimetableState';

export default class AutoSyncAbility extends WorkSchedulerExtensionAbility {
  onWorkStart(work: workScheduler.WorkInfo): void {
    hilog.info(0x0000, 'AutoSync', 'work start %{public}d', work.workId);
    this.run(work);
  }

  onWorkStop(work: workScheduler.WorkInfo): void {
    hilog.info(0x0000, 'AutoSync', 'work stop %{public}d', work.workId);
  }

  private async run(work: workScheduler.WorkInfo): Promise<void> {
    try {
      const semester: Semester | null = await TimetableRepository.getCurrentSemester(this.context);
      if (semester !== null) {
        await TimetableSyncService.fullSync(this.context, semester);
        TimetableState.bump();
      }
      await SystemCalendarSyncService.refresh(this.context);
      await WidgetSnapshotService.write(this.context);
    } catch (error) {
      hilog.warn(0x0000, 'AutoSync', 'sync failed: %{public}s', (error as Error).message);
    } finally {
      try {
        workScheduler.stopWork(work, false);
      } catch (error) {
        // Work may already be finishing.
      }
    }
  }
}
