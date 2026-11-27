import { Identifiers } from '../../common/Identifiers';

/** What a scanned code should turn into. */
export enum ScanPayloadKind {
  URL = 'URL',
  ISBN = 'ISBN',
  TEXT = 'TEXT'
}

export interface ScanPayload {
  kind: ScanPayloadKind;
  /** Normalised value: URL with a scheme, ISBN without separators, otherwise trimmed text. */
  value: string;
  /** Text exactly as the scanner returned it, used for the "other" branch. */
  raw: string;
}

/**
 * Turns a raw scanner string into an actionable payload.
 *
 * The app does not guess: only checksum-valid ISBNs and explicit http(s)/www URLs
 * become actions, everything else stays text and is handled by asking the user.
 */
export class ScanRoute {
  static classify(raw: string): ScanPayload {
    const text: string = raw.trim();
    const isbn: string = Identifiers.isbnOf(text);
    if (isbn.length > 0) {
      return { kind: ScanPayloadKind.ISBN, value: isbn, raw: raw };
    }
    const url: string = Identifiers.urlOf(text);
    if (url.length > 0) {
      return { kind: ScanPayloadKind.URL, value: url, raw: raw };
    }
    return { kind: ScanPayloadKind.TEXT, value: text, raw: raw };
  }
}
