import { http } from '@kit.NetworkKit';
import { CasLoginService } from '../jxfw/CasLoginService';
import { CredentialsStore, SavedCredentials } from '../jxfw/CredentialsStore';
import { JxfwError, JxfwErrorKind } from '../jxfw/JxfwModels';
import { LibrarySession } from './LibrarySession';
import {
  LibraryError,
  LibraryErrorKind,
  LibraryLoan,
  LibraryOverview,
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

/** Native client for the OPAC (图书馆) system, using the shared unified CAS account. */
export class LibraryClient {
  private static loginRunning: Promise<void> | null = null;

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
}
