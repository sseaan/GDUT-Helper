import { PortalNewsItem, PortalPersonalCard } from './PortalModels';

export interface PortalCardDisplay {
  value: string;
  sub: string;
}

function firstNumber(value: string): number {
  const match: RegExpExecArray | null = /(\d+(?:\.\d+)?)/.exec(value);
  if (match === null) {
    return 0;
  }
  const parsed: number = Number.parseFloat(match[1]);
  return Number.isNaN(parsed) ? 0 : parsed;
}

function moneyText(value: number): string {
  if (Math.abs(value - Math.round(value)) < 0.0001) {
    return `${Math.round(value)}`;
  }
  return value.toFixed(2);
}

export function campusCardDisplay(card: PortalPersonalCard | null): PortalCardDisplay {
  if (card === null) {
    return { value: '--', sub: '未获取' };
  }
  const balance: number = firstNumber(card.mainInfo);
  const cardMatch: RegExpExecArray | null = /您卡号[：:]\s*(\S+)/.exec(card.subInfo);
  let tail: string = '';
  if (cardMatch !== null) {
    const cardNo: string = cardMatch[1];
    tail = cardNo.length > 4 ? cardNo.substring(cardNo.length - 4) : cardNo;
  }
  return {
    value: `¥${moneyText(balance)}`,
    sub: tail.length > 0 ? `尾号 ${tail}` : '校园卡'
  };
}

function libraryNumbers(card: PortalPersonalCard): string {
  const parts: string[] = card.subInfo.split('；');
  const due: number = firstNumber(parts.length > 0 ? parts[0] : '');
  const overdue: number = firstNumber(parts.length > 1 ? parts[1] : '');
  return `即将到期 ${due} · 超期 ${overdue}`;
}

export function libraryDisplay(card: PortalPersonalCard | null): PortalCardDisplay {
  if (card === null) {
    return { value: '--', sub: '未获取' };
  }
  const total: number = firstNumber(card.mainInfo);
  return {
    value: `${total}`,
    sub: libraryNumbers(card)
  };
}

export function networkDisplay(card: PortalPersonalCard | null): PortalCardDisplay {
  if (card === null) {
    return { value: '--', sub: '未获取' };
  }
  const balance: number = firstNumber(card.mainInfo);
  const monthMatch: RegExpExecArray | null = /剩余月数[：:]\s*(\d+)/.exec(card.subInfo);
  const statusMatch: RegExpExecArray | null = /状态[：:]\s*([^，,\s]+)/.exec(card.subInfo);
  const parts: string[] = [];
  if (monthMatch !== null) {
    parts.push(`剩余 ${monthMatch[1]} 个月`);
  }
  if (statusMatch !== null) {
    parts.push(statusMatch[1]);
  }
  return {
    value: `${moneyText(balance)}元`,
    sub: parts.length > 0 ? parts.join(' · ') : '校园网'
  };
}

/** Returns a short relative label used by the news cards. */
export function relativeNewsTime(pubTime: string, now: Date = new Date()): string {
  const match: RegExpExecArray | null = /^(\d{4})[\/-](\d{1,2})[\/-](\d{1,2})/.exec(pubTime.trim());
  if (match === null) {
    return pubTime;
  }
  const date: Date = new Date(Number.parseInt(match[1], 10), Number.parseInt(match[2], 10) - 1,
    Number.parseInt(match[3], 10));
  const today: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const target: Date = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const days: number = Math.round((today.getTime() - target.getTime()) / 86400000);
  if (days <= 0) {
    return '今天';
  }
  if (days === 1) {
    return '昨天';
  }
  if (days < 7) {
    return `${days} 天前`;
  }
  return `${match[1]}/${match[2]}/${match[3]}`;
}

/** The portal appends the publish date to some titles; remove it for display. */
export function cleanNewsTitle(title: string): string {
  return title.replace(/\s*\d{4}-\d{1,2}-\d{1,2}\s*$/, '').trim();
}

export function updateTimeLabel(fetchedAt: number, now: number, loading: boolean,
  loggedIn: boolean, error: string): string {
  if (loading && fetchedAt === 0) {
    return '更新中…';
  }
  if (!loggedIn) {
    return '未登录';
  }
  if (error.length > 0 && fetchedAt === 0) {
    return '更新失败';
  }
  if (fetchedAt === 0) {
    return '尚未更新';
  }
  const minutes: number = Math.max(0, Math.floor((now - fetchedAt) / 60000));
  if (minutes < 1) {
    return '更新于 0 分钟前';
  }
  if (minutes < 60) {
    return `更新于 ${minutes} 分钟前`;
  }
  const hours: number = Math.floor(minutes / 60);
  if (hours < 24) {
    return `更新于 ${hours} 小时前`;
  }
  return `更新于 ${Math.floor(hours / 24)} 天前`;
}

export function newsImage(item: PortalNewsItem | null): string {
  return item === null ? '' : item.picUrl;
}
