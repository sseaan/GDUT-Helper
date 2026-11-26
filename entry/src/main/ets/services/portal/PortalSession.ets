/** In-memory ehall session created by the native CAS login. */
export class PortalSession {
  private static cookie: string = '';

  static setCookie(cookie: string): void {
    PortalSession.cookie = cookie;
  }

  static getCookie(): string {
    return PortalSession.cookie;
  }

  static isLoggedIn(): boolean {
    return PortalSession.cookie.length > 0;
  }

  static clear(): void {
    PortalSession.cookie = '';
  }
}
