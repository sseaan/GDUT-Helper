import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { calendarManager } from '@kit.CalendarKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AgendaItem, AgendaKind, agendaForDate } from '../../domain/agenda/AgendaEngine';
import { Course, CourseException, Event, Semester } from '../../domain/model/TimetableModels';
import { TimetableRepository } from '../../data/TimetableRepository';

export const CALENDAR_SYNC_KEY: string = 'calendarSyncEnabled';
const STORE_NAME: string = 'calendar_sync';
const IDS_KEY: string = 'calendar_event_ids';
const DAYS_AHEAD: number = 21;
const MAX_EVENTS: number = 80;

export class SystemCalendarSyncService {
  private static syncing: Promise<number> | null = null;
  private static lastCount: number = 0;

  static lastSyncedCount(): number {
    return SystemCalendarSyncService.lastCount;
  }

  static async loadSetting(context: common.Context): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const enabled = await store.get(CALENDAR_SYNC_KEY, false);
      AppStorage.setOrCreate(CALENDAR_SYNC_KEY, enabled === true);
    } catch (error) {
      AppStorage.setOrCreate(CALENDAR_SYNC_KEY, false);
    }
  }

  static async setEnabled(context: common.UIAbilityContext, enabled: boolean): Promise<boolean> {
    const store = await preferences.getPreferences(context, STORE_NAME);
    if (!enabled) {
      await SystemCalendarSyncService.removeSynced(context);
      await store.put(CALENDAR_SYNC_KEY, false);
      await store.flush();
      AppStorage.setOrCreate(CALENDAR_SYNC_KEY, false);
      return true;
    }
    const granted: boolean = await SystemCalendarSyncService.requestPermissions(context);
    if (!granted) {
      await store.put(CALENDAR_SYNC_KEY, false);
      await store.flush();
      AppStorage.setOrCreate(CALENDAR_SYNC_KEY, false);
      return false;
    }
    await store.put(CALENDAR_SYNC_KEY, true);
    await store.flush();
    AppStorage.setOrCreate(CALENDAR_SYNC_KEY, true);
    await SystemCalendarSyncService.refresh(context);
    return true;
  }

  static async refreshIfEnabled(context: common.UIAbilityContext): Promise<void> {
    await SystemCalendarSyncService.loadSetting(context);
    if (AppStorage.get<boolean>(CALENDAR_SYNC_KEY) === true) {
      await SystemCalendarSyncService.refresh(context);
    }
  }

  static async refresh(context: common.Context): Promise<number> {
    if (SystemCalendarSyncService.syncing !== null) {
      return SystemCalendarSyncService.syncing;
    }
    SystemCalendarSyncService.syncing = SystemCalendarSyncService.refreshInternal(context);
    try {
      return await SystemCalendarSyncService.syncing;
    } finally {
      SystemCalendarSyncService.syncing = null;
    }
  }

  private static eventTitle(item: AgendaItem): string {
    if (item.course !== null && item.course.name.length > 0) {
      return item.course.name;
    }
    return item.title;
  }

  private static eventDescription(item: AgendaItem): string {
    const parts: string[] = [];
    if (item.location.length > 0) {
      parts.push(item.location);
    }
    if (item.course !== null && item.course.teacher.length > 0) {
      parts.push(item.course.teacher);
    }
    parts.push('GDUT Helper');
    return parts.join(' · ');
  }

  private static async refreshInternal(context: common.Context): Promise<number> {
    if (AppStorage.get<boolean>(CALENDAR_SYNC_KEY) !== true) {
      return 0;
    }
    const semester: Semester | null = await TimetableRepository.getCurrentSemester(context);
    if (semester === null) {
      await SystemCalendarSyncService.removeSynced(context);
      return 0;
    }
    const courses: Course[] = await TimetableRepository.listCourses(context, semester.id);
    const exceptions: CourseException[] = await TimetableRepository.listExceptions(context, semester.id);
    const events: Event[] = await TimetableRepository.listEvents(context, semester.id);
    await SystemCalendarSyncService.removeSynced(context);

    const manager = calendarManager.getCalendarManager(context);
    const calendar = await manager.getCalendar();
    const ids: number[] = [];
    const today: Date = new Date();
    for (let offset = 0; offset < DAYS_AHEAD && ids.length < MAX_EVENTS; offset++) {
      const date: Date = new Date(Date.UTC(today.getFullYear(), today.getMonth(), today.getDate() + offset));
      const items: AgendaItem[] = agendaForDate(courses, exceptions, events, semester, date);
      for (const item of items) {
        if (ids.length >= MAX_EVENTS) {
          break;
        }
        try {
          const id: number = await calendar.addEvent({
            type: calendarManager.EventType.NORMAL,
            title: SystemCalendarSyncService.eventTitle(item),
            startTime: item.startTime,
            endTime: item.endTime,
            isAllDay: item.allDay,
            location: { location: item.location },
            description: SystemCalendarSyncService.eventDescription(item),
            reminderTime: [item.kind === AgendaKind.EXAM ? 30 : 10]
          });
          ids.push(id);
        } catch (error) {
          hilog.warn(0x0000, 'CalendarSync', 'add event failed: %{public}s', (error as Error).message);
          break;
        }
      }
    }
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.put(IDS_KEY, JSON.stringify(ids));
    await store.flush();
    SystemCalendarSyncService.lastCount = ids.length;
    hilog.info(0x0000, 'CalendarSync', 'synced %{public}d events', ids.length);
    return ids.length;
  }

  static async removeSynced(context: common.Context): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const raw = await store.get(IDS_KEY, '');
      if (typeof raw !== 'string' || raw.length === 0) {
        return;
      }
      const ids: number[] = JSON.parse(raw) as number[];
      const manager = calendarManager.getCalendarManager(context);
      const calendar = await manager.getCalendar();
      for (const id of ids) {
        try {
          await calendar.deleteEvent(id);
        } catch (error) {
          // Already removed by the user/system.
        }
      }
      await store.put(IDS_KEY, '');
      await store.flush();
    } catch (error) {
      // Best effort cleanup.
    }
  }

  private static async requestPermissions(context: common.UIAbilityContext): Promise<boolean> {
    const permissions: Array<Permissions> = [
      'ohos.permission.READ_CALENDAR',
      'ohos.permission.WRITE_CALENDAR'
    ];
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(context, permissions);
      for (let i = 0; i < result.authResults.length; i++) {
        if (result.authResults[i] !== 0) {
          return false;
        }
      }
      return true;
    } catch (error) {
      return false;
    }
  }
}
