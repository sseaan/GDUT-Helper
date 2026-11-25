import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { notificationManager } from '@kit.NotificationKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AgendaItem, AgendaKind, agendaForDate } from '../../domain/agenda/AgendaEngine';
import { Course, CourseException, Event, Semester } from '../../domain/model/TimetableModels';
import { TimetableRepository } from '../../data/TimetableRepository';

export const REMINDERS_ENABLED_KEY: string = 'remindersEnabled';
const STORE_NAME: string = 'reminder_settings';
const IDS_KEY: string = 'reminder_ids';
const DAYS_AHEAD: number = 7;
const MAX_REMINDERS: number = 24;

export class ReminderService {
  private static refreshing: Promise<number> | null = null;
  private static lastError: string = '';

  static lastErrorText(): string {
    return ReminderService.lastError;
  }
  static async loadSetting(context: common.Context): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const enabled = await store.get(REMINDERS_ENABLED_KEY, false);
      AppStorage.setOrCreate(REMINDERS_ENABLED_KEY, enabled === true);
    } catch (error) {
      AppStorage.setOrCreate(REMINDERS_ENABLED_KEY, false);
    }
  }

  static async setEnabled(context: common.UIAbilityContext, enabled: boolean): Promise<boolean> {
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.put(REMINDERS_ENABLED_KEY, enabled);
    await store.flush();
    AppStorage.setOrCreate(REMINDERS_ENABLED_KEY, enabled);
    if (!enabled) {
      await ReminderService.cancelAll(context);
      return true;
    }
    let notificationEnabled: boolean = await notificationManager.isNotificationEnabled();
    if (!notificationEnabled) {
      try {
        await notificationManager.requestEnableNotification(context);
      } catch (error) {
        // The caller can show the system settings hint.
      }
      notificationEnabled = await notificationManager.isNotificationEnabled();
    }
    if (!notificationEnabled) {
      return false;
    }
    hilog.info(0x0000, 'Reminder', 'notification enabled=%{public}d', notificationEnabled ? 1 : 0);
    const count: number = await ReminderService.refresh(context);
    if (count === 0 && ReminderService.lastError.length > 0) {
      await store.put(REMINDERS_ENABLED_KEY, false);
      await store.flush();
      AppStorage.setOrCreate(REMINDERS_ENABLED_KEY, false);
      return false;
    }
    return true;
  }

  static async refreshIfEnabled(context: common.UIAbilityContext): Promise<void> {
    await ReminderService.loadSetting(context);
    if (AppStorage.get<boolean>(REMINDERS_ENABLED_KEY) === true) {
      await ReminderService.refresh(context);
    }
  }

  static async refresh(context: common.Context): Promise<number> {
    if (ReminderService.refreshing !== null) {
      return ReminderService.refreshing;
    }
    ReminderService.refreshing = ReminderService.refreshInternal(context);
    try {
      return await ReminderService.refreshing;
    } finally {
      ReminderService.refreshing = null;
    }
  }

  private static async refreshInternal(context: common.Context): Promise<number> {
    const semester: Semester | null = await TimetableRepository.getCurrentSemester(context);
    if (semester === null) {
      await ReminderService.cancelAll(context);
      return 0;
    }
    const courses: Course[] = await TimetableRepository.listCourses(context, semester.id);
    const exceptions: CourseException[] = await TimetableRepository.listExceptions(context, semester.id);
    const events: Event[] = await TimetableRepository.listEvents(context, semester.id);
    const hasEnabled: boolean = AppStorage.get<boolean>(REMINDERS_ENABLED_KEY) === true;
    if (!hasEnabled) {
      await ReminderService.cancelAll(context);
      return 0;
    }

    ReminderService.lastError = '';
    await ReminderService.cancelAll(context);
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
    } catch (error) {
      // Slot creation is idempotent/best effort.
    }
    const ids: number[] = [];
    const now: number = Date.now();
    const today: Date = new Date();
    for (let offset = 0; offset < DAYS_AHEAD; offset++) {
      const date: Date = new Date(Date.UTC(today.getFullYear(), today.getMonth(), today.getDate() + offset));
      const items: AgendaItem[] = agendaForDate(courses, exceptions, events, semester, date);
      for (const item of items) {
        if (item.allDay) {
          continue;
        }
        const leadMinutes: number = item.kind === AgendaKind.EXAM ? 30 : 10;
        const remindAt: number = item.startTime - leadMinutes * 60 * 1000;
        if (remindAt <= now + 30 * 1000) {
          continue;
        }
        if (ids.length >= MAX_REMINDERS) {
          break;
        }
        try {
          const id: number = await ReminderService.publish(item, remindAt, leadMinutes);
          ids.push(id);
        } catch (error) {
          ReminderService.lastError = (error as Error).message;
          hilog.warn(0x0000, 'Reminder', 'publish failed: %{public}s', ReminderService.lastError);
          break;
        }
      }
    }
    await ReminderService.saveIds(context, ids);
    hilog.info(0x0000, 'Reminder', 'scheduled %{public}d reminders', ids.length);
    return ids.length;
  }

  private static async publish(item: AgendaItem, remindAt: number, leadMinutes: number): Promise<number> {
    const date: Date = new Date(remindAt);
    const request: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: {
        year: date.getFullYear(),
        month: date.getMonth() + 1,
        day: date.getDate(),
        hour: date.getHours(),
        minute: date.getMinutes(),
        second: 0
      },
      title: item.kind === AgendaKind.EXAM ? `考试提醒：${item.title}` : item.title,
      content: `${leadMinutes} 分钟后${item.kind === AgendaKind.EXAM ? '开考' : '开始'}${item.location.length > 0 ? ' · ' + item.location : ''}`,
      expiredContent: item.title,
      notificationId: ReminderService.notificationId(item.id),
      slotType: notificationManager.SlotType.SERVICE_INFORMATION,
      wantAgent: {
        pkgName: 'com.gduthelper.app',
        abilityName: 'EntryAbility'
      },
      actionButton: [
        {
          title: '知道了',
          type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE
        }
      ]
    };
    return reminderAgentManager.publishReminder(request);
  }

  static async clearScheduled(context: common.Context): Promise<void> {
    await ReminderService.cancelAll(context);
  }

  private static async cancelAll(context: common.Context): Promise<void> {
    try {
      await reminderAgentManager.cancelAllReminders();
    } catch (error) {
      // No valid reminders is the common case.
    }
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      await store.put(IDS_KEY, '');
      await store.flush();
    } catch (error) {
      // Cancellation is best effort.
    }
  }

  private static async saveIds(context: common.Context, ids: number[]): Promise<void> {
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.put(IDS_KEY, JSON.stringify(ids));
    await store.flush();
  }

  private static notificationId(key: string): number {
    let hash: number = 17;
    for (let i = 0; i < key.length; i++) {
      hash = (hash * 31 + key.charCodeAt(i)) & 0x7fffffff;
    }
    return 10000 + hash % 1000000;
  }
}
