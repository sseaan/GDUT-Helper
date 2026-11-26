/**
 * jxfw school-term helpers.
 *
 * GDUT term codes are `YYYY01` / `YYYY02`, where YYYY is the academic year
 * start. The jxfw semester dropdown is not reliable, so the app derives the
 * current term from the local date and shifts it by one term on each side.
 */
export function isValidTermCode(code: string): boolean {
  return /^\d{4}(01|02)$/.test(code.trim());
}

export function currentTermCode(date: Date = new Date()): string {
  const month: number = date.getMonth() + 1;
  if (month >= 8) {
    return `${date.getFullYear()}01`;
  }
  if (month === 1) {
    return `${date.getFullYear() - 1}01`;
  }
  return `${date.getFullYear() - 1}02`;
}

/** Moves a term by a signed number of terms, e.g. 202601 + 1 = 202602. */
export function shiftTermCode(code: string, delta: number): string {
  const term: string = code.trim();
  if (!isValidTermCode(term)) {
    return term;
  }
  const year: number = Number.parseInt(term.substring(0, 4), 10);
  const half: number = term.substring(4) === '01' ? 0 : 1;
  const index: number = year * 2 + half + delta;
  const nextYear: number = Math.floor(index / 2);
  const nextHalf: number = index % 2;
  return `${nextYear}${nextHalf === 0 ? '01' : '02'}`;
}

export function termLabel(code: string): string {
  const term: string = code.trim();
  if (!isValidTermCode(term)) {
    return term.length > 0 ? term : '未选择学期';
  }
  const year: number = Number.parseInt(term.substring(0, 4), 10);
  return `${year}-${year + 1} ${term.substring(4) === '01' ? '第一学期' : '第二学期'}`;
}

/** Previous, current and next term, in display order. */
export function surroundingTermCodes(date: Date = new Date()): string[] {
  const current: string = currentTermCode(date);
  return [shiftTermCode(current, -1), current, shiftTermCode(current, 1)];
}
