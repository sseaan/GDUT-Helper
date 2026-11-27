import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';

const INDEX_FILE: string = 'caldav_index.json';

/** 已推送到远端的一个资源。 */
export interface CalDavIndexEntry {
  uid: string;
  /** 资源文件名，例如 `gdut-1a2b3c4d5e6f7a8b.ics`。 */
  name: string;
  /** 内容指纹，用于跳过没变化的事件。 */
  hash: string;
}

/**
 * 推送索引。
 *
 * Radicale 要求「一个资源一个组件」，所以一个学期会变成几百个 .ics；
 * 索引记着上次推了哪些，用来做增量（只推变化的）和清理（删掉已消失的）。
 * 只放在应用沙箱里，不进 RDB、不进备份。
 */
export class CalDavIndex {
  static async load(context: common.Context): Promise<CalDavIndexEntry[]> {
    const path: string = `${context.filesDir}/${INDEX_FILE}`;
    try {
      if (!fs.accessSync(path)) {
        return [];
      }
      const text: string = fs.readTextSync(path);
      const parsed: CalDavIndexEntry[] = JSON.parse(text) as CalDavIndexEntry[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (error) {
      return [];
    }
  }

  static async save(context: common.Context, entries: CalDavIndexEntry[]): Promise<void> {
    const path: string = `${context.filesDir}/${INDEX_FILE}`;
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, JSON.stringify(entries));
    } finally {
      fs.closeSync(file);
    }
  }

  static async clear(context: common.Context): Promise<void> {
    const path: string = `${context.filesDir}/${INDEX_FILE}`;
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (error) {
      // 没有索引属于正常状态。
    }
  }
}
