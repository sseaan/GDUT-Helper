/** CalDAV（Radicale 等）单向上传课表所需的模型与错误分类。 */

export enum CalDavErrorKind {
  /** 未填写服务器地址。 */
  NOT_CONFIGURED = 'NOT_CONFIGURED',
  /** 401 / 403：账号密码不对，或集合不允许写入。 */
  AUTH = 'AUTH',
  /** 404：集合不存在（多半是没先在客户端里建日历）。 */
  NOT_FOUND = 'NOT_FOUND',
  /** 412 且重试后仍然冲突。 */
  CONFLICT = 'CONFLICT',
  /** 网络 / 超时。 */
  NETWORK = 'NETWORK',
  /** 其它状态码或响应异常。 */
  PROTOCOL = 'PROTOCOL'
}

export class CalDavError extends Error {
  readonly kind: CalDavErrorKind;
  readonly status: number;

  constructor(message: string, kind: CalDavErrorKind = CalDavErrorKind.PROTOCOL, status: number = 0) {
    super(message);
    this.kind = kind;
    this.status = status;
  }
}

/** 本地保存的 CalDAV 配置；密码单独进 Asset Store。 */
export interface CalDavConfig {
  /** 日历集合地址，结尾带 `/`。 */
  url: string;
  username: string;
  /** 课表同步完成后自动推送。 */
  enabled: boolean;
  /** 上次推送成功后服务器返回的 ETag，用于条件更新。 */
  lastEtag: string;
  lastPushedAt: number;
  lastEventCount: number;
}

export interface CalDavPushResult {
  /** 当前学期展开后的事件总数。 */
  events: number;
  /** 本次实际写入的事件数。 */
  uploaded: number;
  /** 本次删除的失效事件数。 */
  deleted: number;
  /** 内容没变化、跳过的事件数。 */
  unchanged: number;
  /** 写入/删除失败的事件数。 */
  failed: number;
}

export function emptyCalDavConfig(): CalDavConfig {
  return {
    url: '',
    username: '',
    enabled: false,
    lastEtag: '',
    lastPushedAt: 0,
    lastEventCount: 0
  };
}
