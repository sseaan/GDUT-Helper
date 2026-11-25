export const JXFW_SESSION_REVISION_KEY: string = 'jxfwSessionRevision';

/** In-memory jxfw session created by native CAS login. */
export class JxfwSession {
  private static cookie: string = '';
  private static username: string = '';

  static setCookie(cookie: string, username: string = ''): void {
    JxfwSession.cookie = cookie;
    JxfwSession.username = username;
    AppStorage.setOrCreate(JXFW_SESSION_REVISION_KEY, JxfwSession.revision() + 1);
  }

  static getCookie(): string {
    return JxfwSession.cookie;
  }

  static getUsername(): string {
    return JxfwSession.username;
  }

  static isLoggedIn(): boolean {
    return JxfwSession.cookie.length > 0;
  }

  static clear(): void {
    JxfwSession.cookie = '';
    JxfwSession.username = '';
    AppStorage.setOrCreate(JXFW_SESSION_REVISION_KEY, JxfwSession.revision() + 1);
  }

  private static revision(): number {
    const value: number | undefined = AppStorage.get<number>(JXFW_SESSION_REVISION_KEY);
    return value === undefined ? 0 : value;
  }
}
