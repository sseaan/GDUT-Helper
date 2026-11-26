export const LIBRARY_SESSION_REVISION_KEY: string = 'librarySessionRevision';

/** In-memory OPAC session created by CAS login. */
export class LibrarySession {
  private static cookie: string = '';

  static setCookie(cookie: string): void {
    LibrarySession.cookie = cookie;
    LibrarySession.bump();
  }

  static getCookie(): string {
    return LibrarySession.cookie;
  }

  static isLoggedIn(): boolean {
    return LibrarySession.token().length > 0;
  }

  static token(): string {
    return LibrarySession.cookieValue('jwt');
  }

  static headerName(): string {
    const name: string = LibrarySession.cookieValue('jwtHeader');
    return name.length > 0 ? name : 'jwtOpacAuth';
  }

  static clear(): void {
    LibrarySession.cookie = '';
    LibrarySession.bump();
  }

  private static bump(): void {
    const value: number | undefined = AppStorage.get<number>(LIBRARY_SESSION_REVISION_KEY);
    AppStorage.setOrCreate(LIBRARY_SESSION_REVISION_KEY, (value === undefined ? 0 : value) + 1);
  }

  private static cookieValue(name: string): string {
    for (const part of LibrarySession.cookie.split(';')) {
      const trimmed: string = part.trim();
      const equals: number = trimmed.indexOf('=');
      if (equals > 0 && trimmed.substring(0, equals).trim() === name) {
        return trimmed.substring(equals + 1).trim();
      }
    }
    return '';
  }
}
