export enum PortalErrorKind {
  NETWORK = 'NETWORK',
  CREDENTIALS = 'CREDENTIALS',
  SESSION = 'SESSION',
  PROTOCOL = 'PROTOCOL'
}

export class PortalError extends Error {
  readonly kind: PortalErrorKind;

  constructor(message: string, kind: PortalErrorKind = PortalErrorKind.PROTOCOL) {
    super(message);
    this.kind = kind;
  }
}

/** One resolved personal card from ehall's CUS_CARD_MYDATA. */
export interface PortalPersonalCard {
  wid: string;
  title: string;
  iconUrl: string;
  mainInfo: string;
  subInfo: string;
  linkUrl: string;
  needRetrieve: boolean;
  accessTime: string;
}

export interface PortalDashboard {
  campusCard: PortalPersonalCard | null;
  library: PortalPersonalCard | null;
  network: PortalPersonalCard | null;
  fetchedAt: number;
}

export interface PortalNewsItem {
  title: string;
  channelName: string;
  pubTime: string;
  picUrl: string;
  url: string;
  wid: string;
  contents: string;
  author: string;
}

export interface PortalNewsPage {
  items: PortalNewsItem[];
  total: number;
  page: number;
  pageSize: number;
  fetchedAt: number;
}

export interface PortalNewsPreview {
  hero: PortalNewsItem | null;
  feed: PortalNewsItem | null;
  fetchedAt: number;
}

export interface PortalNewsChannel {
  id: string;
  name: string;
}

/**
 * Campus-page news uses the 通知简讯网 channels, not the official-site
 * headlines. 最新简讯 is the default preview source.
 */
export const PORTAL_NEWS_CHANNELS: PortalNewsChannel[] = [
  { id: '1750415095823806466', name: '最新简讯' },
  { id: '1750414748292165634', name: '校内通知' },
  { id: '1740368235659382786', name: '公示公告' },
  { id: '1750415322458963969', name: '招标公告' }
];
