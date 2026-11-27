import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const DATABASE_NAME: string = 'gdut_helper.db';
const DATABASE_VERSION: number = 5;

/**
 * Single RDB entry point. M1 uses versioned schema creation; future migrations
 * are added as ordered steps and bump DATABASE_VERSION.
 */
export class Database {
  private static store: relationalStore.RdbStore | null = null;
  private static opening: Promise<relationalStore.RdbStore> | null = null;

  static async get(context: common.Context): Promise<relationalStore.RdbStore> {
    if (Database.store !== null) {
      return Database.store;
    }
    if (Database.opening === null) {
      Database.opening = Database.open(context);
    }
    Database.store = await Database.opening;
    return Database.store;
  }

  private static async open(context: common.Context): Promise<relationalStore.RdbStore> {
    const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, {
      name: DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    });
    if (store.version < 1) {
      await Database.migrateV1(store);
      store.version = 1;
    }
    if (store.version < 2) {
      await Database.migrateV2(store);
      store.version = 2;
    }
    if (store.version < 3) {
      await Database.migrateV3(store);
      store.version = 3;
    }
    if (store.version < 4) {
      await Database.migrateV4(store);
      store.version = 4;
    }
    if (store.version < 5) {
      await Database.migrateV5(store);
      store.version = 5;
    }
    return store;
  }

  private static async migrateV1(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql(
      `CREATE TABLE IF NOT EXISTS semesters (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        start_date TEXT NOT NULL,
        total_weeks INTEGER NOT NULL,
        is_current INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )`
    );
    await store.executeSql(
      `CREATE TABLE IF NOT EXISTS periods (
        semester_id TEXT NOT NULL,
        period_index INTEGER NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        PRIMARY KEY (semester_id, period_index)
      )`
    );
    await store.executeSql(
      `CREATE TABLE IF NOT EXISTS courses (
        id TEXT PRIMARY KEY,
        semester_id TEXT NOT NULL,
        name TEXT NOT NULL,
        teacher TEXT NOT NULL DEFAULT '',
        room TEXT NOT NULL DEFAULT '',
        weekday INTEGER NOT NULL,
        start_period INTEGER NOT NULL,
        end_period INTEGER NOT NULL,
        weeks TEXT NOT NULL,
        color_key INTEGER NOT NULL DEFAULT 0,
        note TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT 'MANUAL',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )`
    );
    await store.executeSql(
      `CREATE TABLE IF NOT EXISTS course_exceptions (
        id TEXT PRIMARY KEY,
        course_id TEXT NOT NULL,
        week INTEGER NOT NULL,
        type TEXT NOT NULL,
        new_weekday INTEGER NOT NULL DEFAULT 0,
        new_start_period INTEGER NOT NULL DEFAULT 0,
        new_end_period INTEGER NOT NULL DEFAULT 0,
        new_room TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )`
    );
    await store.executeSql(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_exception_course_week ON course_exceptions(course_id, week)'
    );
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_course_semester ON courses(semester_id)');
  }

  private static async migrateV2(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql("ALTER TABLE semesters ADD COLUMN term_code TEXT NOT NULL DEFAULT ''");
    await store.executeSql(
      `CREATE TABLE IF NOT EXISTS events (
        id TEXT PRIMARY KEY,
        semester_id TEXT NOT NULL,
        title TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER NOT NULL,
        all_day INTEGER NOT NULL DEFAULT 0,
        location TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT 'GENERAL',
        source TEXT NOT NULL DEFAULT 'MANUAL',
        external_id TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )`
    );
    await store.executeSql(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_event_external ON events(semester_id, external_id)'
    );
    await store.executeSql(
      `CREATE TABLE IF NOT EXISTS course_tombstones (
        semester_id TEXT NOT NULL,
        course_key TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (semester_id, course_key)
      )`
    );
  }

  private static async migrateV3(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql("ALTER TABLE courses ADD COLUMN content TEXT NOT NULL DEFAULT ''");
  }

  private static async migrateV4(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql(
      "ALTER TABLE course_exceptions ADD COLUMN source TEXT NOT NULL DEFAULT 'MANUAL'"
    );
  }

  /** v5: 选课任务 / 抢课队列 / 运行日志。 */
  private static async migrateV5(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql(
      `CREATE TABLE IF NOT EXISTS selection_task (
        id INTEGER PRIMARY KEY,
        term_code TEXT NOT NULL DEFAULT '',
        start_at INTEGER NOT NULL DEFAULT 0,
        interval_ms INTEGER NOT NULL DEFAULT 500,
        priority_mode INTEGER NOT NULL DEFAULT 1,
        auto_retry INTEGER NOT NULL DEFAULT 1,
        sync_after INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'IDLE',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )`
    );
    await store.executeSql(
      `CREATE TABLE IF NOT EXISTS selection_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER NOT NULL,
        kcrwdm TEXT NOT NULL,
        kcmc TEXT NOT NULL,
        teacher TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT '',
        capacity INTEGER NOT NULL DEFAULT 0,
        chosen INTEGER NOT NULL DEFAULT 0,
        position INTEGER NOT NULL DEFAULT 0,
        state TEXT NOT NULL DEFAULT 'PENDING',
        last_message TEXT NOT NULL DEFAULT '',
        attempts INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )`
    );
    await store.executeSql(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_selection_queue_code ON selection_queue(kcrwdm)'
    );
    await store.executeSql(
      `CREATE TABLE IF NOT EXISTS selection_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER NOT NULL,
        at INTEGER NOT NULL,
        kcrwdm TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL DEFAULT '',
        outcome TEXT NOT NULL DEFAULT '',
        message TEXT NOT NULL DEFAULT '',
        rtt_ms INTEGER NOT NULL DEFAULT 0
      )`
    );
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_selection_log_at ON selection_logs(at)');
  }
}
