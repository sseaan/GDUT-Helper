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

export interface LibraryOverview {
  user: LibraryUser;
  loans: LibraryLoan[];
  loanQuota: number;
  total: number;
  fetchedAt: number;
}
