import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ClassroomBuilding, ClassroomOccupancy, ClassroomRoom } from './JwcwxModels';

const STORE_NAME: string = 'jwcwx_cache';
const BUILDINGS_KEY: string = 'buildings';

interface CacheEntry<T> {
  updatedAt: number;
  data: T;
}

async function readEntry<T>(context: common.Context, key: string): Promise<CacheEntry<T> | null> {
  try {
    const store = await preferences.getPreferences(context, STORE_NAME);
    const raw = await store.get(key, '');
    if (typeof raw !== 'string' || raw.length === 0) {
      return null;
    }
    return JSON.parse(raw) as CacheEntry<T>;
  } catch (error) {
    return null;
  }
}

async function writeEntry<T>(context: common.Context, key: string, data: T): Promise<void> {
  try {
    const store = await preferences.getPreferences(context, STORE_NAME);
    const entry: CacheEntry<T> = { updatedAt: Date.now(), data: data };
    await store.put(key, JSON.stringify(entry));
    await store.flush();
  } catch (error) {
    // Cache is best effort.
  }
}

export class JwcwxCache {
  static async clear(context: common.Context): Promise<void> {
    try {
      await preferences.deletePreferences(context, STORE_NAME);
    } catch (error) {
      // Cache cleanup is best effort.
    }
  }

  static async saveBuildings(context: common.Context, buildings: ClassroomBuilding[]): Promise<void> {
    await writeEntry<ClassroomBuilding[]>(context, BUILDINGS_KEY, buildings);
  }

  static async loadBuildings(context: common.Context): Promise<ClassroomBuilding[]> {
    const entry: CacheEntry<ClassroomBuilding[]> | null =
      await readEntry<ClassroomBuilding[]>(context, BUILDINGS_KEY);
    return entry === null ? [] : entry.data;
  }

  static async saveRooms(context: common.Context, buildingCode: string,
    rooms: ClassroomRoom[]): Promise<void> {
    await writeEntry<ClassroomRoom[]>(context, `rooms:${buildingCode}`, rooms);
  }

  static async loadRooms(context: common.Context, buildingCode: string): Promise<ClassroomRoom[]> {
    const entry: CacheEntry<ClassroomRoom[]> | null =
      await readEntry<ClassroomRoom[]>(context, `rooms:${buildingCode}`);
    return entry === null ? [] : entry.data;
  }

  static async saveOccupancy(context: common.Context, buildingCode: string, date: string,
    items: ClassroomOccupancy[]): Promise<void> {
    await writeEntry<ClassroomOccupancy[]>(context, `occupancy:${buildingCode}:${date}`, items);
  }

  static async loadOccupancy(context: common.Context, buildingCode: string,
    date: string): Promise<ClassroomOccupancy[]> {
    const entry: CacheEntry<ClassroomOccupancy[]> | null =
      await readEntry<ClassroomOccupancy[]>(context, `occupancy:${buildingCode}:${date}`);
    return entry === null ? [] : entry.data;
  }
}
