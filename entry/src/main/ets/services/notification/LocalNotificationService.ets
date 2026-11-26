import { common } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DisplaySettings } from '../../state/DisplaySettings';

const TAG: string = 'LocalNotify';

/** Immediate local notifications. Scheduled/agent reminders remain in ReminderService. */
export class LocalNotificationService {
  static async load(context: common.Context): Promise<void> {
    await DisplaySettings.load(context);
  }

  static enabled(): boolean {
    return DisplaySettings.localNotificationsEnabled();
  }

  static async setEnabled(context: common.UIAbilityContext, enabled: boolean): Promise<boolean> {
    if (!enabled) {
      await DisplaySettings.setLocalNotificationsEnabled(context, false);
      return true;
    }
    let granted: boolean = await LocalNotificationService.hasPermission();
    if (!granted) {
      try {
        await notificationManager.requestEnableNotification(context);
      } catch (error) {
        hilog.warn(0x0000, TAG, 'request permission failed: %{public}s', (error as Error).message);
      }
      granted = await LocalNotificationService.hasPermission();
    }
    if (!granted) {
      await DisplaySettings.setLocalNotificationsEnabled(context, false);
      return false;
    }
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
    } catch (error) {
      // Slot creation is idempotent/best effort.
    }
    await DisplaySettings.setLocalNotificationsEnabled(context, true);
    return true;
  }

  private static async hasPermission(): Promise<boolean> {
    try {
      return await notificationManager.isNotificationEnabled();
    } catch (error) {
      return false;
    }
  }

  /** Sends a notification if the feature is enabled and permission is available. */
  static async notify(context: common.Context, title: string, text: string, key: string = 'notice'): Promise<boolean> {
    if (!LocalNotificationService.enabled()) {
      return false;
    }
    if (!(await LocalNotificationService.hasPermission())) {
      return false;
    }
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
      const request: notificationManager.NotificationRequest = {
        id: LocalNotificationService.notificationId(key),
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: text
          }
        }
      };
      await notificationManager.publish(request);
      return true;
    } catch (error) {
      hilog.warn(0x0000, TAG, 'publish failed: %{public}s', (error as Error).message);
      return false;
    }
  }

  private static notificationId(key: string): number {
    let hash: number = 23;
    for (let i = 0; i < key.length; i++) {
      hash = (hash * 31 + key.charCodeAt(i)) & 0x7fffffff;
    }
    return 20000 + hash % 1000000;
  }
}
