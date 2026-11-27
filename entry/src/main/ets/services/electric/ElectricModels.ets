/** 电精灵（bd.bdfairy.cn）的校区与数据模型。 */

export enum ElectricErrorKind {
  /** 网络 / 超时。无效表号在该站点上通常表现为无响应，也归到这里。 */
  NETWORK = 'NETWORK',
  /** 表号被拒（站点返回 msg 且无跳转地址）。 */
  INVALID_METER = 'INVALID_METER',
  /** 页面能打开但没有读到读数。 */
  EMPTY = 'EMPTY',
  /** 页面结构变化，解析失败。 */
  PARSE = 'PARSE'
}

export class ElectricError extends Error {
  readonly kind: ElectricErrorKind;

  constructor(message: string, kind: ElectricErrorKind = ElectricErrorKind.NETWORK) {
    super(message);
    this.kind = kind;
  }
}

/** `areaId` / `areaName` 必须与站点注册表一致，`label` 只用于界面展示。 */
export interface ElectricCampus {
  areaId: string;
  areaName: string;
  label: string;
}

export interface MeterReading {
  campusLabel: string;
  meter: string;
  /** 站点回填的房号，可能是空。 */
  room: string;
  prepaidYuan: string;
  subsidyYuan: string;
  totalYuan: string;
  totalKwh: string;
  meterStatus: string;
  readingTime: string;
  billMonth: string;
  billKwh: string;
  billYuan: string;
  fetchedAt: number;
}

/**
 * 广工在电精灵上的三个 areaId（站点 tier=full：余额/账单/明细均可用）。
 * 54 覆盖大学城东西区、东风路、龙洞；136 番禺；128 揭阳。
 */
export const ELECTRIC_CAMPUSES: ElectricCampus[] = [
  {
    areaId: '54',
    areaName: '广东工业大学(大学城东西区/东风路/龙洞校区)',
    label: '大学城/东风路/龙洞'
  },
  {
    areaId: '136',
    areaName: '广东工业大学(番禺校区)',
    label: '番禺'
  },
  {
    areaId: '128',
    areaName: '广东工业大学(揭阳校区)',
    label: '揭阳'
  }
];
