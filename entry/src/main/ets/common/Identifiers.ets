/**
 * Recognising URLs and ISBNs inside arbitrary text (scan results, pasted strings).
 *
 * Kept framework-free so the scan router and the library client share one set of
 * rules instead of each guessing on its own. All functions are total: they return
 * an empty string instead of throwing when the text is not a valid identifier.
 */

const ISBN_13_PREFIXES: string[] = ['978', '979'];
const ISBN_SEPARATORS: string[] = ['-', ' ', '.', '_', '\u3000'];
const ISBN_MAX_LENGTH: number = 24;
const WEB_SEARCH_URL: string = 'https://cn.bing.com/search?q=';

export class Identifiers {
  /**
   * Returns a normalized ISBN (digits only, `X` kept for ISBN-10) or an empty
   * string when the text is not a checksum-valid ISBN-10 / ISBN-13.
   */
  static isbnOf(raw: string): string {
    const text: string = raw.trim();
    if (text.length === 0 || text.length > ISBN_MAX_LENGTH) {
      return '';
    }
    let digits: string = '';
    for (let index = 0; index < text.length; index++) {
      const char: string = text.charAt(index);
      if (ISBN_SEPARATORS.indexOf(char) >= 0) {
        continue;
      }
      if (char === 'X' || char === 'x') {
        digits += 'X';
        continue;
      }
      if (char < '0' || char > '9') {
        return '';
      }
      digits += char;
    }
    if (digits.length === 13) {
      return Identifiers.isValidIsbn13(digits) ? digits : '';
    }
    if (digits.length === 10) {
      return Identifiers.isValidIsbn10(digits) ? digits : '';
    }
    return '';
  }

  /**
   * Returns an openable http(s) URL, or an empty string when the text is not one.
   * `www.` prefixed input gets `https://`; bare host names stay unrecognised so a
   * random scanned string is never turned into a browser jump.
   */
  static urlOf(raw: string): string {
    const text: string = raw.trim();
    if (text.length === 0) {
      return '';
    }
    const lower: string = text.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return text.length > lower.indexOf('://') + 3 ? text : '';
    }
    if (lower.startsWith('www.')) {
      return text.length > 4 ? `https://${text}` : '';
    }
    return '';
  }

  /** Web search URL used by the "search in browser" escape hatch. */
  static webSearchUrl(keyword: string): string {
    return `${WEB_SEARCH_URL}${encodeURIComponent(keyword.trim())}`;
  }

  private static isValidIsbn13(digits: string): boolean {
    if (ISBN_13_PREFIXES.indexOf(digits.substring(0, 3)) < 0) {
      return false;
    }
    let sum: number = 0;
    for (let index = 0; index < 12; index++) {
      const digit: number = digits.charCodeAt(index) - 48;
      if (digit < 0 || digit > 9) {
        return false;
      }
      sum += index % 2 === 0 ? digit : digit * 3;
    }
    const check: number = digits.charCodeAt(12) - 48;
    return (10 - (sum % 10)) % 10 === check;
  }

  private static isValidIsbn10(value: string): boolean {
    let sum: number = 0;
    for (let index = 0; index < 10; index++) {
      const char: string = value.charAt(index);
      const digit: number = char === 'X' ? 10 : char.charCodeAt(0) - 48;
      if (char !== 'X' && (digit < 0 || digit > 9)) {
        return false;
      }
      // `X` is only allowed as the last (check) character.
      if (char === 'X' && index !== 9) {
        return false;
      }
      sum += digit * (10 - index);
    }
    return sum % 11 === 0;
  }
}
