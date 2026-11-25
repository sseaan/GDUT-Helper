import { http } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { TzcsParser } from './TzcsParser';
import { TzcsChallenge, TzcsError, TzcsReport } from './TzcsModels';

const HOST: string = 'http://tzcs.gdut.edu.cn';
const SCHOOL_CODE: string = '84223B2F7B9F3A91A2F9913135761855';
const LOGIN_URL: string = `${HOST}/Src/PlatForm/user/Login_m.aspx?Mode=2&SchoolCode=${SCHOOL_CODE}`;
const UA: string = 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36';

interface CookieValue {
  name: string;
  value: string;
}

class CookieJar {
  private values: CookieValue[] = [];

  add(raw: string): void {
    if (raw.length === 0) {
      return;
    }
    if (raw.includes('\t')) {
      for (const line of raw.split(/\r?\n/)) {
        const columns: string[] = line.trim().split('\t');
        if (columns.length >= 7) {
          this.put(columns[5], columns.slice(6).join('\t'));
        }
      }
      return;
    }
    for (const part of raw.split(/,(?=\s*[^;=\s]+=)/)) {
      const first: string = part.split(';')[0].trim();
      const equals: number = first.indexOf('=');
      if (equals > 0) {
        this.put(first.substring(0, equals), first.substring(equals + 1));
      }
    }
  }

  addHeader(raw: string): void {
    for (const part of raw.split(';')) {
      const token: string = part.trim();
      const equals: number = token.indexOf('=');
      if (equals > 0) {
        this.put(token.substring(0, equals).trim(), token.substring(equals + 1).trim());
      }
    }
  }

  header(): string {
    return this.values.map((item: CookieValue) => `${item.name}=${item.value}`).join('; ');
  }

  clear(): void {
    this.values = [];
  }

  private put(name: string, value: string): void {
    const existing: CookieValue | undefined = this.values.find((item: CookieValue) => item.name === name);
    if (existing === undefined) {
      this.values.push({ name: name, value: value });
    } else {
      existing.value = value;
    }
  }
}

interface TzcsResponse {
  code: number;
  text: string;
  bytes: Uint8Array;
  location: string;
}

function headerValue(source: Object, name: string): string {
  const headers: Record<string, Object> = source as Record<string, Object>;
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() === name.toLowerCase()) {
      const value: Object = headers[key];
      return Array.isArray(value)
        ? (value as Object[]).map((item: Object) => String(item)).join(', ')
        : String(value);
    }
  }
  return '';
}

function encode(text: string): Uint8Array {
  return new util.TextEncoder().encodeInto(text);
}

function base64(bytes: Uint8Array): string {
  return new util.Base64Helper().encodeToStringSync(bytes);
}

export class TzcsClient {
  private jar: CookieJar = new CookieJar();
  private client: http.HttpRequest = http.createHttp();
  private autoCookie: boolean = false;
  private form: Record<string, string> = {};
  private action: string = LOGIN_URL;

  private resetClient(): void {
    try {
      this.client.destroy();
    } catch (error) {
      // ignore
    }
    this.client = http.createHttp();
    this.autoCookie = false;
    try {
      this.client.enableAutoCookie(true);
      this.autoCookie = true;
    } catch (error) {
      this.autoCookie = false;
    }
  }

  async startChallenge(): Promise<TzcsChallenge> {
    this.jar.clear();
    this.resetClient();
    const page: TzcsResponse = await this.request('GET', LOGIN_URL, '', '');
    const form = TzcsParser.loginForm(page.text);
    if (form === null) {
      throw new TzcsError('体测登录页解析失败，请确认在校园网/VPN 环境', 'PROTOCOL');
    }
    this.form = form.hidden;
    this.action = form.action.length > 0 ? this.resolve(LOGIN_URL, form.action).replace('/./', '/') : LOGIN_URL;
    const captcha: TzcsResponse = await this.request('GET',
      `${HOST}/Src/PlatForm/GetCheckCode.aspx?t=${Date.now()}`, '', LOGIN_URL, true);
    if (captcha.bytes.length === 0) {
      throw new TzcsError('无法获取体测验证码', 'PROTOCOL');
    }
    return { captchaBase64: base64(captcha.bytes) };
  }

  setCookieHeader(cookie: string): void {
    this.jar.clear();
    this.jar.addHeader(cookie);
  }

  hasChallenge(): boolean {
    return Object.keys(this.form).length > 0;
  }

  async login(username: string, password: string, captcha: string): Promise<void> {
    if (!this.hasChallenge()) {
      throw new TzcsError('验证码已失效，请刷新验证码后重试', 'CAPTCHA');
    }
    const schoolNo: string = this.form['hidSchoolNo'] ?? '';
    const schoolCode: string = this.form['hidCode'] ?? '';
    const encrypted: string = await this.encrypt(password, schoolNo, schoolCode);
    const fields: Record<string, string> = {};
    for (const key of Object.keys(this.form)) {
      fields[key] = this.form[key];
    }
    fields['hidRole'] = '2';
    fields['drpRole'] = '2';
    fields['username'] = username.trim();
    fields['password'] = encrypted;
    fields['vercode'] = captcha.trim();
    fields['BtnSubmit'] = '登 入';
    const body: string = Object.keys(fields).map((key: string) =>
      `${encodeURIComponent(key)}=${encodeURIComponent(fields[key]).replace(/%20/g, '+')}`).join('&');
    const response: TzcsResponse = await this.request('POST', this.action, body,
      'application/x-www-form-urlencoded; charset=UTF-8');
    const di: number = response.text.indexOf('divMessage1');
    if (di >= 0) {
    }
    const ver: number = response.text.indexOf('验证码');
    if (ver >= 0) {
    }
    const error: string = TzcsParser.loginError(response.text);
    if (error.length > 0) {
      throw new TzcsError(error, error.includes('验证码') ? 'CAPTCHA'
        : (error.includes('密码') || error.includes('学号') ? 'CREDENTIALS' : 'OTHER'));
    }
    if (TzcsParser.isLogin(response.text)) {
      throw new TzcsError('验证码错误或已过期，请刷新后重新输入', 'CAPTCHA');
    }
    const redirect: string = TzcsParser.redirectTarget(response.text);
    if (redirect.length > 0) {
      await this.request('GET', this.resolve(this.action, redirect), '', LOGIN_URL);
    }
  }

  async fetchReports(): Promise<TzcsReport[]> {
    const currentUrl: string = `${HOST}/Src/PlatForm/Personal/PHTest_StudentScore.aspx`;
    const current: TzcsResponse = await this.request('GET', currentUrl, '', LOGIN_URL);
    if (TzcsParser.isLogin(current.text) || current.location.includes('Login')) {
      throw new TzcsError('体测登录已过期，请重新验证', 'SESSION');
    }
    const first: TzcsReport | null = TzcsParser.parseReport(current.text);
    if (first === null) {
      throw new TzcsError('体测成绩页解析失败，页面可能已改版', 'PROTOCOL');
    }
    const reports: TzcsReport[] = [first];
    const visited: number[] = [first.year];
    const queue: number[] = first.historyYears.slice();
    while (queue.length > 0 && reports.length < 8) {
      const year: number = queue.shift() as number;
      if (visited.indexOf(year) >= 0) {
        continue;
      }
      visited.push(year);
      const response: TzcsResponse = await this.request('GET',
        `${HOST}/Src/PlatForm/Personal/PHTest_StudentScore_H.aspx?DataYear=${year}`, '', currentUrl);
      if (TzcsParser.isLogin(response.text)) {
        throw new TzcsError('体测登录已过期，请重新验证', 'SESSION');
      }
      const report: TzcsReport | null = TzcsParser.parseReport(response.text, year);
      if (report !== null) {
        reports.push(report);
        for (const next of report.historyYears) {
          if (visited.indexOf(next) < 0) {
            queue.push(next);
          }
        }
      }
    }
    reports.sort((a: TzcsReport, b: TzcsReport) => b.year - a.year);
    return reports;
  }

  reset(): void {
    this.jar.clear();
    this.form = {};
  }

  private resolve(base: string, location: string): string {
    if (location.startsWith('http://') || location.startsWith('https://')) {
      return location;
    }
    const schemeEnd: number = base.indexOf('://');
    const hostStart: number = schemeEnd + 3;
    const pathStart: number = base.indexOf('/', hostStart);
    const origin: string = pathStart < 0 ? base : base.substring(0, pathStart);
    const baseDir: string = base.substring(0, base.lastIndexOf('/') + 1);
    return location.startsWith('/') ? `${origin}${location}` : `${baseDir}${location}`;
  }

  private async request(method: string, url: string, body: string,
    referer: string, bytes: boolean = false): Promise<TzcsResponse> {
    const client: http.HttpRequest = this.client;
    let redirectHeaders: Object | null = null;
    client.on('headersReceive', (headers: Object) => {
      redirectHeaders = headers;
    });
    try {
      const headers: Record<string, string> = {
        'User-Agent': UA,
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      };
      if (referer.length > 0) {
        headers['Referer'] = referer;
      }
      if (!this.autoCookie && this.jar.header().length > 0) {
        headers['Cookie'] = this.jar.header();
      }
      if (body.length > 0) {
        headers['Content-Type'] = 'application/x-www-form-urlencoded';
      }
      const response = await client.request(url, {
        method: method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: headers,
        connectTimeout: 15000,
        readTimeout: 25000,
        expectDataType: bytes ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING,
        maxRedirects: 0,
        extraData: body.length > 0 ? body : undefined
      });
      const cookies: string = response.cookies.length > 0 ? response.cookies : headerValue(response.header, 'set-cookie');
      this.jar.add(cookies);
      let text: string = '';
      let data: Uint8Array = new Uint8Array(0);
      if (bytes && response.result instanceof ArrayBuffer) {
        data = new Uint8Array(response.result as ArrayBuffer);
      } else if (typeof response.result === 'string') {
        text = response.result;
      }
      return { code: response.responseCode, text: text, bytes: data,
        location: headerValue(response.header, 'location') };
    } catch (error) {
      if (redirectHeaders !== null) {
        const location: string = headerValue(redirectHeaders, 'location');
        if (location.length > 0) {
          this.jar.add(headerValue(redirectHeaders, 'set-cookie'));
          return { code: 302, text: '', bytes: new Uint8Array(0), location: location };
        }
      }
      throw new TzcsError('无法连接体测平台，请确认在校园网/VPN 环境', 'NETWORK');
    } finally {
      // The client is shared so automatic cookies survive across requests.
    }
  }

  private async encrypt(password: string, schoolNo: string, schoolCode: string): Promise<string> {
    const md = cryptoFramework.createMd('SHA256');
    await md.update({ data: encode(schoolNo) });
    const digest: cryptoFramework.DataBlob = await md.digest();
    const keyBytes: Uint8Array = digest.data.slice(0, 16);
    const iv: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: { data: encode(schoolCode).slice(0, 16) }
    };
    const key = await cryptoFramework.createSymKeyGenerator('AES128').convertKey({ data: keyBytes });
    const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, iv);
    const out: cryptoFramework.DataBlob = await cipher.doFinal({ data: encode(password) });
    return base64(out.data);
  }
}
