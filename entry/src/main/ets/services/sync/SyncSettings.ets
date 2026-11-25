import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const STORE_NAME: string = 'jxfw_sync';

/** Small persisted summary shown on the sync page. */
export class SyncSettings {
  static async get(context: common.Context, key: string): Promise<string> {
    const store = await preferences.getPreferences(context, STORE_NAME);
    const value = await store.get(key, '');
    return typeof value === 'string' ? value : '';
  }

  static async set(context: common.Context, key: string, value: string): Promise<void> {
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.put(key, value);
    await store.flush();
  }
}
