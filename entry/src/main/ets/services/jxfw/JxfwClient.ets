import { http } from '@kit.NetworkKit';
import { JxfwError, JxfwErrorKind } from './JxfwModels';
import { JxfwSession } from './JxfwSession';
import { JxfwParser } from './JxfwParser';
import { CasLoginService } from './CasLoginService';
import { JxfwExam, JxfwLesson, JxfwWeek } from './JxfwModels';

const JXFW_BASE: string = 'https://jxfw.gdut.edu.cn';
const USER_AGENT: string = 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36';

export class JxfwClient {
  private async request(
    method: http.RequestMethod,
    url: string,
    body: string = '',
    referer: string = '',
    includeSession: boolean = true,
    allowRetry: boolean = true
  ): Promise<string> {
    const client = http.createHttp();
    try {
      const headers: Record<string, string> = {
        'User-Agent': USER_AGENT,
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Accept': 'application/json, text/javascript, */*; q=0.01'
      };
      if (referer.length > 0) {
        headers['Referer'] = referer;
      }
      if (body.length > 0) {
        headers['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8';
        headers['X-Requested-With'] = 'XMLHttpRequest';
      }
      if (includeSession && JxfwSession.getCookie().length > 0) {
        headers['Cookie'] = JxfwSession.getCookie();
      }
      const response = await client.request(url, {
        method: method,
        header: headers,
        connectTimeout: 15000,
        readTimeout: 25000,
        expectDataType: http.HttpDataType.STRING,
        extraData: body.length > 0 ? body : undefined
      });
      const text: string = typeof response.result === 'string' ? response.result : '';
      if (response.responseCode < 200 || response.responseCode >= 400) {
        throw new JxfwError(`HTTP ${response.responseCode}`, JxfwErrorKind.NETWORK);
      }
      if (includeSession) {
        try {
          this.ensureSession(text);
        } catch (error) {
          if (allowRetry && error instanceof JxfwError &&
            error.kind === JxfwErrorKind.SESSION &&
            await CasLoginService.autoLogin()) {
            return this.request(method, url, body, referer, includeSession, false);
          }
          if (error instanceof JxfwError) {
            throw error;
          }
          throw new JxfwError('教务会话失效', JxfwErrorKind.SESSION);
        }
      }
      return text;
    } catch (error) {
      if (error instanceof Error) {
        throw error;
      }
      throw new JxfwError('无法连接教务系统，请检查网络', JxfwErrorKind.NETWORK);
    } finally {
      client.destroy();
    }
  }

  private ensureSession(text: string): void {
    const trimmed: string = text.trimStart();
    if (text.includes('使用统一认证中心登录') || text.includes('请输入学号或工号') ||
      ((trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<html')) &&
        !text.includes('var kbxx') && !text.includes('教学管理系统'))) {
      throw new JxfwError('教务会话已失效，请重新登录', JxfwErrorKind.SESSION);
    }
    if (text.includes('请输入短信验证码')) {
      throw new JxfwError('教务系统要求短信验证，请先完成验证', JxfwErrorKind.SMS);
    }
  }

  async fetchAllKb(term: string): Promise<string> {
    const url: string = `${JXFW_BASE}/xsgrkbcx!xsAllKbList.action?xnxqdm=${encodeURIComponent(term)}`;
    return this.request(http.RequestMethod.GET, url,
      '', `${JXFW_BASE}/xsgrkbcx!getXsgrbkList.action`);
  }

  async fetchWeek(term: string, week: number): Promise<string> {
    const url: string = `${JXFW_BASE}/xsgrkbcx!getKbRq.action?xnxqdm=${encodeURIComponent(term)}&zc=${week}`;
    return this.request(http.RequestMethod.GET, url,
      '', `${JXFW_BASE}/xsgrkbcx!xskbList.action`);
  }

  async fetchExams(term: string): Promise<string> {
    const body: string = `xnxqdm=${encodeURIComponent(term)}&page=1&rows=60&sort=${encodeURIComponent('zc,xq,jcdm2')}&order=asc`;
    return this.request(http.RequestMethod.POST, `${JXFW_BASE}/xsksap!getDataList.action`,
      body, `${JXFW_BASE}/xsksap!ksapList.action`);
  }

  async fetchGradePage(term: string, page: number, rows: number): Promise<string> {
    const body: string =
      `xnxqdm=${encodeURIComponent(term)}&jhlxdm=&page=${page}&rows=${rows}&sort=xnxqdm&order=asc`;
    return this.request(http.RequestMethod.POST, `${JXFW_BASE}/xskccjxx!getDataList.action`,
      body, `${JXFW_BASE}/xskccjxx!xskccjList.action?firstquery=1`);
  }

  async fetchAllLessons(term: string): Promise<JxfwLesson[]> {
    return JxfwParser.parseLessons(await this.fetchAllKb(term));
  }

  async fetchExamList(term: string): Promise<JxfwExam[]> {
    return JxfwParser.parseExams(await this.fetchExams(term));
  }

  async fetchWeekData(term: string, week: number): Promise<JxfwWeek> {
    return JxfwParser.parseWeek(await this.fetchWeek(term, week));
  }
}
