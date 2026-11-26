import { http } from '@kit.NetworkKit';
import { CasLoginService } from '../jxfw/CasLoginService';
import { CredentialsStore, SavedCredentials } from '../jxfw/CredentialsStore';
import { JxfwError, JxfwErrorKind } from '../jxfw/JxfwModels';
import { PortalSession } from './PortalSession';
import {
  PortalError,
  PortalErrorKind,
  PortalNewsItem,
  PortalNewsPage,
  PortalPersonalCard
} from './PortalModels';

const EHALL_BASE: string = 'https://ehall.gdut.edu.cn';
const EHALL_SERVICE: string =
  'https://ehall.gdut.edu.cn/login?portalService=https%3A%2F%2Fehall.gdut.edu.cn%2Findex.html%23%2F%23%2F';
const USER_AGENT: string = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36';
const MYDATA_WID: string = '7276243894285743';
const MYNEWS_WID: string = '7631867210332992';

interface PersonalDataRaw {
  wid?: string;
  title?: string;
  iconUrl?: string;
  mainInfo?: string;
  subInfo?: string;
  linkUrl?: string;
  needRetrieve?: number;
  accessTime?: string;
}

interface NewsItemRaw {
  title?: string;
  channelName?: string;
  pubTime?: string;
  picUrl?: string;
  url?: string;
  wid?: string;
  contents?: string;
  author?: string;
}

interface NewsDatasRaw {
  data?: NewsItemRaw[] | null;
  pageNumber?: number;
  pageSize?: number;
  totalSize?: number;
}

interface NewsConfigRaw {
  datas?: NewsDatasRaw;
}

interface PortalEnvelope {
  errcode?: string;
  errmsg?: string;
  data?: Object;
}

function text(value: string | null | undefined): string {
  return value === undefined || value === null ? '' : value.trim();
}

function mapCard(raw: PersonalDataRaw): PortalPersonalCard {
  return {
    wid: text(raw.wid),
    title: text(raw.title),
    iconUrl: text(raw.iconUrl),
    mainInfo: text(raw.mainInfo),
    subInfo: text(raw.subInfo),
    linkUrl: text(raw.linkUrl),
    needRetrieve: raw.needRetrieve === 1,
    accessTime: text(raw.accessTime)
  };
}

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(() => resolve(), ms);
  });
}

function mapNews(raw: NewsItemRaw): PortalNewsItem {
  return {
    title: text(raw.title),
    channelName: text(raw.channelName),
    pubTime: text(raw.pubTime),
    picUrl: text(raw.picUrl),
    url: text(raw.url),
    wid: text(raw.wid),
    contents: text(raw.contents),
    author: text(raw.author)
  };
}

/**
 * Native ehall client. It reuses the saved CAS account and the native CAS
 * service, then calls the portal's JSON card endpoints with WISCPSID cookies.
 */
export class PortalClient {
  private static loginRunning: Promise<void> | null = null;
  private static articleImageCache: Map<string, string> = new Map();

  static async ensureLoggedIn(force: boolean = false): Promise<void> {
    if (!force && PortalSession.isLoggedIn()) {
      return;
    }
    if (PortalClient.loginRunning !== null) {
      return PortalClient.loginRunning;
    }
    PortalClient.loginRunning = PortalClient.performLogin();
    try {
      await PortalClient.loginRunning;
    } finally {
      PortalClient.loginRunning = null;
    }
  }

  private static async performLogin(): Promise<void> {
    const saved: SavedCredentials | null = await CredentialsStore.load();
    if (saved === null) {
      throw new PortalError('请先登录统一认证，再查看校园数据', PortalErrorKind.CREDENTIALS);
    }
    try {
      const cookie: string =
        await CasLoginService.loginForService(saved.username, saved.password, EHALL_SERVICE, 'WISCPSID');
      if (cookie.length === 0) {
        throw new PortalError('统一认证成功，但未取得门户会话', PortalErrorKind.SESSION);
      }
      const portalCookie: string = PortalClient.ehallCookieHeader(cookie);
      const warmCookie: string = await PortalClient.warmPortal(portalCookie);
      PortalSession.setCookie(warmCookie);
    } catch (error) {
      PortalSession.clear();
      if (error instanceof PortalError) {
        throw error;
      }
      if (error instanceof JxfwError) {
        const kind: PortalErrorKind = error.kind === JxfwErrorKind.NETWORK
          ? PortalErrorKind.NETWORK
          : (error.kind === JxfwErrorKind.CREDENTIALS ? PortalErrorKind.CREDENTIALS
            : (error.kind === JxfwErrorKind.SESSION ? PortalErrorKind.SESSION : PortalErrorKind.PROTOCOL));
        throw new PortalError(error.message, kind);
      }
      throw new PortalError('登录融合门户失败，请稍后重试', PortalErrorKind.NETWORK);
    }
  }

  private static async postCard(
    cardWid: string,
    cardId: string,
    method: string,
    param: Record<string, Object>,
    allowRetry: boolean = true,
    extra: Record<string, Object> = {}
  ): Promise<Object> {
    await PortalClient.ensureLoggedIn();
    const body: Record<string, Object> = {};
    for (const key of Object.keys(extra)) {
      body[key] = extra[key];
    }
    body['cardId'] = cardId;
    body['cardWid'] = cardWid;
    body['method'] = method;
    body['param'] = param;
    body['n'] = `${Math.random()}`;
    const client = http.createHttp();
    try {
      const headers: Record<string, string> = {
        'User-Agent': USER_AGENT,
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Content-Type': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        'Referer': `${EHALL_BASE}/index.html`,
        'sec-ch-ua': '"Not:A-Brand";v="8", "Chromium";v="156", "Google Chrome";v="156"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"macOS"',
        'sec-fetch-site': 'same-origin',
        'sec-fetch-mode': 'cors',
        'sec-fetch-dest': 'empty',
        'Cookie': PortalSession.getCookie()
      };
      const response = await client.request(`${EHALL_BASE}/execCardMethod/${cardWid}/${cardId}`, {
        method: http.RequestMethod.POST,
        header: headers,
        connectTimeout: 15000,
        readTimeout: 25000,
        expectDataType: http.HttpDataType.STRING,
        extraData: JSON.stringify(body)
      });
      const raw: string = typeof response.result === 'string' ? response.result : '';
      if (response.responseCode < 200 || response.responseCode >= 400) {
        if (response.responseCode === 401 || response.responseCode === 403) {
          throw new PortalError('门户会话已失效，请重新登录', PortalErrorKind.SESSION);
        }
        throw new PortalError(`门户接口 HTTP ${response.responseCode}`, PortalErrorKind.NETWORK);
      }
      if (PortalClient.looksLikeLoginPage(raw)) {
        throw new PortalError('门户会话已失效，请重新登录', PortalErrorKind.SESSION);
      }
      let envelope: PortalEnvelope;
      try {
        envelope = JSON.parse(raw) as PortalEnvelope;
      } catch (error) {
        throw new PortalError('门户接口返回了无法解析的数据', PortalErrorKind.PROTOCOL);
      }
      if (envelope.errcode !== '0') {
        throw new PortalError(text(envelope.errmsg).length > 0
          ? text(envelope.errmsg) : '门户接口返回错误', PortalErrorKind.PROTOCOL);
      }
      return envelope.data === undefined || envelope.data === null ? new Object() : envelope.data;
    } catch (error) {
      if (error instanceof PortalError && error.kind === PortalErrorKind.SESSION && allowRetry) {
        PortalSession.clear();
        await PortalClient.ensureLoggedIn(true);
        return PortalClient.postCard(cardWid, cardId, method, param, false);
      }
      if (error instanceof PortalError) {
        throw error;
      }
      if (error instanceof Error) {
        throw new PortalError('无法连接融合门户，请检查网络', PortalErrorKind.NETWORK);
      }
      throw new PortalError('无法连接融合门户，请检查网络', PortalErrorKind.NETWORK);
    } finally {
      client.destroy();
    }
  }

  /**
   * Loads the portal bootstrap once. getLoginUser is what puts the CAS user
   * into the portal's personal-data context; without it card detail returns
   * `data:null` even though list/news work.
   */
  private static async warmPortal(cookie: string): Promise<string> {
    const paths: string[] = [
      '/index.html',
      '/base/getPortalConfig',
      `/getLoginUser?_t=${Date.now()}`,
      `/getLoginUserAndGuest?_t=${Date.now()}`,
      `/getPageView?_t=${Date.now()}&pageCode=&originalUrl=https%253A%252F%252Fehall.gdut.edu.cn%252Findex.html%2523%252F&lang=zh_CN`
    ];
    let current: string = cookie;
    for (const path of paths) {
      current = await PortalClient.warmRequest(path, current);
    }
    current = await PortalClient.warmMinos(current);
    return current;
  }

  private static async warmMinos(cookie: string): Promise<string> {
    const client = http.createHttp();
    try {
      const response = await client.request(`${EHALL_BASE}/minos-stata/collect/collectData`, {
        method: http.RequestMethod.POST,
        header: {
          'User-Agent': USER_AGENT,
          'Accept': 'application/json, text/plain, */*',
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': `${EHALL_BASE}/index.html`,
          'Cookie': cookie
        },
        connectTimeout: 15000,
        readTimeout: 20000,
        expectDataType: http.HttpDataType.STRING,
        extraData: '{}'
      });
      const extra: string = typeof response.cookies === 'string' ? response.cookies : '';
      return PortalClient.mergeCookies(cookie, extra);
    } catch (error) {
      return cookie;
    } finally {
      client.destroy();
    }
  }

  private static async warmRequest(path: string, cookie: string): Promise<string> {
    const client = http.createHttp();
    try {
      const response = await client.request(`${EHALL_BASE}${path}`, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': USER_AGENT,
          'Accept': 'application/json, text/plain, */*',
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': `${EHALL_BASE}/index.html`,
          'Cookie': cookie
        },
        connectTimeout: 15000,
        readTimeout: 20000,
        expectDataType: http.HttpDataType.STRING
      });
      const extra: string = typeof response.cookies === 'string' ? response.cookies : '';
      return PortalClient.mergeCookies(cookie, extra);
    } catch (error) {
      return cookie;
    } finally {
      client.destroy();
    }
  }

  private static mergeCookies(base: string, raw: string): string {
    const names: string[] = [];
    const values: string[] = [];
    const set = (name: string, value: string): void => {
      if (name.length === 0) {
        return;
      }
      const index: number = names.indexOf(name);
      if (index >= 0) {
        values[index] = value;
      } else {
        names.push(name);
        values.push(value);
      }
    };
    for (const part of base.split(';')) {
      const trimmed: string = part.trim();
      const equals: number = trimmed.indexOf('=');
      if (equals > 0) {
        set(trimmed.substring(0, equals).trim(), trimmed.substring(equals + 1).trim());
      }
    }
    if (raw.length > 0) {
      if (raw.includes('\t')) {
        for (const line of raw.split(/\r?\n/)) {
          const columns: string[] = line.trim().split('\t');
          if (columns.length >= 7) {
            set(columns[5].trim(), columns.slice(6).join('\t').trim());
          }
        }
      } else {
        for (const part of raw.split(/\r?\n|,(?=\s*[^;=\s]+=)/)) {
          const first: string = part.split(';')[0].trim();
          const equals: number = first.indexOf('=');
          if (equals > 0) {
            set(first.substring(0, equals).trim(), first.substring(equals + 1).trim());
          }
        }
      }
    }
    const result: string[] = [];
    for (let i = 0; i < names.length; i++) {
      result.push(`${names[i]}=${values[i]}`);
    }
    return result.join('; ');
  }

  /**
   * The CAS jar also contains authserver cookies. ehall must not receive the
   * authserver JSESSIONID/CASTGC, otherwise its detail endpoint resolves the
   * wrong context and returns data:null.
   */
  private static ehallCookieHeader(cookie: string): string {
    const blocked: string[] = ['JSESSIONID', 'CASTGC', 'happyVoyage', 'platformMultilingual'];
    const parts: string[] = [];
    for (const part of cookie.split(';')) {
      const trimmed: string = part.trim();
      if (trimmed.length === 0) {
        continue;
      }
      const name: string = trimmed.split('=')[0].trim();
      if (name.length > 0 && blocked.indexOf(name) < 0) {
        parts.push(trimmed);
      }
    }
    return parts.join('; ');
  }

  private static looksLikeLoginPage(raw: string): boolean {
    const value: string = raw.trimStart();
    return value.startsWith('<!DOCTYPE') || value.startsWith('<html') ||
      raw.includes('统一身份认证平台') || raw.includes('请输入学号');
  }

  /** Fetches an OAS article HTML and returns its first content image (lazy, cached). */
  static async fetchArticleImage(url: string): Promise<string> {
    if (url.length === 0) {
      return '';
    }
    const cached: string | undefined = PortalClient.articleImageCache.get(url);
    if (cached !== undefined) {
      return cached;
    }
    const client = http.createHttp();
    try {
      const response = await client.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': USER_AGENT,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9'
        },
        connectTimeout: 10000,
        readTimeout: 15000,
        expectDataType: http.HttpDataType.STRING
      });
      if (response.responseCode < 200 || response.responseCode >= 400) {
        return '';
      }
      const html: string = typeof response.result === 'string' ? response.result : '';
      const pattern: RegExp = /<img[^>]+(?:originalSrc|src)\s*=\s*["']([^"']+)["'][^>]*>/gi;
      let match: RegExpExecArray | null = pattern.exec(html);
      while (match !== null) {
        const src: string = match[1].trim();
        if (src.length > 0 && !src.startsWith('data:') &&
          !src.includes('/skin/') && !src.includes('news_logo') &&
          !src.toLowerCase().includes('icon')) {
          let absolute: string = src;
          if (src.startsWith('//')) {
            absolute = `https:${src}`;
          } else if (src.startsWith('/')) {
            absolute = `https://oas.gdut.edu.cn${src}`;
          } else if (!/^https?:\/\//.test(src)) {
            absolute = `https://oas.gdut.edu.cn/seeyon/${src}`;
          }
          PortalClient.articleImageCache.set(url, absolute);
          return absolute;
        }
        match = pattern.exec(html);
      }
      PortalClient.articleImageCache.set(url, '');
      return '';
    } catch (error) {
      return '';
    } finally {
      client.destroy();
    }
  }

  static async initializePersonalData(): Promise<void> {
    const meta: Record<string, Object> = {
      'wid': '14749e3bfe03f8ce0eedf0b126fd0c00',
      'cardId': 'CUS_CARD_MYDATA',
      'cardName': '个人事务',
      'cardDesc': '个人事务',
      'imageUrl': '/CUS_CARD_MYDATA/pc/img/display.png',
      'imageUrlMobile': '/CUS_CARD_MYDATA/base/image/display.png',
      'updateTime': '2022-10-18 03:07:38',
      'platformType': '0;1',
      'configurableFlag': 0,
      'configurableRuntimeFlag': 0,
      'cardSystemType': 1,
      'versionNumber': '1.0.0_20221018030125',
      'cardStatus': 0,
      'refPage': true,
      'cardWid': MYDATA_WID,
      'showTitle': false,
      'enabled': true
    };
    await PortalClient.postCard(MYDATA_WID, 'CUS_CARD_MYDATA', 'renderData',
      { 'lang': 'zh_CN', 'platformType': 0 }, true, meta);
    const saved: SavedCredentials | null = await CredentialsStore.load();
    if (saved !== null) {
      try {
        await PortalClient.postCard(MYDATA_WID, 'CUS_CARD_MYDATA', 'configuredData',
          { 'lang': 'zh_CN', 'userAccount': saved.username, 'platformType': 0 }, true, meta);
      } catch (error) {
        // configuredData is a best-effort portal warm-up.
      }
    }
  }

  static async fetchPersonalCards(): Promise<PortalPersonalCard[]> {
    await PortalClient.initializePersonalData();
    const data: Object = await PortalClient.postCard(
      MYDATA_WID, 'CUS_CARD_MYDATA', 'getPersonalDataList',
      { 'lang': 'zh_CN', 'platformType': 0 });
    if (!Array.isArray(data)) {
      return [];
    }
    return (data as PersonalDataRaw[]).map((item: PersonalDataRaw) => mapCard(item));
  }

  static async fetchPersonalCardDetail(wid: string): Promise<PortalPersonalCard | null> {
    if (wid.length === 0) {
      return null;
    }
    for (let attempt = 0; attempt < 3; attempt++) {
      const data: Object = await PortalClient.postCard(
        MYDATA_WID, 'CUS_CARD_MYDATA', 'getPersonalDataDetail',
        { 'wid': wid, 'extraInfo': '', 'lang': 'zh_CN', 'platformType': 0 });
      const keys: string[] = Object.keys(data as Object);
      if (!Array.isArray(data) && keys.length > 0) {
        return mapCard(data as PersonalDataRaw);
      }
      if (attempt < 2) {
        await delay(800);
      }
    }
    return null;
  }

  static async fetchNews(channelId: string, page: number): Promise<PortalNewsPage> {
    const data: Object = await PortalClient.postCard(
      MYNEWS_WID, 'CUS_CARD_MYNEWS', 'getChannelNews',
      {
        'channelIds': channelId,
        'pageNumber': page,
        'lang': 'zh_CN',
        'platformType': 0
      });
    const config: NewsConfigRaw = data as NewsConfigRaw;
    const datas: NewsDatasRaw | undefined = config.datas;
    const items: PortalNewsItem[] = [];
    if (datas !== undefined && datas.data !== undefined && datas.data !== null) {
      for (const item of datas.data) {
        const mapped: PortalNewsItem = mapNews(item);
        if (mapped.title.length > 0) {
          items.push(mapped);
        }
      }
    }
    return {
      items: items,
      total: datas !== undefined && datas.totalSize !== undefined ? datas.totalSize : items.length,
      page: datas !== undefined && datas.pageNumber !== undefined ? datas.pageNumber : page,
      pageSize: datas !== undefined && datas.pageSize !== undefined ? datas.pageSize : items.length,
      fetchedAt: Date.now()
    };
  }
}
