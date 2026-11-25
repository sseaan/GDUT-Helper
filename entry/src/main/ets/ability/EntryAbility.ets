import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ReminderService } from '../services/reminder/ReminderService';
import { SystemCalendarSyncService } from '../services/calendar/SystemCalendarSyncService';
import { WidgetSnapshotService } from '../services/widget/WidgetSnapshotService';
import { AppearanceSettings } from '../state/AppearanceSettings';

const DOMAIN: number = 0x0000;
const TAG: string = 'GDUTHelper';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'EntryAbility onCreate');
    AppearanceSettings.load(this.context).then((mode) => {
      AppearanceSettings.apply(this.context, mode);
    }).catch(() => {});
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'EntryAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'Succeeded in loading the content.');
    });

    try {
      const mainWindow = windowStage.getMainWindowSync();
      mainWindow.setWindowLayoutFullScreen(true);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to enable full-screen layout: %{public}s', JSON.stringify(error));
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'EntryAbility onForeground');
    ReminderService.refreshIfEnabled(this.context).catch(() => {});
    SystemCalendarSyncService.refreshIfEnabled(this.context).catch(() => {});
    WidgetSnapshotService.write(this.context).catch(() => {});
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'EntryAbility onBackground');
  }
}
