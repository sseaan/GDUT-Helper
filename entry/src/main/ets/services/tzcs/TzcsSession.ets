export const TZCS_SESSION_REVISION_KEY: string = 'tzcsSessionRevision';

/** Cookie captured from the Tzcs WebView login. */
export class TzcsSession {
  private static cookie: string = '';

  static setCookie(cookie: string): void {
    TzcsSession.cookie = cookie;
    AppStorage.setOrCreate(TZCS_SESSION_REVISION_KEY, TzcsSession.revision() + 1);
  }

  static getCookie(): string {
    return TzcsSession.cookie;
  }

  static isLoggedIn(): boolean {
    return TzcsSession.cookie.length > 0;
  }

  static clear(): void {
    TzcsSession.cookie = '';
    AppStorage.setOrCreate(TZCS_SESSION_REVISION_KEY, TzcsSession.revision() + 1);
  }

  private static revision(): number {
    const value: number | undefined = AppStorage.get<number>(TZCS_SESSION_REVISION_KEY);
    return value === undefined ? 0 : value;
  }
}
