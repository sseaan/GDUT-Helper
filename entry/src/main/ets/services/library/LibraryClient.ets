import { http } from '@kit.NetworkKit';
import { Identifiers } from '../../common/Identifiers';
import { CasLoginService } from '../jxfw/CasLoginService';
import { CredentialsStore, SavedCredentials } from '../jxfw/CredentialsStore';
import { JxfwError, JxfwErrorKind } from '../jxfw/JxfwModels';
import { LibrarySession } from './LibrarySession';
import {
  LibraryBook,
  LibraryError,
  LibraryErrorKind,
  LibraryHolding,
  LibraryLoan,
  LibraryOverview,
  LibrarySearchField,
  LibrarySearchQuery,
  LibrarySearchResult,
  LibraryUser
} from './LibraryModels';

const OPAC_BASE: string = 'https://opac.gdut.edu.cn';
const OPAC_SERVICE: string = 'https://opac.gdut.edu.cn/sso-cas/cas/index/gdut';
const OPAC_INIT: string =
  'https://opac.gdut.edu.cn/sso-cas/cas/gdut/init?refer=https%3A%2F%2Fopac.gdut.edu.cn%2Ffind%2Fsso%2Flogin%2Fgdut%2F0%3FpageType%3D0%26navigation%3D1';
const GROUP_CODE: string = '800555';
const USER_AGENT: string =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36';

interface LibraryEnvelope {
  success?: boolean;
  message?: string;
  errCode?: number;
  data?: Object;
}

interface LoanRaw {
  title?: string;
  bookName?: string;
  bookTitle?: string;
  name?: string;
  author?: string;
  authorName?: string;
  zz?: string;
  barcode?: string;
  barCode?: string;
  bookBarcode?: string;
  location?: string;
  libName?: string;
  libraryName?: string;
  collectionPlace?: string;
  loanDate?: string;
  borrowDate?: string;
  startDate?: string;
  dueDate?: string;
  shouldReturnDate?: string;
  endDate?: string;
  returnDate?: string;
  renewCount?: number;
  renewTimes?: number;
  csm?: number;
  status?: string;
  statusName?: string;
  id?: string;
  recordId?: string;
}

interface LoanListData {
  searchResult?: LoanRaw[];
  loanNum?: number;
  numFound?: number;
}

interface UserRaw {
  name?: string;
  unit?: string;
  department?: string;
  userId?: string;
}

interface SearchData {
  numFound?: number;
  searchResult?: Record<string, Object>[];
}

const SEARCH_ROWS: number = 20;
const SEARCH_CACHE_TTL: number = 5 * 60 * 1000;
const SEARCH_CACHE_MAX: number = 8;

interface SearchCacheEntry {
  key: string;
  result: LibrarySearchResult;
  at: number;
}

function text(value: string | number | undefined | null): string {
  if (value === undefined || value === null) {
    return '';
  }
  return `${value}`.trim();
}

function first(raw: LoanRaw, keys: string[]): string {
  for (const key of keys) {
    const value: string = text((raw as Record<string, Object>)[key] as string);
    if (value.length > 0) {
      return value;
    }
  }
  return '';
}

function numberOf(raw: LoanRaw, keys: string[]): number {
  for (const key of keys) {
    const value: string = text((raw as Record<string, Object>)[key] as string);
    if (value.length > 0) {
      const parsed: number = Number.parseInt(value, 10);
      if (!Number.isNaN(parsed)) {
        return parsed;
      }
    }
  }
  return 0;
}

function mapLoan(raw: LoanRaw): LibraryLoan {
  return {
    id: first(raw, ['id', 'recordId', 'barcode', 'barCode']),
    title: first(raw, ['title', 'bookName', 'bookTitle', 'name']),
    author: first(raw, ['author', 'authorName', 'zz']),
    barcode: first(raw, ['barcode', 'barCode', 'bookBarcode']),
    location: first(raw, ['location', 'libName', 'libraryName', 'collectionPlace']),
    loanDate: first(raw, ['loanDate', 'borrowDate', 'startDate']),
    dueDate: first(raw, ['dueDate', 'shouldReturnDate', 'endDate']),
    returnDate: first(raw, ['returnDate']),
    renewCount: numberOf(raw, ['renewCount', 'renewTimes', 'csm']),
    status: first(raw, ['status', 'statusName']),
    raw: JSON.stringify(raw)
  };
}

function field(record: Record<string, Object>, key: string): string {
  return text(record[key] as string);
}

function countOf(value: string): number {
  if (value.length === 0) {
    return 0;
  }
  const parsed: number = Number.parseInt(value, 10);
  return Number.isNaN(parsed) ? 0 : parsed;
}

function mapBook(raw: Record<string, Object>): LibraryBook {
  return {
    recordId: field(raw, 'recordId'),
    title: field(raw, 'title'),
    author: field(raw, 'author'),
    publisher: field(raw, 'publisher'),
    isbn: field(raw, 'isbn'),
    publishYear: field(raw, 'publishYear'),
    callNo: field(raw, 'callNoOne'),
    price: field(raw, 'price'),
    pageCount: field(raw, 'bookPage'),
    subject: field(raw, 'subjectWord'),
    physicalCount: countOf(field(raw, 'physicalCount')),
    onShelfCount: countOf(field(raw, 'onShelfCountI')),
    abstractText: field(raw, 'adstract')
  };
}

function mapHolding(raw: Record<string, Object>): LibraryHolding {
  const location: string = field(raw, 'curLocationName');
  return {
    itemId: field(raw, 'itemId'),
    callNo: field(raw, 'callNo'),
    barcode: field(raw, 'barcode'),
    location: location.length > 0 ? location : field(raw, 'locationName'),
    status: field(raw, 'processType'),
    policy: field(raw, 'itemPolicyName'),
    inDate: field(raw, 'inDate'),
    vol: field(raw, 'vol'),
    year: field(raw, 'year')
  };
}

/** Native client for the OPAC (图书馆) system, using the shared unified CAS account. */
export class LibraryClient {
  private static loginRunning: Promise<void> | null = null;
  private static searchCache: SearchCacheEntry[] = [];

  static async ensureLoggedIn(force: boolean = false): Promise<void> {
    if (!force && LibrarySession.isLoggedIn()) {
      return;
    }
    if (LibraryClient.loginRunning !== null) {
      return LibraryClient.loginRunning;
    }
    LibraryClient.loginRunning = LibraryClient.performLogin();
    try {
      await LibraryClient.loginRunning;
    } finally {
      LibraryClient.loginRunning = null;
    }
  }

  private static async performLogin(): Promise<void> {
    const saved: SavedCredentials | null = await CredentialsStore.load();
    if (saved === null) {
      throw new LibraryError('请先登录统一认证，再查看图书馆', LibraryErrorKind.CREDENTIALS);
    }
    try {
      const cookie: string = await CasLoginService.loginForService(
        saved.username, saved.password, OPAC_SERVICE, 'jwt', OPAC_INIT);
      if (cookie.indexOf('jwt=') < 0) {
        throw new LibraryError('统一认证成功，但未取得图书馆会话', LibraryErrorKind.SESSION);
      }
      LibrarySession.setCookie(cookie);
    } catch (error) {
      LibrarySession.clear();
      if (error instanceof LibraryError) {
        throw error;
      }
      if (error instanceof JxfwError) {
        const kind: LibraryErrorKind = error.kind === JxfwErrorKind.NETWORK
          ? LibraryErrorKind.NETWORK
          : (error.kind === JxfwErrorKind.CREDENTIALS ? LibraryErrorKind.CREDENTIALS
            : (error.kind === JxfwErrorKind.SESSION ? LibraryErrorKind.SESSION : LibraryErrorKind.PROTOCOL));
        throw new LibraryError(error.message, kind);
      }
      throw new LibraryError('登录图书馆失败，请稍后重试', LibraryErrorKind.NETWORK);
    }
  }

  private static headers(): Record<string, string> {
    const result: Record<string, string> = {
      'User-Agent': USER_AGENT,
      'Accept': 'application/json, text/plain, */*',
      'Content-Type': 'application/json;charset=UTF-8',
      'groupCode': GROUP_CODE,
      'mappingPath': '',
      'x-lang': 'CHI',
      'content-language': 'zh_CN',
      'Cookie': LibrarySession.getCookie()
    };
    result[LibrarySession.headerName()] = LibrarySession.token();
    return result;
  }

  private static async request(
    method: http.RequestMethod,
    path: string,
    body: string = '',
    allowRetry: boolean = true
  ): Promise<Object> {
    await LibraryClient.ensureLoggedIn();
    const client = http.createHttp();
    try {
      const response = await client.request(`${OPAC_BASE}${path}`, {
        method: method,
        header: LibraryClient.headers(),
        connectTimeout: 15000,
        readTimeout: 25000,
        expectDataType: http.HttpDataType.STRING,
        extraData: body.length > 0 ? body : undefined
      });
      const raw: string = typeof response.result === 'string' ? response.result : '';
      if (response.responseCode < 200 || response.responseCode >= 400) {
        throw new LibraryError(`图书馆接口 HTTP ${response.responseCode}`, LibraryErrorKind.NETWORK);
      }
      let envelope: LibraryEnvelope;
      try {
        envelope = JSON.parse(raw) as LibraryEnvelope;
      } catch (error) {
        if (raw.trimStart().startsWith('<')) {
          throw new LibraryError('图书馆会话已失效，请重新登录', LibraryErrorKind.SESSION);
        }
        throw new LibraryError('图书馆接口返回了无法解析的数据', LibraryErrorKind.PROTOCOL);
      }
      if (envelope.errCode === 401 || envelope.success === false &&
        (envelope.message ?? '').includes('登录')) {
        throw new LibraryError('图书馆会话已失效，请重新登录', LibraryErrorKind.SESSION);
      }
      if (envelope.success === false) {
        throw new LibraryError(envelope.message ?? '图书馆接口返回错误', LibraryErrorKind.PROTOCOL);
      }
      return envelope.data === undefined || envelope.data === null ? new Object() : envelope.data;
    } catch (error) {
      if (error instanceof LibraryError && error.kind === LibraryErrorKind.SESSION && allowRetry) {
        LibrarySession.clear();
        await LibraryClient.ensureLoggedIn(true);
        return LibraryClient.request(method, path, body, false);
      }
      if (error instanceof LibraryError) {
        throw error;
      }
      throw new LibraryError('无法连接图书馆系统，请检查网络', LibraryErrorKind.NETWORK);
    } finally {
      client.destroy();
    }
  }

  static async fetchUser(): Promise<LibraryUser> {
    const data: Object = await LibraryClient.request(http.RequestMethod.GET, '/oga/userinfo');
    const raw: UserRaw = data as UserRaw;
    return {
      name: text(raw.name),
      unit: text(raw.unit),
      department: text(raw.department),
      userId: text(raw.userId)
    };
  }

  static async fetchOverview(): Promise<LibraryOverview> {
    const user: LibraryUser = await LibraryClient.fetchUser();
    const body: string = JSON.stringify({
      page: 1,
      rows: 50,
      searchType: 1,
      searchContent: '',
      sortType: 0,
      startDate: null,
      endDate: null
    });
    const data: Object = await LibraryClient.request(
      http.RequestMethod.POST, '/find/loanInfo/loanList', body);
    const list: LoanListData = data as LoanListData;
    const loans: LibraryLoan[] = [];
    if (list.searchResult !== undefined) {
      for (const raw of list.searchResult) {
        loans.push(mapLoan(raw));
      }
    }
    return {
      user: user,
      loans: loans,
      loanQuota: list.loanNum === undefined ? 0 : list.loanNum,
      total: list.numFound === undefined ? loans.length : list.numFound,
      fetchedAt: Date.now()
    };
  }

  /**
   * 书目检索。OPAC 的公开目录接口不要求登录态，所以这里走匿名通路：
   * 没登录过统一认证也能查馆藏，扫码查书不会先撞上登录墙。
   *
   * `field = ALL` 且关键字是合法 ISBN 时自动改为 ISBN 检索。
   */
  static async searchBooks(query: LibrarySearchQuery, page: number = 1): Promise<LibrarySearchResult> {
    const keyword: string = query.keyword.trim();
    if (keyword.length === 0) {
      return { total: 0, books: [], page: page, rows: SEARCH_ROWS };
    }
    const isbn: string = Identifiers.isbnOf(keyword);
    const asIsbn: boolean = query.field === LibrarySearchField.ALL && isbn.length > 0;
    const field: string = asIsbn ? LibrarySearchField.ISBN : query.field;
    const content: string = asIsbn ? isbn : keyword;
    const key: string = `${field}|${query.sort}|${content}|${page}`;

    const cached: LibrarySearchResult | null = LibraryClient.cachedSearch(key);
    if (cached !== null) {
      return cached;
    }
    const data: Object = await LibraryClient.publicRequest(
      http.RequestMethod.POST, '/find/unify/search',
      LibraryClient.searchBody(content, field, query.sort, page));
    const list: SearchData = data as SearchData;
    const books: LibraryBook[] = [];
    if (list.searchResult !== undefined && Array.isArray(list.searchResult)) {
      for (const raw of list.searchResult) {
        books.push(mapBook(raw));
      }
    }
    const result: LibrarySearchResult = {
      total: list.numFound === undefined ? books.length : list.numFound,
      books: books,
      page: page,
      rows: SEARCH_ROWS
    };
    LibraryClient.rememberSearch(key, result);
    return result;
  }

  private static cachedSearch(key: string): LibrarySearchResult | null {
    const now: number = Date.now();
    for (const entry of LibraryClient.searchCache) {
      if (entry.key === key && now - entry.at < SEARCH_CACHE_TTL) {
        return entry.result;
      }
    }
    return null;
  }

  private static rememberSearch(key: string, result: LibrarySearchResult): void {
    const kept: SearchCacheEntry[] = [];
    for (const entry of LibraryClient.searchCache) {
      if (entry.key !== key) {
        kept.push(entry);
      }
    }
    kept.unshift({ key: key, result: result, at: Date.now() });
    while (kept.length > SEARCH_CACHE_MAX) {
      kept.pop();
    }
    LibraryClient.searchCache = kept;
  }

  static clearSearchCache(): void {
    LibraryClient.searchCache = [];
  }

  /** 单本图书的册信息；公开接口，同样不需要登录。 */
  static async fetchHoldings(recordId: string): Promise<LibraryHolding[]> {
    if (recordId.length === 0) {
      return [];
    }
    const data: Object = await LibraryClient.publicRequest(
      http.RequestMethod.POST, '/find/physical/groupitems',
      JSON.stringify({ 'recordId': recordId, 'page': 1, 'rows': 50 }));
    const holdings: LibraryHolding[] = [];
    if (Array.isArray(data)) {
      for (const raw of data as Record<string, Object>[]) {
        holdings.push(mapHolding(raw));
      }
    }
    return holdings;
  }

  /**
   * 检索请求体。字段集合就是 OPAC 前端实际下发的形态：缺字段时服务端直接回
   * `系统访问中断`，而 `docCode` 必须是 `[null]`（`["2"]` 会返回 0 条）。
   */
  private static searchBody(content: string, field: string, sort: string, page: number): string {
    const none: (string | null)[] = [];
    const body: Record<string, Object | null> = {
      'docCode': [null] as (string | null)[],
      'litCode': none,
      'searchField': field,
      'searchFieldContent': content,
      'matchMode': '2',
      'resourceType': none,
      'subject': none,
      'discode1': none,
      'publisher': none,
      'libCode': none,
      'locationId': none,
      'eCollectionIds': none,
      'neweCollectionIds': none,
      'curLocationId': none,
      'campusId': none,
      'kindNo': none,
      'collectionName': none,
      'author': none,
      'langCode': none,
      'countryCode': none,
      'publishBegin': null,
      'publishEnd': null,
      'coreInclude': none,
      'ddType': none,
      'verifyStatus': none,
      'group': none,
      'sortField': sort,
      'sortClause': 'asc',
      'page': page,
      'rows': SEARCH_ROWS,
      'onlyOnShelf': null,
      'searchItems': null,
      'newCoreInclude': none,
      'customSub': none,
      'customSub0': none,
      'indexSearch': 1
    };
    return JSON.stringify(body);
  }

  /** 公开目录请求：不登录、不携带 jwt，也不在 401 时尝试重登。 */
  private static async publicRequest(
    method: http.RequestMethod,
    path: string,
    body: string = ''
  ): Promise<Object> {
    const client = http.createHttp();
    try {
      const response = await client.request(`${OPAC_BASE}${path}`, {
        method: method,
        header: {
          'User-Agent': USER_AGENT,
          'Accept': 'application/json, text/plain, */*',
          'Content-Type': 'application/json;charset=UTF-8',
          'groupCode': GROUP_CODE,
          'mappingPath': '',
          'x-lang': 'CHI',
          'content-language': 'zh_CN',
          'Origin': OPAC_BASE,
          'Referer': `${OPAC_BASE}/`
        },
        connectTimeout: 15000,
        readTimeout: 25000,
        expectDataType: http.HttpDataType.STRING,
        extraData: body.length > 0 ? body : undefined
      });
      const raw: string = typeof response.result === 'string' ? response.result : '';
      if (response.responseCode < 200 || response.responseCode >= 400) {
        throw new LibraryError(`图书馆接口 HTTP ${response.responseCode}`, LibraryErrorKind.NETWORK);
      }
      let envelope: LibraryEnvelope;
      try {
        envelope = JSON.parse(raw) as LibraryEnvelope;
      } catch (error) {
        throw new LibraryError('图书馆接口返回了无法解析的数据', LibraryErrorKind.PROTOCOL);
      }
      if (envelope.success === false) {
        throw new LibraryError(envelope.message ?? '图书馆接口返回错误', LibraryErrorKind.PROTOCOL);
      }
      return envelope.data === undefined || envelope.data === null ? new Object() : envelope.data;
    } catch (error) {
      if (error instanceof LibraryError) {
        throw error;
      }
      throw new LibraryError('无法连接图书馆系统，请检查网络', LibraryErrorKind.NETWORK);
    } finally {
      client.destroy();
    }
  }
}
