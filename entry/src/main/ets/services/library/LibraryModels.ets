export enum LibraryErrorKind {
  NETWORK = 'NETWORK',
  CREDENTIALS = 'CREDENTIALS',
  SESSION = 'SESSION',
  PROTOCOL = 'PROTOCOL'
}

export class LibraryError extends Error {
  readonly kind: LibraryErrorKind;

  constructor(message: string, kind: LibraryErrorKind = LibraryErrorKind.PROTOCOL) {
    super(message);
    this.kind = kind;
  }
}

export interface LibraryUser {
  name: string;
  unit: string;
  department: string;
  userId: string;
}

export interface LibraryLoan {
  id: string;
  title: string;
  author: string;
  barcode: string;
  location: string;
  loanDate: string;
  dueDate: string;
  returnDate: string;
  renewCount: number;
  status: string;
  raw: string;
}

/** 检索字段；值与 OPAC 的 `searchField` 一一对应，`ALL` 为模糊检索。 */
export enum LibrarySearchField {
  ALL = 'keyWord',
  TITLE = 'title',
  AUTHOR = 'author',
  CALL_NO = 'callNo',
  ISBN = 'isbn'
}

/** 排序字段；实测 `publishTime` 无效会直接返 0 条，不要用。 */
export enum LibrarySort {
  RELEVANCE = 'relevance',
  TITLE = 'title_sort',
  NEWEST = 'publishYear'
}

export interface LibrarySearchQuery {
  keyword: string;
  field: LibrarySearchField;
  sort: LibrarySort;
}

/** 书目检索命中项，字段来自 OPAC `/find/unify/search` 的 `searchResult`。 */
export interface LibraryBook {
  recordId: string;
  title: string;
  author: string;
  publisher: string;
  isbn: string;
  publishYear: string;
  callNo: string;
  price: string;
  pageCount: string;
  subject: string;
  /** 馆藏册数。 */
  physicalCount: number;
  /** 可借（在架）册数。 */
  onShelfCount: number;
  abstractText: string;
}

/** 单册馆藏，字段来自 OPAC `/find/physical/groupitems`。 */
export interface LibraryHolding {
  itemId: string;
  callNo: string;
  barcode: string;
  location: string;
  /** OPAC 的 `processType`，例如“借出-应还日期:2025-05-09”或“在架”。 */
  status: string;
  policy: string;
  inDate: string;
  vol: string;
  year: string;
}

export interface LibrarySearchResult {
  total: number;
  books: LibraryBook[];
  page: number;
  rows: number;
}

export interface LibraryOverview {
  user: LibraryUser;
  loans: LibraryLoan[];
  loanQuota: number;
  total: number;
  fetchedAt: number;
}
