import { common } from '@kit.AbilityKit';
import { TimetableRepository } from '../../data/TimetableRepository';
import { Semester } from '../../domain/model/TimetableModels';
import { IcsEventItem, IcsExportService } from '../importexport/IcsExportService';
import { CalDavClient } from './CalDavClient';
import { CalDavConfig, CalDavError, CalDavErrorKind, CalDavPushResult } from './CalDavModels';
import { CalDavIndex, CalDavIndexEntry } from './CalDavIndex';
import { CalDavSettings } from './CalDavSettings';

const CONCURRENCY: number = 3;

export type CalDavProgress = (done: number, total: number) => void;

/**
 * 课表 → CalDAV 单向镜像。
 *
 * 每个事件一个资源（Radicale 不接受多组件文档），本地索引记录上次推过的 UID/内容指纹：
 * 只推新增和变化的，删掉已经不存在的事件，没变化的一次网络请求都不发。
 */
export class CalDavSyncService {
  /** 手动推送：配置类错误会抛给页面。 */
  static async push(context: common.Context, onProgress?: CalDavProgress): Promise<CalDavPushResult> {
    const semester: Semester | null = await TimetableRepository.getCurrentSemester(context);
    if (semester === null) {
      throw new CalDavError('还没有当前学期，先同步或设置学期', CalDavErrorKind.NOT_CONFIGURED);
    }
    const config: CalDavConfig = await CalDavSettings.load(context);
    if (CalDavClient.normalize(config.url).length === 0) {
      throw new CalDavError('请先填写日历集合地址', CalDavErrorKind.NOT_CONFIGURED);
    }
    const password: string = await CalDavSettings.password();
    const events: IcsEventItem[] = await IcsExportService.buildEvents(context);
    const previous: CalDavIndexEntry[] = await CalDavIndex.load(context);

    const previousByUid: Record<string, CalDavIndexEntry> = {};
    for (const entry of previous) {
      previousByUid[entry.uid] = entry;
    }
    const currentUids: Record<string, boolean> = {};

    const pending: IcsEventItem[] = [];
    const entries: CalDavIndexEntry[] = [];
    for (const event of events) {
      const name: string = CalDavClient.resourceName(event.uid);
      const entry: CalDavIndexEntry = { uid: event.uid, name: name, hash: event.hash };
      currentUids[event.uid] = true;
      const known: CalDavIndexEntry | undefined = previousByUid[event.uid];
      if (known !== undefined && known.hash === event.hash && known.name === name) {
        entries.push(entry);
        continue;
      }
      pending.push(event);
    }

    const removals: CalDavIndexEntry[] = [];
    for (const entry of previous) {
      if (currentUids[entry.uid] !== true) {
        removals.push(entry);
      }
    }

    let failed: number = 0;
    let firstError: CalDavError | null = null;
    let uploaded: number = 0;

    const total: number = pending.length;
    let done: number = 0;
    for (let start = 0; start < pending.length; start += CONCURRENCY) {
      const slice: IcsEventItem[] = pending.slice(start, start + CONCURRENCY);
      const tasks: Promise<void>[] = [];
      for (const event of slice) {
        tasks.push(CalDavClient.putResource(config, password,
          CalDavClient.resourceName(event.uid), event.body)
          .then(() => {
            uploaded++;
            entries.push({ uid: event.uid, name: CalDavClient.resourceName(event.uid), hash: event.hash });
          })
          .catch((error: Object) => {
            failed++;
            if (firstError === null && error instanceof CalDavError) {
              firstError = error as CalDavError;
            }
          }));
      }
      await Promise.all(tasks);
      done += slice.length;
      if (onProgress !== undefined && total > 0) {
        onProgress(done, total);
      }
    }

    // 上传完成后再清理失效项：中途失败时宁可短暂重复，也不要把日历删空。
    for (const entry of removals) {
      try {
        await CalDavClient.deleteResource(config, password, entry.name);
      } catch (error) {
        failed++;
        if (firstError === null && error instanceof CalDavError) {
          firstError = error;
        }
        entries.push(entry);
      }
    }

    if (failed > 0 && uploaded === 0 && firstError !== null) {
      throw firstError;
    }

    await CalDavIndex.save(context, entries);
    config.lastEtag = '';
    config.lastPushedAt = Date.now();
    config.lastEventCount = events.length;
    await CalDavSettings.save(context, config);

    return {
      events: events.length,
      uploaded: uploaded,
      deleted: removals.length,
      unchanged: events.length - uploaded - failed,
      failed: failed
    };
  }

  /** 自动推送：教务同步后调用，失败只留状态，不打断主流程。 */
  static async pushIfEnabled(context: common.Context): Promise<void> {
    try {
      const config: CalDavConfig = await CalDavSettings.load(context);
      if (!config.enabled || CalDavClient.normalize(config.url).length === 0) {
        return;
      }
      await CalDavSyncService.push(context);
    } catch (error) {
      // 日历只是镜像，失败不能影响本地课表与教务同步。
    }
  }

  /** 清空远端：删除索引里记录过的所有资源，用于换服务器或关功能。 */
  static async wipeRemote(context: common.Context): Promise<number> {
    const config: CalDavConfig = await CalDavSettings.load(context);
    const password: string = await CalDavSettings.password();
    const entries: CalDavIndexEntry[] = await CalDavIndex.load(context);
    let removed: number = 0;
    const remaining: CalDavIndexEntry[] = [];
    for (const entry of entries) {
      try {
        await CalDavClient.deleteResource(config, password, entry.name);
        removed++;
      } catch (error) {
        // 单个失败不阻塞，索引里留着下次继续删。
        remaining.push(entry);
      }
    }
    if (remaining.length === 0) {
      await CalDavIndex.clear(context);
    } else {
      await CalDavIndex.save(context, remaining);
    }
    return removed;
  }
}
