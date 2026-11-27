import { http } from '@kit.NetworkKit';
import { JxfwSession } from '../jxfw/JxfwSession';

const PROBE_URL: string = 'https://jxfw.gdut.edu.cn/login!welcome.action';
const PROBE_REFERER: string = 'https://jxfw.gdut.edu.cn/default!index.action';
const USER_AGENT: string = 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36';
const SAMPLE_COUNT: number = 3;
const MAX_STALE_MS: number = 10 * 60 * 1000;

interface ClockSample {
  offsetMs: number;
  rttMs: number;
}

interface ProbeResult {
  serverMs: number;
  rttMs: number;
  ok: boolean;
}

function headerValue(response: http.HttpResponse, name: string): string {
  const headers: Record<string, Object> = response.header as Record<string, Object>;
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() !== name.toLowerCase()) {
      continue;
    }
    const value: Object = headers[key];
    if (Array.isArray(value)) {
      return (value as Object[]).map((item: Object) => `${item}`).join(', ');
    }
    return `${value}`;
  }
  return '';
}

/**
 * 服务器时钟校准与准点等待。
 *
 * jxfw 的 `Date` 响应头是学校服务器时间，用最小 RTT 的一次采样估算本机偏移，
 * 抢课按「服务器到达目标时刻」触发，避免手机时钟误差导致早/晚一整分钟。
 */
export class SelectionClock {
  private static offsetMs: number = 0;
  private static rttMs: number = 0;
  private static calibrated: boolean = false;
  private static calibratedAt: number = 0;

  static getOffsetMs(): number {
    return SelectionClock.offsetMs;
  }

  static getRttMs(): number {
    return SelectionClock.rttMs;
  }

  static isCalibrated(): boolean {
    return SelectionClock.calibrated;
  }

  static isStale(): boolean {
    if (!SelectionClock.calibrated) {
      return true;
    }
    return Date.now() - SelectionClock.calibratedAt > MAX_STALE_MS;
  }

  /** 手动偏移兜底：手机时间比服务器快多少毫秒。 */
  static setOffset(offsetMs: number): void {
    SelectionClock.offsetMs = offsetMs;
    SelectionClock.calibrated = true;
    SelectionClock.calibratedAt = Date.now();
  }

  static reset(): void {
    SelectionClock.offsetMs = 0;
    SelectionClock.rttMs = 0;
    SelectionClock.calibrated = false;
    SelectionClock.calibratedAt = 0;
  }

  /** 服务器时间（毫秒）。 */
  static serverNow(): number {
    return Date.now() + SelectionClock.offsetMs;
  }

  /** 把「服务器时间戳」换算成本机 `Date.now()` 时间线。 */
  static toLocal(serverMs: number): number {
    return serverMs - SelectionClock.offsetMs;
  }

  static async calibrate(): Promise<boolean> {
    const samples: ClockSample[] = [];
    for (let i = 0; i < SAMPLE_COUNT; i++) {
      const probe: ProbeResult = await SelectionClock.probe();
      if (probe.ok && probe.rttMs < 5000) {
        samples.push({
          offsetMs: probe.serverMs - (Date.now() - probe.rttMs / 2),
          rttMs: probe.rttMs
        });
      }
      if (i < SAMPLE_COUNT - 1) {
        await SelectionClock.sleep(150);
      }
    }
    if (samples.length === 0) {
      return false;
    }
    let best: ClockSample = samples[0];
    for (const sample of samples) {
      if (sample.rttMs < best.rttMs) {
        best = sample;
      }
    }
    SelectionClock.offsetMs = Math.round(best.offsetMs);
    SelectionClock.rttMs = Math.round(best.rttMs);
    SelectionClock.calibrated = true;
    SelectionClock.calibratedAt = Date.now();
    return true;
  }

  private static async probe(): Promise<ProbeResult> {
    const client: http.HttpRequest = http.createHttp();
    const start: number = Date.now();
    try {
      const headers: Record<string, string> = {
        'User-Agent': USER_AGENT,
        'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Referer': PROBE_REFERER
      };
      const cookie: string = JxfwSession.getCookie();
      if (cookie.length > 0) {
        headers['Cookie'] = cookie;
      }
      const response: http.HttpResponse = await client.request(PROBE_URL, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 8000,
        readTimeout: 10000,
        expectDataType: http.HttpDataType.STRING
      });
      const end: number = Date.now();
      const serverDate: string = headerValue(response, 'date');
      const serverMs: number = serverDate.length > 0 ? new Date(serverDate).getTime() : 0;
      return {
        serverMs: Number.isNaN(serverMs) ? 0 : serverMs,
        rttMs: end - start,
        ok: serverMs > 0
      };
    } catch (error) {
      return { serverMs: 0, rttMs: 0, ok: false };
    } finally {
      client.destroy();
    }
  }

  static sleep(ms: number): Promise<void> {
    const delay: number = ms < 0 ? 0 : ms;
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), delay);
    });
  }

  /**
   * 等待到本机时间线的目标时刻。分段休眠 + 末段忙等，
   * 避免一次性 `setTimeout(大间隔)` 的累积漂移与定时器精度损失。
   */
  static async sleepUntil(targetLocalMs: number): Promise<void> {
    for (;;) {
      const remain: number = targetLocalMs - Date.now();
      if (remain <= 0) {
        return;
      }
      if (remain > 1500) {
        await SelectionClock.sleep(remain - 1000);
      } else if (remain > 60) {
        await SelectionClock.sleep(Math.min(remain - 45, 50));
      } else {
        while (Date.now() < targetLocalMs) {
          // 末段 60ms 内的忙等，保证发射时刻误差在个位数毫秒。
        }
        return;
      }
    }
  }

  static formatOffset(): string {
    if (!SelectionClock.calibrated) {
      return '未校准';
    }
    const offset: number = SelectionClock.offsetMs;
    const sign: string = offset > 0 ? '+' : '';
    return `${sign}${offset}ms · RTT ${SelectionClock.rttMs}ms`;
  }
}
