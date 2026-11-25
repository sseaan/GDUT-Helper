import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { workScheduler } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export const AUTO_SYNC_KEY: string = 'autoSyncEnabled';
const STORE_NAME: string = 'auto_sync';
const WORK_ID: number = 1001;
const BUNDLE_NAME: string = 'com.gduthelper.app';
const ABILITY_NAME: string = 'AutoSyncAbility';

export class AutoSyncService {
  static async loadSetting(context: common.Context): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const enabled = await store.get(AUTO_SYNC_KEY, false);
      AppStorage.setOrCreate(AUTO_SYNC_KEY, enabled === true);
    } catch (error) {
      AppStorage.setOrCreate(AUTO_SYNC_KEY, false);
    }
  }

  static async setEnabled(context: common.Context, enabled: boolean): Promise<boolean> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      await store.put(AUTO_SYNC_KEY, enabled);
      await store.flush();
      AppStorage.setOrCreate(AUTO_SYNC_KEY, enabled);
      const work: workScheduler.WorkInfo = {
        workId: WORK_ID,
        bundleName: BUNDLE_NAME,
        abilityName: ABILITY_NAME,
        networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY,
        isRepeat: enabled,
        repeatCycleTime: 7 * 24 * 60 * 60 * 1000,
        isPersisted: true,
        parameters: { source: 'weekly' }
      };
      if (enabled) {
        workScheduler.startWork(work);
        hilog.info(0x0000, 'AutoSync', 'started weekly work');
      } else {
        workScheduler.stopWork(work, true);
        hilog.info(0x0000, 'AutoSync', 'stopped weekly work');
      }
      return true;
    } catch (error) {
      hilog.warn(0x0000, 'AutoSync', 'toggle failed: %{public}s', (error as Error).message);
      return false;
    }
  }
}
