import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { GradeCache, JxfwGrade } from '../../domain/model/GradeModels';
import { JxfwClient } from '../jxfw/JxfwClient';
import { JxfwGradeParser } from '../jxfw/JxfwGradeParser';

const STORE_NAME: string = 'grade_cache';
const CACHE_KEY: string = 'grades';

export class GradeService {
  static async loadCache(context: common.Context): Promise<GradeCache | null> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      const raw = await store.get(CACHE_KEY, '');
      if (typeof raw !== 'string' || raw.length === 0) {
        return null;
      }
      return JSON.parse(raw) as GradeCache;
    } catch (error) {
      return null;
    }
  }

  static async clearCache(context: common.Context): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      await store.put(CACHE_KEY, '');
      await store.flush();
    } catch (error) {
      // Cache cleanup is best effort.
    }
  }

  static async sync(context: common.Context): Promise<GradeCache> {
    const client: JxfwClient = new JxfwClient();
    const all: JxfwGrade[] = [];
    for (let page = 1; page <= 10; page++) {
      const raw: string = await client.fetchGradePage('', page, 100);
      const rows: JxfwGrade[] = JxfwGradeParser.parsePage(raw);
      for (const grade of rows) {
        const key: string = `${grade.term}|${grade.code}|${grade.name}`;
        if (!all.some((item: JxfwGrade) => `${item.term}|${item.code}|${item.name}` === key)) {
          all.push(grade);
        }
      }
      if (rows.length < 100) {
        break;
      }
    }
    const cache: GradeCache = { updatedAt: Date.now(), grades: all };
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.put(CACHE_KEY, JSON.stringify(cache));
    await store.flush();
    return cache;
  }
}
