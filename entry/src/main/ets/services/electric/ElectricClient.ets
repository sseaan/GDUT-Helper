import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ElectricCampus, ElectricError, ElectricErrorKind, MeterReading } from './ElectricModels';
import { ElectricParser } from './ElectricParser';

const BASE: string = 'http://bd.bdfairy.cn';
/**
 * 站点是微信 H5，服务端按 UA 识别环境。带 MicroMessenger UA 不代表要登录微信，
 * 免登录链路（connect.sid）就够查余额。
 */
const UA: string =
  'Mozilla/5.0 (Linux; Android 12; M2012K11AC Build/SKQ1.211006.001; wv) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Version/4.0 Chrome/107.0.5304.141 Mobile Safari/537.36 XWEB/5169 ' +
  'MMWEBSDK/20220903 MMWEBID/3905 MicroMessenger/8.0.28.2240(0x28001C35) WeChat/arm64 Weixin ' +
  'NetType/WIFI Language/zh_CN ABI/arm64';

const CONNECT_TIMEOUT: number = 6000;
const READ_TIMEOUT: number = 8000;
const METER_PATTERN: RegExp = /^\d{6,}$/;

interface Exchange {
  code: number;
  body: string;
}

function pick(record: Record<string, string>, key: string): string {
  const value: string = record[key];
  return value === undefined ? '' : value;
}

/**
 * 电精灵电表查询（Beta，非官方）。
 *
 * 链路与站点 H5 一致，全部走免登录会话：
 *   POST /selectarea              → 选校，同时下发 connect.sid
 *   POST /selectmeter             → 提交表号，返回 { url: '/meter_main' }
 *   GET  {url}                    → 读数页（HTML）
 *   GET  /electricbill            → 月账单（可选）
 *
 * 不要先访问 `GET /?id=`：那一步会 302 到微信 OAuth，而 `maxRedirects: 0`
 * 在部分实现上会直接抛 2300047，跟随又可能卡在微信域名。
 * 实测 `/selectarea` 自己就会 Set-Cookie，所以入口请求整段省略。
 *
 * Cookie 手写维护：`HttpRequest.enableAutoCookie()` 是 API 26 才有的能力，
 * 而本项目最低兼容 API 23，所以用 response.cookies（Netscape 格式）自己攒会话。
 */
export class ElectricClient {
  static async query(campus: ElectricCampus, meter: string): Promise<MeterReading> {
    const comAddress: string = meter.trim();
    if (!METER_PATTERN.test(comAddress)) {
      throw new ElectricError('表号应为 6 位以上数字', ElectricErrorKind.INVALID_METER);
    }

    const client = http.createHttp();
    const jar: Record<string, string> = {};
    try {
      // 1. 选校：这一步就会下发 connect.sid，所以不需要先访问入口页。
      //    会话已被标记绑房时先解绑，否则 /selectmeter 常返回错误页。
      const areaBody: string = JSON.stringify({
        'areaId': campus.areaId,
        'areaName': campus.areaName
      });
      let area: Record<string, string> = await ElectricClient.selectArea(client, jar, areaBody);
      if (ElectricClient.looksBound(area)) {
        try {
          await ElectricClient.send(client, jar, http.RequestMethod.POST, '/phonejcbd', '{}', '/selectPhoneMeter');
        } catch (error) {
          // 解绑失败也继续，/selectmeter 仍有机会成功。
        }
        area = await ElectricClient.selectArea(client, jar, areaBody);
      }

      // 2. 提交表号
      const selectBody: string = JSON.stringify({
        'comAddress': comAddress,
        'hidType': '电表',
        'room': ''
      });
      const select: Exchange = await ElectricClient.send(
        client, jar, http.RequestMethod.POST, '/selectmeter', selectBody, '/login');
      const selectJson: Record<string, string> = ElectricClient.parseJson(select.body);
      const target: string = ElectricParser.clean(pick(selectJson, 'url'));
      if (target.length === 0) {
        const message: string = ElectricParser.clean(pick(selectJson, 'msg')).length > 0
          ? ElectricParser.clean(pick(selectJson, 'msg'))
          : ElectricParser.clean(pick(selectJson, 'message'));
        throw new ElectricError(
          message.length > 0 ? `表号被拒绝：${message}` : '表号无效，或该电表未接入电精灵',
          ElectricErrorKind.INVALID_METER);
      }

      // 3. 读数页
      const path: string = target.startsWith('/') ? target : `/${target}`;
      const main: Exchange = await ElectricClient.send(
        client, jar, http.RequestMethod.GET, path, '', '/selectmeter');
      if (main.code !== 200) {
        throw new ElectricError(`电表页面返回 HTTP ${main.code}，请稍后重试`, ElectricErrorKind.NETWORK);
      }
      if (main.body.indexOf('errorApp') >= 0) {
        throw new ElectricError('站点返回错误页，请确认表号或稍后重试', ElectricErrorKind.EMPTY);
      }
      const refs: Record<string, string> = ElectricParser.refs(main.body);
      const totalYuan: string = pick(refs, 'zye');
      const prepaidYuan: string = pick(refs, 'yffye');
      const totalKwh: string = pick(refs, 'zydl');
      if (totalYuan.length === 0 && prepaidYuan.length === 0 && totalKwh.length === 0) {
        throw new ElectricError(
          refs['yffye'] === undefined && refs['zydl'] === undefined
            ? '没读到读数，页面结构可能已变化'
            : '该电表暂无可读数据',
          ElectricErrorKind.EMPTY);
      }

      // 4. 月账单（可选，失败不影响余额展示）
      let billMonth: string = '';
      let billKwh: string = '';
      let billYuan: string = '';
      try {
        const bill: Exchange = await ElectricClient.send(
          client, jar, http.RequestMethod.GET, '/electricbill', '', '/meter_main');
        if (bill.code === 200 && bill.body.indexOf('billData') >= 0) {
          const values: Record<string, string> = ElectricParser.billValues(bill.body);
          billMonth = ElectricParser.billMonth(bill.body);
          billKwh = pick(values, 'ydl');
          billYuan = pick(values, 'ydje');
        }
      } catch (error) {
        // 账单是锦上添花。
      }

      const subsidy: string = pick(refs, 'bzdye').length > 0
        ? pick(refs, 'bzdye') : pick(refs, 'bzye');
      return {
        campusLabel: campus.label,
        meter: comAddress,
        room: pick(refs, 'roomaddr'),
        prepaidYuan: prepaidYuan,
        subsidyYuan: subsidy,
        totalYuan: totalYuan.length > 0 ? totalYuan : prepaidYuan,
        totalKwh: totalKwh,
        meterStatus: pick(refs, 'dbzt'),
        readingTime: pick(refs, 'cbsj'),
        billMonth: billMonth,
        billKwh: billKwh,
        billYuan: billYuan,
        fetchedAt: Date.now()
      };
    } catch (error) {
      if (error instanceof ElectricError) {
        throw error;
      }
      const failure: BusinessError = error as BusinessError;
      const suffix: string = failure.code === undefined || failure.code === null ? '' : `（${failure.code}）`;
      throw new ElectricError(`无法连接电精灵${suffix}，请检查网络后重试`, ElectricErrorKind.NETWORK);
    } finally {
      client.destroy();
    }
  }

  private static async selectArea(
    client: http.HttpRequest,
    jar: Record<string, string>,
    body: string
  ): Promise<Record<string, string>> {
    const response: Exchange = await ElectricClient.send(
      client, jar, http.RequestMethod.POST, '/selectarea', body, '/selectArea');
    return ElectricClient.parseJson(response.body);
  }

  /** 站点用 `band: "1"` 或 `data: "selectmeter"` 表示当前会话已绑过房间。 */
  private static looksBound(area: Record<string, string>): boolean {
    if (pick(area, 'band') === '1') {
      return true;
    }
    const data: string = pick(area, 'data');
    return data === 'selectmeter' || data === 'selectPhoneMeter' || data === 'meter_main';
  }

  private static parseJson(body: string): Record<string, string> {
    try {
      const parsed: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
      const result: Record<string, string> = {};
      for (const key of Object.keys(parsed)) {
        const value: Object = parsed[key];
        result[key] = value === null || value === undefined ? '' : `${value}`;
      }
      return result;
    } catch (error) {
      throw new ElectricError('站点返回了无法解析的内容', ElectricErrorKind.PARSE);
    }
  }

  private static headers(json: boolean, referer: string): Record<string, string> {
    const header: Record<string, string> = {
      'User-Agent': UA,
      'Accept': json ? 'application/json, text/plain, */*' : 'text/html,application/xhtml+xml,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'X-Requested-With': 'com.tencent.mm',
      'Origin': BASE,
      'Referer': `${BASE}${referer}`
    };
    if (json) {
      header['Content-Type'] = 'application/json';
    }
    return header;
  }

  private static async send(
    client: http.HttpRequest,
    jar: Record<string, string>,
    method: http.RequestMethod,
    path: string,
    body: string,
    referer: string
  ): Promise<Exchange> {
    const header: Record<string, string> = ElectricClient.headers(body.length > 0, referer);
    const cookie: string = ElectricClient.cookieHeader(jar);
    if (cookie.length > 0) {
      header['Cookie'] = cookie;
    }
    const options: http.HttpRequestOptions = {
      method: method,
      header: header,
      connectTimeout: CONNECT_TIMEOUT,
      readTimeout: READ_TIMEOUT,
      expectDataType: http.HttpDataType.STRING,
      extraData: body.length > 0 ? body : undefined
    };
    const response: http.HttpResponse = await client.request(`${BASE}${path}`, options);
    ElectricClient.absorbCookies(jar, response.cookies);
    ElectricClient.absorbHeaderCookies(jar, response.header);
    const text: string = typeof response.result === 'string' ? response.result : '';
    return { code: response.responseCode, body: text };
  }

  /** `response.cookies` 是 Netscape cookie-file 格式；同时兼容 `a=b; c=d`。 */
  private static absorbCookies(jar: Record<string, string>, raw: string): void {
    if (raw === undefined || raw === null || raw.length === 0) {
      return;
    }
    for (const line of raw.split('\n')) {
      const trimmed: string = line.trim();
      if (trimmed.length === 0 || trimmed.startsWith('#')) {
        continue;
      }
      if (trimmed.indexOf('\t') >= 0) {
        const columns: string[] = trimmed.split('\t');
        if (columns.length < 7 || columns[5].trim().length === 0) {
          continue;
        }
        // Netscape 首列是 domain：跟随重定向时可能混入其他域的 Cookie，这里只留本站的。
        const domain: string = columns[0].trim();
        if (domain.length > 0 && domain.indexOf('bdfairy') < 0) {
          continue;
        }
        jar[columns[5].trim()] = columns[6].trim();
        continue;
      }
      const equals: number = trimmed.indexOf('=');
      if (equals > 0) {
        const semicolon: number = trimmed.indexOf(';');
        const valueEnd: number = semicolon > equals ? semicolon : trimmed.length;
        jar[trimmed.substring(0, equals).trim()] = trimmed.substring(equals + 1, valueEnd).trim();
      }
    }
  }

  /** 兜底：`response.cookies` 为空时从 `Set-Cookie` 响应头里取。 */
  private static absorbHeaderCookies(jar: Record<string, string>, header: Object): void {
    if (header === undefined || header === null) {
      return;
    }
    const record: Record<string, Object> = header as Record<string, Object>;
    for (const key of Object.keys(record)) {
      if (key.toLowerCase() !== 'set-cookie') {
        continue;
      }
      const value: Object = record[key];
      if (typeof value === 'string') {
        ElectricClient.absorbCookies(jar, value);
      } else if (Array.isArray(value)) {
        for (const item of value as Object[]) {
          ElectricClient.absorbCookies(jar, `${item}`);
        }
      }
    }
  }

  private static cookieHeader(jar: Record<string, string>): string {
    const parts: string[] = [];
    for (const key of Object.keys(jar)) {
      parts.push(`${key}=${jar[key]}`);
    }
    return parts.join('; ');
  }
}
