import { http } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { JxfwError, JxfwErrorKind } from './JxfwModels';
import { JxfwSession } from './JxfwSession';
import { CredentialsStore, SavedCredentials } from './CredentialsStore';

const AUTH_BASE: string = 'https://authserver.gdut.edu.cn';
const JXFW_BASE: string = 'https://jxfw.gdut.edu.cn';
const SERVICE: string = `${JXFW_BASE}/new/ssoLogin`;
const LOGIN_URL: string = `${AUTH_BASE}/authserver/login?service=${encodeURIComponent(SERVICE)}`;
const USER_AGENT: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';
const RANDOM_CHARS: string = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

interface CasLoginPage {
  salt: string;
  execution: string;
}

interface CookieValue {
  name: string;
  value: string;
}

class CookieJar {
  private cookies: CookieValue[] = [];

  addRaw(raw: string): void {
    if (raw.length === 0) {
      return;
    }
    // @ohos.net.http returns cookies in Netscape cookie-file format:
    // domain<TAB>flag<TAB>path<TAB>secure<TAB>expiry<TAB>name<TAB>value
    if (raw.includes('\t')) {
      for (const line of raw.split(/\r?\n/)) {
        const trimmed: string = line.trim();
        if (trimmed.length === 0) {
          continue;
        }
        const columns: string[] = trimmed.split('\t');
        if (columns.length < 7) {
          continue;
        }
        const name: string = columns[5].trim();
        const value: string = columns.slice(6).join('\t').trim();
        if (name.length > 0) {
          this.put(name, value);
        }
      }
      return;
    }
    const parts: string[] = raw.split(/\r?\n|,(?=\s*[^;=\s]+=)/);
    for (const part of parts) {
      const first: string = part.split(';')[0].trim();
      const equals: number = first.indexOf('=');
      if (equals <= 0) {
        continue;
      }
      const name: string = first.substring(0, equals).trim();
      const value: string = first.substring(equals + 1).trim();
      this.put(name, value);
    }
  }

  private put(name: string, value: string): void {
    const existing: CookieValue | undefined = this.cookies.find((item) => item.name === name);
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

function encode(value: string): Uint8Array {
  return new util.TextEncoder().encodeInto(value);
}

function randomString(length: number): string {
  let result: string = '';
  for (let i = 0; i < length; i++) {
    result += RANDOM_CHARS.charAt(Math.floor(Math.random() * RANDOM_CHARS.length));
  }
  return result;
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

function parseLoginPage(html: string): CasLoginPage {
  const saltMatch: RegExpExecArray | null = /id="pwdEncryptSalt"\s+value="([^"]*)"/.exec(html);
  const executionMatch: RegExpExecArray | null = /name="execution"\s+value="([^"]*)"/.exec(html);
  if (saltMatch === null || executionMatch === null) {
    throw new JxfwError('统一认证页面结构已变化，请稍后重试', JxfwErrorKind.PROTOCOL);
  }
  return { salt: saltMatch[1], execution: executionMatch[1] };
}

function loginErrorMessage(html: string): JxfwError {
  const errorMatch: RegExpExecArray | null =
    /id="showErrorTip"[^>]*>([\s\S]*?)<\/span>/.exec(html);
  const message: string = errorMatch === null ? '' : errorMatch[1].replace(/<[^>]+>/g, '').trim();
  if (message.includes('验证码') || message.includes('captcha')) {
    return new JxfwError('教务登录需要验证码，请稍后重试', JxfwErrorKind.CAPTCHA);
  }
  if (message.includes('短信')) {
    return new JxfwError('教务登录需要短信验证，请稍后重试', JxfwErrorKind.SMS);
  }
  if (message.includes('密码') || message.includes('账号') || message.includes('用户名')) {
    return new JxfwError(message.length > 0 ? message : '学号或密码错误', JxfwErrorKind.CREDENTIALS);
  }
  if (message.length > 0) {
    return new JxfwError(message, JxfwErrorKind.PROTOCOL);
  }
  return new JxfwError('统一认证登录失败，请检查账号或稍后重试', JxfwErrorKind.PROTOCOL);
}

/** Native CAS login (encrypted password form), no WebView and no password logging. */
export class CasLoginService {
  private static lastAutoLoginAt: number = 0;
  private static autoLoginRunning: Promise<boolean> | null = null;

  static async login(username: string, password: string): Promise<void> {
    const cookie: string = await CasLoginService.loginForService(username, password, SERVICE);
    JxfwSession.setCookie(cookie, username.trim());
  }

  /** Native CAS login for an arbitrary CAS service; returns the resulting Cookie header. */
  static async loginForService(username: string, password: string, serviceUrl: string): Promise<string> {
    if (username.trim().length === 0 || password.length === 0) {
      throw new JxfwError('请输入学号和密码', JxfwErrorKind.CREDENTIALS);
    }
    const loginUrl: string = `${AUTH_BASE}/authserver/login?service=${encodeURIComponent(serviceUrl)}`;
    const targetHost: string = CasLoginService.hostOf(serviceUrl);
    const jar: CookieJar = new CookieJar();
    hilog.info(0x0000, 'CAS', 'login page requested for %{public}s', targetHost);
    const loginPage = await CasLoginService.request(
      http.RequestMethod.GET, loginUrl, '', '', jar, '', false);
    hilog.info(0x0000, 'CAS', 'login page loaded code=%{public}d', loginPage.code);
    const page: CasLoginPage = parseLoginPage(loginPage.body);
    try {
      const captchaCheck = await CasLoginService.request(
        http.RequestMethod.GET,
        `${AUTH_BASE}/authserver/checkNeedCaptcha.htl?username=${encodeURIComponent(username.trim())}`,
        '', loginUrl, jar, '', true);
      if (captchaCheck.body.replace(/\s/g, '').includes('"isNeed":true')) {
        throw new JxfwError('当前账号需要滑块验证码，请先在浏览器完成一次教务登录后重试',
          JxfwErrorKind.CAPTCHA);
      }
    } catch (error) {
      if (error instanceof JxfwError) {
        throw error;
      }
    }
    const encrypted: string = await CasLoginService.encryptPassword(password, page.salt);
    const form: string = CasLoginService.formBody(username.trim(), encrypted, page.execution);
    hilog.info(0x0000, 'CAS', 'posting credentials for %{public}s', targetHost);
    const post = await CasLoginService.request(
      http.RequestMethod.POST, loginUrl, form, loginUrl, jar, 'application/x-www-form-urlencoded', true);
    hilog.info(0x0000, 'CAS', 'post result code=%{public}d location=%{public}s', post.code, post.location.length > 0 ? 'yes' : 'no');
    const reachedTarget: boolean = post.body.includes('教学管理系统') ||
      post.body.includes('kbxx') || post.body.includes('login!welcome');
    if (post.code === 200 && post.location.length === 0 && reachedTarget) {
      return jar.header();
    }
    if (post.code === 200 && post.location.length === 0) {
      throw loginErrorMessage(post.body);
    }
    const ticketLocation: string = post.location;
    if (ticketLocation.length === 0) {
      throw loginErrorMessage(post.body);
    }
    return await CasLoginService.followTicket(ticketLocation, jar, targetHost);
  }

  static async autoLogin(): Promise<boolean> {
    if (JxfwSession.isLoggedIn()) {
      return true;
    }
    if (CasLoginService.autoLoginRunning !== null) {
      return CasLoginService.autoLoginRunning;
    }
    const now: number = Date.now();
    if (now - CasLoginService.lastAutoLoginAt < 8000) {
      return false;
    }
    CasLoginService.lastAutoLoginAt = now;
    CasLoginService.autoLoginRunning = CasLoginService.performAutoLogin();
    try {
      return await CasLoginService.autoLoginRunning;
    } finally {
      CasLoginService.autoLoginRunning = null;
    }
  }

  private static async performAutoLogin(): Promise<boolean> {
    const saved: SavedCredentials | null = await CredentialsStore.load();
    if (saved === null) {
      return false;
    }
    try {
      await CasLoginService.login(saved.username, saved.password);
      return true;
    } catch (error) {
      JxfwSession.clear();
      return false;
    }
  }

  private static async followTicket(location: string, jar: CookieJar, targetHost: string): Promise<string> {
    let url: string = CasLoginService.normalizeTargetUrl(location);
    for (let i = 0; i < 6; i++) {
      const response = await CasLoginService.request(
        http.RequestMethod.GET, url, '', LOGIN_URL, jar, '', true);
      if (response.code >= 300 && response.code < 400 && response.location.length > 0) {
        url = CasLoginService.normalizeTargetUrl(CasLoginService.resolveUrl(url, response.location));
        continue;
      }
      if (CasLoginService.hostOf(url) === targetHost && jar.has('JSESSIONID')) {
        return jar.header();
      }
      if (response.code === 200) {
        throw new JxfwError('统一认证已通过，但目标系统会话建立失败', JxfwErrorKind.PROTOCOL);
      }
    }
    throw new JxfwError('统一认证跳转次数过多', JxfwErrorKind.PROTOCOL);
  }

  private static normalizeTargetUrl(url: string): string {
    if (url.startsWith('http://jwcwx.gdut.edu.cn')) {
      return 'https://' + url.substring('http://'.length);
    }
    return url;
  }

  private static hostOf(url: string): string {
    const match: RegExpExecArray | null = /^https?:\/\/([^\/]+)/.exec(url);
    return match === null ? '' : match[1].toLowerCase();
  }

  private static resolveUrl(base: string, location: string): string {
    if (location.startsWith('http://') || location.startsWith('https://')) {
      return location;
    }
    const schemeEnd: number = base.indexOf('://');
    if (schemeEnd < 0) {
      return location;
    }
    const hostStart: number = schemeEnd + 3;
    const pathStart: number = base.indexOf('/', hostStart);
    const origin: string = pathStart < 0 ? base : base.substring(0, pathStart);
    return `${origin}${location.startsWith('/') ? '' : '/'}${location}`;
  }

  private static formBody(username: string, password: string, execution: string): string {
    return [
      `username=${encodeURIComponent(username)}`,
      `password=${encodeURIComponent(password)}`,
      'captcha=',
      '_eventId=submit',
      'lt=',
      'cllt=userNameLogin',
      'dllt=generalLogin',
      `execution=${encodeURIComponent(execution)}`
    ].join('&');
  }

  private static async encryptPassword(password: string, salt: string): Promise<string> {
    if (salt.length === 0) {
      throw new JxfwError('统一认证缺少加密参数', JxfwErrorKind.PROTOCOL);
    }
    return CasLoginService.encryptWith(password, salt, randomString(64), randomString(16));
  }

  private static async encryptWith(
    password: string, salt: string, prefix: string, ivText: string
  ): Promise<string> {
    const keyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
    const key = await keyGenerator.convertKey({ data: encode(salt) });
    const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
    const iv: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: { data: encode(ivText) }
    };
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, iv);
    const plain: Uint8Array = encode(prefix + password);
    const output: cryptoFramework.DataBlob = await cipher.doFinal({ data: plain });
    return new util.Base64Helper().encodeToStringSync(output.data);
  }


  private static async request(
    method: http.RequestMethod,
    url: string,
    body: string,
    referer: string,
    jar: CookieJar,
    contentType: string,
    includeCookies: boolean
  ): Promise<CasHttpResponse> {
    const client: http.HttpRequest = http.createHttp();
    let redirectHeaders: Object | null = null;
    client.on('headersReceive', (headers: Object) => {
      redirectHeaders = headers;
    });
    try {
      const headers: Record<string, string> = {
        'User-Agent': USER_AGENT,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9'
      };
      if (referer.length > 0) {
        headers['Referer'] = referer;
      }
      if (contentType.length > 0) {
        headers['Content-Type'] = contentType;
      }
      if (includeCookies) {
        headers['Cookie'] = jar.header();
      }
      const response = await client.request(url, {
        method: method,
        header: headers,
        connectTimeout: 15000,
        readTimeout: 25000,
        expectDataType: http.HttpDataType.STRING,
        maxRedirects: 0,
        extraData: body.length > 0 ? body : undefined
      });
      const cookies: string = response.cookies.length > 0
        ? response.cookies : headerValue(response, 'set-cookie');
      jar.addRaw(cookies);
      const text: string = typeof response.result === 'string' ? response.result : '';
      return {
        code: response.responseCode,
        body: text,
        location: headerValue(response, 'location')
      };
    } catch (error) {
      if (redirectHeaders !== null) {
        const location: string = headerValueFromObject(redirectHeaders, 'location');
        if (location.length > 0) {
          jar.addRaw(headerValueFromObject(redirectHeaders, 'set-cookie'));
          return { code: 302, body: '', location: location };
        }
      }
      const be: BusinessError = error as BusinessError;
      hilog.error(0x0000, 'CAS', 'request failed: code=%{public}d message=%{public}s',
        be.code === undefined ? -1 : be.code, be.message === undefined ? 'unknown' : be.message);
      if (error instanceof Error) {
        throw error;
      }
      throw new JxfwError('无法连接学校统一认证，请检查网络', JxfwErrorKind.NETWORK);
    } finally {
      client.destroy();
    }
  }
}

interface CasHttpResponse {
  code: number;
  body: string;
  location: string;
}
