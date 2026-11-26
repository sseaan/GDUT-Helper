import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { Database } from '../../data/Database';
import { TimetableRepository } from '../../data/TimetableRepository';
import { Course, CourseException, Event, Period, Semester } from '../../domain/model/TimetableModels';
import { AppearanceSettings, IMMERSIVE_KEY, HANDEDNESS_KEY, ThemeMode } from '../../state/AppearanceSettings';
import { DisplaySettings } from '../../state/DisplaySettings';
import { SystemCalendarSyncService } from '../calendar/SystemCalendarSyncService';
import { ReminderService } from '../reminder/ReminderService';
import { GradeService } from '../grades/GradeService';
import { TzcsCacheService } from '../tzcs/TzcsCache';
import { WidgetSnapshotService } from '../widget/WidgetSnapshotService';
import { JwcwxCache } from '../jwcwx/JwcwxCache';
import { BackupBundle, BackupSettings, BackupTombstone } from './BackupModels';
import { relationalStore } from '@kit.ArkData';

const FORMAT: string = 'gdut-helper-backup';
const VERSION: number = 2;
const SCHEMA_VERSION: number = 4;
const MAX_BACKUP_BYTES: number = 20 * 1024 * 1024;

function readText(uri: string): string {
  const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
    const stat = fs.statSync(uri);
    if (stat.size > MAX_BACKUP_BYTES) {
      throw new Error('文件超过 20MB 限制');
    }
    const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
    fs.readSync(file.fd, buffer);
    return new util.TextDecoder('utf-8').decodeToString(new Uint8Array(buffer));
  } finally {
    fs.closeSync(file);
  }
}

function writeText(uri: string, text: string): void {
  const file = fs.openSync(uri, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, text);
  } finally {
    fs.closeSync(file);
  }
}

async function prefString(context: common.Context, storeName: string, key: string): Promise<string> {
  try {
    const store = await preferences.getPreferences(context, storeName);
    const value = await store.get(key, '');
    return typeof value === 'string' ? value : '';
  } catch (error) {
    return '';
  }
}

async function putPrefString(context: common.Context, storeName: string, key: string, value: string): Promise<void> {
  if (value.length === 0) {
    return;
  }
  try {
    const store = await preferences.getPreferences(context, storeName);
    await store.put(key, value);
    await store.flush();
  } catch (error) {
    // Cache restore is best effort.
  }
}

interface BackupCanonical {
  format: string;
  version: number;
  schemaVersion: number;
  exportedAt: number;
  semesters: Semester[];
  periods: Period[];
  courses: Course[];
  exceptions: CourseException[];
  events: Event[];
  tombstones: BackupTombstone[];
  grades: string;
  tzcs: string;
  settings: BackupSettings;
}

function canonicalJson(bundle: BackupBundle): string {
  const payload: BackupCanonical = {
    format: bundle.format,
    version: bundle.version,
    schemaVersion: bundle.schemaVersion,
    exportedAt: bundle.exportedAt,
    semesters: bundle.semesters,
    periods: bundle.periods,
    courses: bundle.courses,
    exceptions: bundle.exceptions,
    events: bundle.events,
    tombstones: bundle.tombstones,
    grades: bundle.grades,
    tzcs: bundle.tzcs,
    settings: bundle.settings
  };
  return JSON.stringify(payload);
}

async function checksumOf(bundle: BackupBundle): Promise<string> {
  const md = cryptoFramework.createMd('SHA256');
  await md.update({ data: new util.TextEncoder().encodeInto(canonicalJson(bundle)) });
  const digest = await md.digest();
  return new util.Base64Helper().encodeToStringSync(digest.data);
}

function migrateBundle(raw: BackupBundle): BackupBundle {
  const bundle: BackupBundle = raw;
  if (!Array.isArray(bundle.periods)) {
    bundle.periods = [];
  }
  if (!Array.isArray(bundle.tombstones)) {
    bundle.tombstones = [];
  }
  if (typeof bundle.grades !== 'string') {
    bundle.grades = '';
  }
  if (typeof bundle.tzcs !== 'string') {
    bundle.tzcs = '';
  }
  if (bundle.settings === undefined || bundle.settings === null) {
    bundle.settings = {
      themeMode: 'system',
      immersiveEnabled: true,
      handednessEnabled: true,
      showCourseContent: false,
      localNotificationsEnabled: false,
      themeColorId: 'harmony',
      materialLevel: 10
    };
  }
  if (typeof bundle.settings.themeMode !== 'string') {
    bundle.settings.themeMode = 'system';
  }
  if (typeof bundle.settings.immersiveEnabled !== 'boolean') {
    bundle.settings.immersiveEnabled = true;
  }
  if (typeof bundle.settings.handednessEnabled !== 'boolean') {
    bundle.settings.handednessEnabled = true;
  }
  if (typeof bundle.settings.showCourseContent !== 'boolean') {
    bundle.settings.showCourseContent = false;
  }
  if (bundle.settings.campusNewsEnabled !== undefined &&
    typeof bundle.settings.campusNewsEnabled !== 'boolean') {
    bundle.settings.campusNewsEnabled = false;
  }
  if (bundle.settings.campusDataEnabled !== undefined &&
    typeof bundle.settings.campusDataEnabled !== 'boolean') {
    bundle.settings.campusDataEnabled = false;
  }
  if (bundle.settings.localNotificationsEnabled !== undefined &&
    typeof bundle.settings.localNotificationsEnabled !== 'boolean') {
    bundle.settings.localNotificationsEnabled = false;
  }
  if (typeof bundle.settings.themeColorId !== 'string') {
    bundle.settings.themeColorId = 'harmony';
  }
  if (bundle.settings.materialLevel !== 0 && bundle.settings.materialLevel !== 1 &&
    bundle.settings.materialLevel !== 2) {
    bundle.settings.materialLevel = 10;
  }
  if (typeof bundle.checksum !== 'string') {
    bundle.checksum = '';
  }
  if (bundle.version < VERSION) {
    bundle.version = VERSION;
  }
  if (bundle.schemaVersion === undefined || bundle.schemaVersion < 1) {
    bundle.schemaVersion = SCHEMA_VERSION;
  }
  return bundle;
}

export class BackupService {
  static async create(context: common.UIAbilityContext): Promise<BackupBundle> {
    const semesters: Semester[] = await TimetableRepository.listSemesters(context);
    const periods: Period[] = [];
    for (const semester of semesters) {
      const semesterPeriods: Period[] = await TimetableRepository.listPeriods(context, semester.id);
      for (const period of semesterPeriods) {
        periods.push(period);
      }
    }
    const courses: Course[] = await TimetableRepository.listAllCourses(context);
    const exceptions: CourseException[] = await TimetableRepository.listAllExceptions(context);
    const events: Event[] = await TimetableRepository.listAllEvents(context);
    const tombstones: BackupTombstone[] = [];
    for (const semester of semesters) {
      const keys: string[] = await TimetableRepository.listTombstones(context, semester.id);
      for (const key of keys) {
        tombstones.push({ semesterId: semester.id, courseKey: key });
      }
    }
    const settingsStore = await preferences.getPreferences(context, 'appearance_settings');
    const modeValue = await settingsStore.get('themeMode', ThemeMode.SYSTEM);
    const immersive = await settingsStore.get(IMMERSIVE_KEY, true);
    const handedness = await settingsStore.get(HANDEDNESS_KEY, true);
    const themeColorId = await settingsStore.get('themeColorId', 'harmony');
    const materialLevel = await settingsStore.get('materialLevel', 10);
    const displayStore = await preferences.getPreferences(context, 'display_settings');
    const showContent = await displayStore.get('showCourseContent', false);
    const campusNews = await displayStore.get('campusNewsEnabled', true);
    const campusData = await displayStore.get('campusDataEnabled', true);
    const localNotifications = await displayStore.get('localNotificationsEnabled', false);
    const settings: BackupSettings = {
      themeMode: typeof modeValue === 'string' ? modeValue : ThemeMode.SYSTEM,
      immersiveEnabled: immersive === true,
      handednessEnabled: handedness === true,
      showCourseContent: showContent === true,
      campusNewsEnabled: campusNews !== false,
      campusDataEnabled: campusData !== false,
      localNotificationsEnabled: localNotifications === true,
      themeColorId: typeof themeColorId === 'string' ? themeColorId : 'harmony',
      materialLevel: materialLevel === 0 || materialLevel === 1 || materialLevel === 2 ? materialLevel : 10
    };
    return {
      format: FORMAT,
      version: VERSION,
      schemaVersion: SCHEMA_VERSION,
      exportedAt: Date.now(),
      checksum: '',
      semesters: semesters,
      periods: periods,
      courses: courses,
      exceptions: exceptions,
      events: events,
      tombstones: tombstones,
      grades: await prefString(context, 'grade_cache', 'grades'),
      tzcs: await prefString(context, 'tzcs_cache', 'reports'),
      settings: settings
    };
  }

  static async exportToFile(context: common.UIAbilityContext): Promise<string> {
    const bundle: BackupBundle = await BackupService.create(context);
    bundle.checksum = await checksumOf(bundle);
    const pickerInstance = new picker.DocumentViewPicker(context);
    const options = new picker.DocumentSaveOptions();
    const date: Date = new Date();
    const stamp: string = `${date.getFullYear()}${`${date.getMonth() + 1}`.padStart(2, '0')}${`${date.getDate()}`.padStart(2, '0')}-${`${date.getHours()}`.padStart(2, '0')}${`${date.getMinutes()}`.padStart(2, '0')}${`${date.getSeconds()}`.padStart(2, '0')}`;
    options.newFileNames = [`gdut-helper-backup-${stamp}.json`];
    options.fileSuffixChoices = ['工大助手备份|.json'];
    const uris: string[] = await pickerInstance.save(options);
    if (uris.length === 0) {
      throw new Error('未选择保存位置');
    }
    writeText(uris[0], JSON.stringify(bundle));
    return uris[0];
  }

  static async pickFile(context: common.UIAbilityContext, kind: string): Promise<string> {
    const pickerInstance = new picker.DocumentViewPicker(context);
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    if (kind === 'json') {
      options.fileSuffixFilters = ['工大助手备份|.json'];
    } else if (kind === 'ics') {
      options.fileSuffixFilters = ['日历文件|.ics'];
    } else {
      options.fileSuffixFilters = ['Excel 表格|.xlsx'];
    }
    const uris: string[] = await pickerInstance.select(options);
    if (uris.length === 0) {
      throw new Error('未选择文件');
    }
    return uris[0];
  }

  static readTextUri(uri: string): string {
    return readText(uri);
  }

  static async parseBundle(text: string): Promise<BackupBundle> {
    let bundle: BackupBundle;
    try {
      bundle = JSON.parse(text) as BackupBundle;
    } catch (error) {
      throw new Error('备份文件不是有效的 JSON');
    }
    if (bundle.format !== FORMAT) {
      throw new Error('不是 工大助手备份文件');
    }
    if (bundle.version !== 1 && bundle.version !== VERSION) {
      throw new Error(`不支持的备份版本：${bundle.version}`);
    }
    if (!Array.isArray(bundle.semesters) || !Array.isArray(bundle.courses) ||
      !Array.isArray(bundle.exceptions) || !Array.isArray(bundle.events)) {
      throw new Error('备份文件缺少必要数据');
    }
    bundle = migrateBundle(bundle);
    if (bundle.checksum.length > 0) {
      const actual: string = await checksumOf(bundle);
      if (actual !== bundle.checksum) {
        throw new Error('备份文件校验失败，可能已损坏');
      }
    }
    return bundle;
  }

  static async readBundle(context: common.UIAbilityContext): Promise<BackupBundle> {
    const uri: string = await BackupService.pickFile(context, 'json');
    return BackupService.parseBundle(readText(uri));
  }

  static async clearLocalData(context: common.UIAbilityContext): Promise<void> {
    await TimetableRepository.clearAllData(context);
    await GradeService.clearCache(context);
    await TzcsCacheService.clear(context);
    await JwcwxCache.clear(context);
    WidgetSnapshotService.clear(context);
    try {
      await SystemCalendarSyncService.removeSynced(context);
      await ReminderService.clearScheduled(context);
    } catch (error) {
      // Device integrations are best effort.
    }
  }

  static async restore(context: common.UIAbilityContext, bundle: BackupBundle): Promise<void> {
    const store: relationalStore.RdbStore = await Database.get(context);
    await store.beginTransaction();
    try {
      await TimetableRepository.clearAllData(context);
      for (const semester of bundle.semesters) {
        await TimetableRepository.saveSemester(context, semester);
      }
      for (const period of bundle.periods) {
        await TimetableRepository.savePeriod(context, period);
      }
      for (const course of bundle.courses) {
        await TimetableRepository.saveCourse(context, course);
      }
      for (const exception of bundle.exceptions) {
        await TimetableRepository.saveException(context, exception);
      }
      for (const event of bundle.events) {
        await TimetableRepository.upsertEvent(context, event);
      }
      for (const tombstone of bundle.tombstones) {
        await TimetableRepository.addTombstone(context, tombstone.semesterId, tombstone.courseKey);
      }
      await store.commit();
    } catch (error) {
      await store.rollBack();
      throw new Error('恢复失败，已回滚');
    }
    await putPrefString(context, 'grade_cache', 'grades', bundle.grades);
    await putPrefString(context, 'tzcs_cache', 'reports', bundle.tzcs);
    const settingsStore = await preferences.getPreferences(context, 'appearance_settings');
    await settingsStore.put('themeMode', bundle.settings.themeMode);
    await settingsStore.put(IMMERSIVE_KEY, bundle.settings.immersiveEnabled);
    await settingsStore.put(HANDEDNESS_KEY, bundle.settings.handednessEnabled);
    await settingsStore.flush();
    AppStorage.setOrCreate(IMMERSIVE_KEY, bundle.settings.immersiveEnabled);
    AppStorage.setOrCreate(HANDEDNESS_KEY, bundle.settings.handednessEnabled);
    AppearanceSettings.apply(context, bundle.settings.themeMode === ThemeMode.LIGHT ? ThemeMode.LIGHT :
      (bundle.settings.themeMode === ThemeMode.DARK ? ThemeMode.DARK : ThemeMode.SYSTEM));
    await DisplaySettings.set(context, bundle.settings.showCourseContent);
    await DisplaySettings.setCampusNewsEnabled(context, bundle.settings.campusNewsEnabled !== false);
    await DisplaySettings.setCampusDataEnabled(context, bundle.settings.campusDataEnabled !== false);
    await DisplaySettings.setLocalNotificationsEnabled(context, bundle.settings.localNotificationsEnabled === true);
    await AppearanceSettings.setThemeColor(context, bundle.settings.themeColorId ?? 'harmony');
    await AppearanceSettings.setMaterialLevel(context, bundle.settings.materialLevel ?? 10);
    try {
      await SystemCalendarSyncService.removeSynced(context);
      await ReminderService.clearScheduled(context);
    } catch (error) {
      // Device calendar/reminder cleanup is best effort.
    }
  }
}
