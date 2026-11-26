import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { JxfwClient } from './JxfwClient';
import { JxfwSession } from './JxfwSession';
import { CasLoginService } from './CasLoginService';

const PREFERENCE_NAME: string = 'profile_settings';
const KEY_JXFW_NAME: string = 'jxfw_name';
const KEY_MANUAL_NAME: string = 'display_name';
export const PROFILE_NAME_REVISION_KEY: string = 'profileNameRevision';

function bumpRevision(): void {
  const value: number | undefined = AppStorage.get<number>(PROFILE_NAME_REVISION_KEY);
  AppStorage.setOrCreate(PROFILE_NAME_REVISION_KEY, (value === undefined ? 0 : value) + 1);
}

/** Reads/caches the student name exposed by jxfw and manages the manual override. */
export class JxfwProfileService {
  private static async store(context: common.Context): Promise<preferences.Preferences> {
    return preferences.getPreferences(context, PREFERENCE_NAME);
  }

  static async cachedName(context: common.Context): Promise<string> {
    try {
      const store: preferences.Preferences = await JxfwProfileService.store(context);
      const value = await store.get(KEY_JXFW_NAME, '');
      return typeof value === 'string' ? value.trim() : '';
    } catch (error) {
      return '';
    }
  }

  static async manualName(context: common.Context): Promise<string> {
    try {
      const store: preferences.Preferences = await JxfwProfileService.store(context);
      const value = await store.get(KEY_MANUAL_NAME, '');
      return typeof value === 'string' ? value.trim() : '';
    } catch (error) {
      return '';
    }
  }

  static async setManualName(context: common.Context, name: string): Promise<void> {
    const store: preferences.Preferences = await JxfwProfileService.store(context);
    await store.put(KEY_MANUAL_NAME, name.trim());
    await store.flush();
    bumpRevision();
  }

  static async clearManualName(context: common.Context): Promise<void> {
    const store: preferences.Preferences = await JxfwProfileService.store(context);
    await store.delete(KEY_MANUAL_NAME);
    await store.flush();
    bumpRevision();
  }

  /**
   * Logs in when necessary and reads the name from jxfw. Failures are silent:
   * the profile page then falls back to the manual name or the app title.
   */
  static async refresh(context: common.Context): Promise<string> {
    try {
      if (!JxfwSession.isLoggedIn() && !(await CasLoginService.autoLogin())) {
        return '';
      }
      const name: string = await new JxfwClient().fetchStudentName();
      if (name.length > 0) {
        const store: preferences.Preferences = await JxfwProfileService.store(context);
        await store.put(KEY_JXFW_NAME, name);
        await store.flush();
        bumpRevision();
      }
      return name;
    } catch (error) {
      return '';
    }
  }
}
