import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CasLoginService } from '../jxfw/CasLoginService';
import { CredentialsStore, SavedCredentials } from '../jxfw/CredentialsStore';
import {
  ClassroomBuilding,
  ClassroomOccupancy,
  ClassroomRoom,
  JwcwxError,
  JwcwxErrorKind
} from './JwcwxModels';
import { JwcwxParser } from './JwcwxParser';

const HOST: string = 'https://jwcwx.gdut.edu.cn';
const SERVICE: string = 'http://jwcwx.gdut.edu.cn/login/cas';
const USER_AGENT: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

interface CookieValue {
  name: string;
  value: string;
}

class CookieJar {
  private cookies: CookieValue[] = [];

  clear(): void {
    this.cookies = [];
  }

  setHeader(raw: string): void {
    for (const part of raw.split(';')) {
      const token: string = part.trim();
      const equals: number = token.indexOf('=');
      if (equals > 0) {
        this.put(token.substring(0, equals).trim(), token.substring(equals + 1).trim());
      }
    }
  }

  addRaw(raw: string): void {
    if (raw.length === 0) {
      return;
    }
    if (raw.includes('\t')) {
      for (const line of raw.split(/\r?\n/)) {
        const columns: string[] = line.trim().split('\t');
        if (columns.length >= 7 && columns[5].trim().length > 0) {
          this.put(columns[5].trim(), columns.slice(6).join('\t').trim());
        }
      }
      return;
    }
    for (const part of raw.split(/\r?\n|,(?=\s*[^;=\s]+=)/)) {
      const first: string = part.split(';')[0].trim();
      const equals: number = first.indexOf('=');
      if (equals > 0) {
        this.put(first.substring(0, equals).trim(), first.substring(equals + 1).trim());
      }
    }
  }

  private put(name: string, value: string): void {
    const existing: CookieValue | undefined = this.cookies.find((item: CookieValue) => item.name === name);
    if (existing === undefined) {
      this.cookies.push({ name: name, value: value });
    } else {
      existing.value = value;
    }
  }

  header(): string {
    return this.cookies.map((item: CookieValue) => `${item.name}=${item.value}`).join('; ');
  }

  has(name: string): boolean {
    return this.cookies.some((item: CookieValue) => item.name === name && item.value.length > 0);
  }
}

interface JwcwxResponse {
  code: number;
  body: string;
  location: string;
}

function headerObject(response: http.HttpResponse): Record<string, Object> {
  const raw: Object = response.header;
  if (typeof raw === 'string') {
    try {
      return JSON.parse(raw) as Record<string, Object>;
    } catch (error) {
      return {};
    }
  }
  return raw as Record<string, Object>;
}

function headerValue(response: http.HttpResponse, name: string): string {
  const headers: Record<string, Object> = headerObject(response);
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() === name.toLowerCase()) {
      const value: Object = headers[key];
      if (Array.isArray(value)) {
        return (value as Object[]).map((item: Object) => String(item)).join(', ');
      }
      return String(value);
    }
  }
  return '';
}

function headerValueFromObject(source: Object, name: string): string {
  const headers: Record<string, Object> = source as Record<string, Object>;
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() === name.toLowerCase()) {
      const value: Object = headers[key];
      if (Array.isArray(value)) {
        return (value as Object[]).map((item: Object) => String(item)).join(', ');
      }
      return String(value);
    }
  }
  return '';
}

function resolveUrl(base: string, location: string): string {
  if (location.startsWith('http://') || location.startsWith('https://')) {
    return location;
  }
  const match: RegExpExecArray | null = /^https?:\/\/[^\/]+/.exec(base);
  const origin: string = match === null ? HOST : match[0];
  return `${origin}${location.startsWith('/') ? '' : '/'}${location}`;
}

function isSessionRedirect(location: string): boolean {
  return location.includes('/login') || location.includes('authserver');
}

function htmlLooksLikeLogin(body: string): boolean {
  return body.includes('/login/openid') || body.includes('统一认证中心登录') ||
    body.includes('id="pwdEncryptSalt"');
}

export class JwcwxClient {
  private jar: CookieJar = new CookieJar();
  private loggedIn: boolean = false;

  async fetchBuildings(): Promise<ClassroomBuilding[]> {
    return await this.withSession<ClassroomBuilding[]>(async () => {
      return JwcwxParser.parseBuildings(
        await this.get(`${HOST}/free-class-room/buildingData?jwCode=`, true, false));
    });
  }

  async fetchRooms(buildingCode: string): Promise<ClassroomRoom[]> {
    return await this.withSession<ClassroomRoom[]>(async () => {
      const encoded: string = encodeURIComponent(buildingCode);
      return JwcwxParser.parseRooms(
        await this.get(`${HOST}/free-class-room/classroom/${encoded}?jwCode=`, false, false));
    });
  }

  async fetchOccupancy(buildingCode: string, date: string): Promise<ClassroomOccupancy[]> {
    return await this.withSession<ClassroomOccupancy[]>(async () => {
      const building: string = encodeURIComponent(buildingCode);
      const day: string = encodeURIComponent(date);
      return JwcwxParser.parseOccupancy(
        await this.get(`${HOST}/free-class-room/classroomUsedData?jwCode=&jzwdm=${building}&rq=${day}`,
          true, false));
    });
  }

  private async withSession<T>(operation: () => Promise<T>): Promise<T> {
    await this.ensureLogin();
    try {
      return await operation();
    } catch (error) {
      if (!(error instanceof JwcwxError) || error.kind !== JwcwxErrorKind.SESSION) {
        const failure: JwcwxError = error as JwcwxError;
        throw failure;
      }
      this.loggedIn = false;
      await this.ensureLogin();
      return await operation();
    }
  }

  private async ensureLogin(): Promise<void> {
    if (this.loggedIn && this.jar.has('JSESSIONID')) {
      return;
    }
    const saved: SavedCredentials | null = await CredentialsStore.load();
    if (saved === null) {
      throw new JwcwxError('请先在教务同步中登录，再查询空教室', JwcwxErrorKind.CREDENTIALS);
    }
    let lastError: JwcwxError | null = null;
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        await this.loginOnce(saved);
        return;
      } catch (error) {
        const failure: JwcwxError = error as JwcwxError;
        lastError = failure;
        this.loggedIn = false;
        if (!(error instanceof JwcwxError) || error.kind !== JwcwxErrorKind.NETWORK) {
          throw failure;
        }
        if (attempt < 2) {
          await new Promise<void>((resolve: () => void) => {
            setTimeout(() => resolve(), 800);
          });
        }
      }
    }
    if (lastError !== null) {
      throw lastError;
    }
    throw new JwcwxError('无法登录教室查询系统，请检查校园网/VPN', JwcwxErrorKind.NETWORK);
  }

  private async loginOnce(saved: SavedCredentials): Promise<void> {
    try {
      const cookie: string = await CasLoginService.loginForService(saved.username, saved.password, SERVICE);
      this.jar.clear();
      this.jar.setHeader(cookie);
      if (!this.jar.has('JSESSIONID')) {
        throw new JwcwxError('教室查询系统会话建立失败', JwcwxErrorKind.PROTOCOL);
      }
      this.loggedIn = true;
      // A first JSON request also verifies that the server-side CAS context is bound.
      await this.get(`${HOST}/free-class-room/buildingData?jwCode=`, true, false);
    } catch (error) {
      this.loggedIn = false;
      if (error instanceof JwcwxError) {
        throw error;
      }
      throw new JwcwxError('无法登录教室查询系统，请检查校园网/VPN', JwcwxErrorKind.NETWORK);
    }
  }

  private async get(url: string, xhr: boolean, allowSessionRedirect: boolean): Promise<string> {
    let current: string = url;
    for (let i = 0; i < 6; i++) {
      const response: JwcwxResponse = await this.request(current, xhr);
      if (response.code >= 300 && response.code < 400 && response.location.length > 0) {
        const next: string = resolveUrl(current, response.location);
        if (isSessionRedirect(response.location) && !allowSessionRedirect) {
          this.loggedIn = false;
          throw new JwcwxError('教室查询会话已失效，请重试', JwcwxErrorKind.SESSION);
        }
        if (isSessionRedirect(response.location) && allowSessionRedirect) {
          this.loggedIn = false;
          throw new JwcwxError('教室查询会话已失效，请重新登录教务', JwcwxErrorKind.SESSION);
        }
        current = next;
        continue;
      }
      if (response.code < 200 || response.code >= 300) {
        throw new JwcwxError(`教室查询系统返回 HTTP ${response.code}`, JwcwxErrorKind.NETWORK);
      }
      if (htmlLooksLikeLogin(response.body)) {
        this.loggedIn = false;
        throw new JwcwxError('教室查询会话已失效，请重新登录教务', JwcwxErrorKind.SESSION);
      }
      if (xhr && !response.body.trimStart().startsWith('{') && !response.body.trimStart().startsWith('[')) {
        this.loggedIn = false;
        throw new JwcwxError('教室查询接口返回异常，请稍后重试', JwcwxErrorKind.PROTOCOL);
      }
      return response.body;
    }
    throw new JwcwxError('教室查询跳转次数过多', JwcwxErrorKind.NETWORK);
  }

  private async request(url: string, xhr: boolean): Promise<JwcwxResponse> {
    const client: http.HttpRequest = http.createHttp();
    let redirectHeaders: Object | null = null;
    client.on('headersReceive', (headers: Object) => {
      redirectHeaders = headers;
    });
    try {
      const headers: Record<string, string> = {
        'User-Agent': USER_AGENT,
        'Accept': xhr ? 'application/json, text/javascript, */*; q=0.01' :
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Referer': `${HOST}/free-class-room`
      };
      if (xhr) {
        headers['X-Requested-With'] = 'XMLHttpRequest';
      }
      if (this.jar.header().length > 0) {
        headers['Cookie'] = this.jar.header();
      }
      const response = await client.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 15000,
        readTimeout: 25000,
        expectDataType: http.HttpDataType.STRING,
        maxRedirects: 0
      });
      const cookies: string = response.cookies.length > 0 ? response.cookies : headerValue(response, 'set-cookie');
      this.jar.addRaw(cookies);
      return {
        code: response.responseCode,
        body: typeof response.result === 'string' ? response.result : '',
        location: headerValue(response, 'location')
      };
    } catch (error) {
      if (redirectHeaders !== null) {
        const location: string = headerValueFromObject(redirectHeaders, 'location');
        if (location.length > 0) {
          this.jar.addRaw(headerValueFromObject(redirectHeaders, 'set-cookie'));
          return { code: 302, body: '', location: location };
        }
      }
      const be: BusinessError = error as BusinessError;
      if (be.code !== undefined) {
        throw new JwcwxError('无法连接教室查询系统，请检查校园网/VPN', JwcwxErrorKind.NETWORK);
      }
      throw new JwcwxError('教室查询网络异常', JwcwxErrorKind.NETWORK);
    } finally {
      client.destroy();
    }
  }
}
