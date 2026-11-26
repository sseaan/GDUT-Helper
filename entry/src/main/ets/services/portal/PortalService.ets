import { PortalClient } from './PortalClient';
import {
  PortalDashboard,
  PortalNewsItem,
  PortalNewsPage,
  PortalNewsPreview,
  PORTAL_NEWS_CHANNELS,
  PortalPersonalCard
} from './PortalModels';
import { PortalSession } from './PortalSession';

const DASHBOARD_TTL_MS: number = 5 * 60 * 1000;
const NEWS_TTL_MS: number = 3 * 60 * 1000;

function findCard(cards: PortalPersonalCard[], keyword: string): PortalPersonalCard | null {
  const card: PortalPersonalCard | undefined =
    cards.find((item: PortalPersonalCard) => item.title.includes(keyword));
  return card === undefined ? null : card;
}

export class PortalService {
  private static dashboardCache: PortalDashboard | null = null;
  private static newsPreviewCache: PortalNewsPreview | null = null;
  private static newsPages: Map<string, PortalNewsPage> = new Map();

  static cachedDashboard(): PortalDashboard | null {
    return PortalService.dashboardCache;
  }

  static cachedNewsPreview(): PortalNewsPreview | null {
    return PortalService.newsPreviewCache;
  }

  static clearCache(): void {
    PortalService.dashboardCache = null;
    PortalService.newsPreviewCache = null;
    PortalService.newsPages.clear();
  }

  static clearSession(): void {
    PortalService.clearCache();
    PortalSession.clear();
  }

  static async loadDashboard(force: boolean = false): Promise<PortalDashboard> {
    const now: number = Date.now();
    if (!force && PortalService.dashboardCache !== null &&
      now - PortalService.dashboardCache.fetchedAt < DASHBOARD_TTL_MS) {
      return PortalService.dashboardCache;
    }
    const cards: PortalPersonalCard[] = await PortalClient.fetchPersonalCards();
    let campusCard: PortalPersonalCard | null = findCard(cards, '校园卡');
    let library: PortalPersonalCard | null = findCard(cards, '图书借阅');
    let network: PortalPersonalCard | null = findCard(cards, '校园网');

    if (campusCard !== null && campusCard.needRetrieve) {
      campusCard = await PortalService.detailOr(campusCard);
    }
    if (library !== null && library.needRetrieve) {
      library = await PortalService.detailOr(library);
    }
    if (network !== null && network.needRetrieve) {
      network = await PortalService.detailOr(network);
    }

    const dashboard: PortalDashboard = {
      campusCard: campusCard,
      library: library,
      network: network,
      fetchedAt: now
    };
    PortalService.dashboardCache = dashboard;
    return dashboard;
  }

  private static async detailOr(card: PortalPersonalCard): Promise<PortalPersonalCard> {
    try {
      const detail: PortalPersonalCard | null =
        await PortalClient.fetchPersonalCardDetail(card.wid);
      return detail === null ? card : detail;
    } catch (error) {
      return card;
    }
  }

  private static async enrichImage(item: PortalNewsItem | null): Promise<void> {
    if (item === null || item.picUrl.length > 0 || item.url.length === 0) {
      return;
    }
    const image: string = await PortalClient.fetchArticleImage(item.url);
    if (image.length > 0) {
      item.picUrl = image;
    }
  }

  static async loadNewsPreview(force: boolean = false): Promise<PortalNewsPreview> {
    const now: number = Date.now();
    if (!force && PortalService.newsPreviewCache !== null &&
      now - PortalService.newsPreviewCache.fetchedAt < NEWS_TTL_MS) {
      return PortalService.newsPreviewCache;
    }
    const page: PortalNewsPage =
      await PortalClient.fetchNews(PORTAL_NEWS_CHANNELS[0].id, 1);
    const hero: PortalNewsItem | null = page.items.find((item: PortalNewsItem) =>
      item.picUrl.length > 0) ?? (page.items.length > 0 ? page.items[0] : null);
    let feed: PortalNewsItem | null = null;
    if (hero !== null) {
      feed = page.items.find((item: PortalNewsItem) =>
        item.wid !== hero.wid && item.picUrl.length > 0) ?? null;
      if (feed === null) {
        feed = page.items.find((item: PortalNewsItem) => item.wid !== hero.wid) ?? null;
      }
    }
    await PortalService.enrichImage(hero);
    if (feed !== null && feed.wid !== (hero === null ? '' : hero.wid)) {
      await PortalService.enrichImage(feed);
    }
    const preview: PortalNewsPreview = {
      hero: hero,
      feed: feed,
      fetchedAt: now
    };
    PortalService.newsPreviewCache = preview;
    return preview;
  }

  static async loadNews(channelId: string, page: number,
    force: boolean = false): Promise<PortalNewsPage> {
    const key: string = `${channelId}:${page}`;
    const cached: PortalNewsPage | undefined = PortalService.newsPages.get(key);
    if (!force && cached !== undefined && Date.now() - cached.fetchedAt < NEWS_TTL_MS) {
      return cached;
    }
    const result: PortalNewsPage = await PortalClient.fetchNews(channelId, page);
    const tasks: Promise<void>[] = [];
    for (const item of result.items) {
      tasks.push(PortalService.enrichImage(item));
    }
    await Promise.all(tasks);
    PortalService.newsPages.set(key, result);
    return result;
  }
}
