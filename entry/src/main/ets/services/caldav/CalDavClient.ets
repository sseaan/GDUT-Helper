import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { stableHash } from '../../common/StableHash';
import { CalDavConfig, CalDavError, CalDavErrorKind } from './CalDavModels';

const CONNECT_TIMEOUT: number = 10000;
const READ_TIMEOUT: number = 20000;
const CALENDAR_TYPE: string = 'text/calendar; charset=utf-8';

function text(value: string | number | undefined | null): string {
  if (value === undefined || value === null) {
    return '';
  }
  return `${value}`.trim();
}

function basicAuth(username: string, password: string): string {
  const raw: string = `${username}:${password}`;
  const bytes: Uint8Array = new util.TextEncoder().encodeInto(raw);
  return `Basic ${new util.Base64Helper().encodeToStringSync(bytes)}`;
}

/**
 * 最小可用的 CalDAV 写入客户端。
 *
 * 两个来自实践的约束：
 * 1. HarmonyOS 的 `http.RequestMethod` 没有 PROPFIND / REPORT / MKCALENDAR，
 *    所以不发现、不建日历，用户直接填建好的日历集合地址；
 * 2. Radicale 要求「一个资源一个组件」，多 VEVENT 的整学期文件会被 400 拒掉，
 *    因此这里按事件逐个 PUT，文件名由 UID 派生。
 */
export class CalDavClient {
  /** 补全协议、去空格、保证结尾斜杠。 */
  static normalize(url: string): string {
    let value: string = url.trim();
    if (value.length === 0) {
      return '';
    }
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = `https://${value}`;
    }
    if (!value.endsWith('/')) {
      value = `${value}/`;
    }
    return value;
  }

  /** UID → 稳定资源名，重推时覆盖同一个文件。 */
  static resourceName(uid: string): string {
    return `gdut-${stableHash(uid)}.ics`;
  }

  /** 集合是否可达（HEAD，仅用于「测试连接」）。 */
  static async probe(config: CalDavConfig, password: string): Promise<void> {
    const base: string = CalDavClient.requireUrl(config);
    const client = http.createHttp();
    try {
      const response: http.HttpResponse = await client.request(base, {
        method: http.RequestMethod.HEAD,
        header: CalDavClient.headers(config, password, false),
        connectTimeout: CONNECT_TIMEOUT,
        readTimeout: READ_TIMEOUT,
        expectDataType: http.HttpDataType.STRING
      });
      if (response.responseCode >= 400) {
        throw CalDavClient.errorOf(response.responseCode);
      }
    } catch (error) {
      throw CalDavClient.wrap(error);
    } finally {
      client.destroy();
    }
  }

  /** 写入单个事件资源；201（新建）和 204（覆盖）都算成功。 */
  static async putResource(
    config: CalDavConfig,
    password: string,
    name: string,
    body: string
  ): Promise<void> {
    const url: string = `${CalDavClient.requireUrl(config)}${name}`;
    const client = http.createHttp();
    try {
      const response: http.HttpResponse = await client.request(url, {
        method: http.RequestMethod.PUT,
        header: CalDavClient.headers(config, password, true),
        connectTimeout: CONNECT_TIMEOUT,
        readTimeout: READ_TIMEOUT,
        expectDataType: http.HttpDataType.STRING,
        extraData: body
      });
      if (response.responseCode >= 400) {
        throw CalDavClient.errorOf(response.responseCode);
      }
    } catch (error) {
      throw CalDavClient.wrap(error);
    } finally {
      client.destroy();
    }
  }

  /** 删除失效事件；404 视为已删除。 */
  static async deleteResource(config: CalDavConfig, password: string, name: string): Promise<void> {
    const url: string = `${CalDavClient.requireUrl(config)}${name}`;
    const client = http.createHttp();
    try {
      const response: http.HttpResponse = await client.request(url, {
        method: http.RequestMethod.DELETE,
        header: CalDavClient.headers(config, password, false),
        connectTimeout: CONNECT_TIMEOUT,
        readTimeout: READ_TIMEOUT,
        expectDataType: http.HttpDataType.STRING
      });
      if (response.responseCode >= 400 && response.responseCode !== 404) {
        throw CalDavClient.errorOf(response.responseCode);
      }
    } catch (error) {
      throw CalDavClient.wrap(error);
    } finally {
      client.destroy();
    }
  }

  private static headers(config: CalDavConfig, password: string, json: boolean): Record<string, string> {
    const header: Record<string, string> = { 'Accept': 'text/calendar, */*' };
    if (json) {
      header['Content-Type'] = CALENDAR_TYPE;
    }
    if (config.username.length > 0) {
      header['Authorization'] = basicAuth(config.username, password);
    }
    return header;
  }

  private static requireUrl(config: CalDavConfig): string {
    const url: string = CalDavClient.normalize(config.url);
    if (url.length === 0) {
      throw new CalDavError('请先填写日历集合地址', CalDavErrorKind.NOT_CONFIGURED);
    }
    return url;
  }

  private static errorOf(status: number): CalDavError {
    if (status === 401 || status === 403) {
      return new CalDavError('服务器拒绝了写入，请检查用户名和密码', CalDavErrorKind.AUTH, status);
    }
    if (status === 404) {
      return new CalDavError('日历集合不存在，请先在日历应用里建好日历后填入它的地址',
        CalDavErrorKind.NOT_FOUND, status);
    }
    if (status === 409) {
      return new CalDavError('日历里已存在相同 UID 的事件（可能是之前导入过导出的 ICS），请清理后重试',
        CalDavErrorKind.CONFLICT, status);
    }
    if (status === 412) {
      return new CalDavError('远端刚被其它客户端改过，请重试', CalDavErrorKind.CONFLICT, status);
    }
    return new CalDavError(`服务器返回 HTTP ${status}`, CalDavErrorKind.PROTOCOL, status);
  }

  private static wrap(error: Object): CalDavError {
    if (error instanceof CalDavError) {
      return error;
    }
    const failure: BusinessError = error as BusinessError;
    const suffix: string = failure.code === undefined || failure.code === null ? '' : `（${failure.code}）`;
    return new CalDavError(`无法连接日历服务器${suffix}，请检查地址与网络`, CalDavErrorKind.NETWORK);
  }
}
