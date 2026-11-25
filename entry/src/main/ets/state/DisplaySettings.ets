import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

export const SHOW_COURSE_CONTENT_KEY: string = 'showCourseContent';
const STORE_NAME: string = 'display_settings';

/** Display-only preferences shared by Profile and the timetable. */
export class DisplaySettings {
  static value(): boolean {
    const value: boolean | undefined = AppStorage.get<boolean>(SHOW_COURSE_CONTENT_KEY);
    return value === undefined ? false : value;
  }

  static async load(context: common.Context): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const value = await store.get(SHOW_COURSE_CONTENT_KEY, false);
      AppStorage.setOrCreate(SHOW_COURSE_CONTENT_KEY, value === true);
    } catch (error) {
      AppStorage.setOrCreate(SHOW_COURSE_CONTENT_KEY, false);
    }
  }

  static async set(context: common.Context, value: boolean): Promise<void> {
    AppStorage.setOrCreate(SHOW_COURSE_CONTENT_KEY, value);
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.put(SHOW_COURSE_CONTENT_KEY, value);
    await store.flush();
  }
}
