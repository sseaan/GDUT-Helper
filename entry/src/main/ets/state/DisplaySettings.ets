import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

export const SHOW_COURSE_CONTENT_KEY: string = 'showCourseContent';
export const CAMPUS_NEWS_ENABLED_KEY: string = 'campusNewsEnabled';
export const CAMPUS_DATA_ENABLED_KEY: string = 'campusDataEnabled';
export const LOCAL_NOTIFICATIONS_ENABLED_KEY: string = 'localNotificationsEnabled';
export const SELECTION_ENABLED_KEY: string = 'selectionEnabled';
const STORE_NAME: string = 'display_settings';

/** Display-only preferences shared by Profile and the timetable. */
export class DisplaySettings {
  static value(): boolean {
    const value: boolean | undefined = AppStorage.get<boolean>(SHOW_COURSE_CONTENT_KEY);
    return value === undefined ? false : value;
  }

  static campusNewsEnabled(): boolean {
    const value: boolean | undefined = AppStorage.get<boolean>(CAMPUS_NEWS_ENABLED_KEY);
    return value === undefined ? true : value;
  }

  static campusDataEnabled(): boolean {
    const value: boolean | undefined = AppStorage.get<boolean>(CAMPUS_DATA_ENABLED_KEY);
    return value === undefined ? true : value;
  }

  static localNotificationsEnabled(): boolean {
    const value: boolean | undefined = AppStorage.get<boolean>(LOCAL_NOTIFICATIONS_ENABLED_KEY);
    return value === undefined ? false : value;
  }

  static selectionEnabled(): boolean {
    const value: boolean | undefined = AppStorage.get<boolean>(SELECTION_ENABLED_KEY);
    return value === undefined ? true : value;
  }

  static async load(context: common.Context): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const value = await store.get(SHOW_COURSE_CONTENT_KEY, false);
      AppStorage.setOrCreate(SHOW_COURSE_CONTENT_KEY, value === true);
      const news = await store.get(CAMPUS_NEWS_ENABLED_KEY, true);
      AppStorage.setOrCreate(CAMPUS_NEWS_ENABLED_KEY, news !== false);
      const data = await store.get(CAMPUS_DATA_ENABLED_KEY, true);
      AppStorage.setOrCreate(CAMPUS_DATA_ENABLED_KEY, data !== false);
      const localNotifications = await store.get(LOCAL_NOTIFICATIONS_ENABLED_KEY, false);
      AppStorage.setOrCreate(LOCAL_NOTIFICATIONS_ENABLED_KEY, localNotifications === true);
      const selection = await store.get(SELECTION_ENABLED_KEY, true);
      AppStorage.setOrCreate(SELECTION_ENABLED_KEY, selection !== false);
    } catch (error) {
      AppStorage.setOrCreate(SHOW_COURSE_CONTENT_KEY, false);
      AppStorage.setOrCreate(CAMPUS_NEWS_ENABLED_KEY, true);
      AppStorage.setOrCreate(CAMPUS_DATA_ENABLED_KEY, true);
      AppStorage.setOrCreate(LOCAL_NOTIFICATIONS_ENABLED_KEY, false);
      AppStorage.setOrCreate(SELECTION_ENABLED_KEY, true);
    }
  }

  static async set(context: common.Context, value: boolean): Promise<void> {
    AppStorage.setOrCreate(SHOW_COURSE_CONTENT_KEY, value);
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.put(SHOW_COURSE_CONTENT_KEY, value);
    await store.flush();
  }

  static async setCampusNewsEnabled(context: common.Context, value: boolean): Promise<void> {
    AppStorage.setOrCreate(CAMPUS_NEWS_ENABLED_KEY, value);
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.put(CAMPUS_NEWS_ENABLED_KEY, value);
    await store.flush();
  }

  static async setCampusDataEnabled(context: common.Context, value: boolean): Promise<void> {
    AppStorage.setOrCreate(CAMPUS_DATA_ENABLED_KEY, value);
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.put(CAMPUS_DATA_ENABLED_KEY, value);
    await store.flush();
  }

  static async setLocalNotificationsEnabled(context: common.Context, value: boolean): Promise<void> {
    AppStorage.setOrCreate(LOCAL_NOTIFICATIONS_ENABLED_KEY, value);
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.put(LOCAL_NOTIFICATIONS_ENABLED_KEY, value);
    await store.flush();
  }

  static async setSelectionEnabled(context: common.Context, value: boolean): Promise<void> {
    AppStorage.setOrCreate(SELECTION_ENABLED_KEY, value);
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.put(SELECTION_ENABLED_KEY, value);
    await store.flush();
  }

}
