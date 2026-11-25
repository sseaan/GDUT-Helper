import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { TzcsCache, TzcsReport } from './TzcsModels';

const STORE_NAME: string = 'tzcs_cache';
const CACHE_KEY: string = 'reports';

export class TzcsCacheService {
  static async load(context: common.Context): Promise<TzcsCache | null> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const raw = await store.get(CACHE_KEY, '');
      if (typeof raw !== 'string' || raw.length === 0) {
        return null;
      }
      return JSON.parse(raw) as TzcsCache;
    } catch (error) {
      return null;
    }
  }

  static async clear(context: common.Context): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      await store.put(CACHE_KEY, '');
      await store.flush();
    } catch (error) {
      // ignore
    }
  }

  static async save(context: common.Context, reports: TzcsReport[]): Promise<void> {
    try {
      const cache: TzcsCache = { updatedAt: Date.now(), reports: reports };
      const store = await preferences.getPreferences(context, STORE_NAME);
      await store.put(CACHE_KEY, JSON.stringify(cache));
      await store.flush();
    } catch (error) {
      // Cache failure does not invalidate the fetched reports.
    }
  }
}
