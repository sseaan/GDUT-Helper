export interface ClassroomBuilding {
  code: string;
  number: string;
  name: string;
  campusCode: string;
  campusName: string;
}

export interface ClassroomRoom {
  code: string;
  name: string;
  capacity: number;
}

export enum OccupancyType {
  COURSE = 'COURSE',
  BORROWED = 'BORROWED',
  LOCKED = 'LOCKED',
  EXAM = 'EXAM',
  OTHER = 'OTHER'
}

export interface ClassroomOccupancy {
  id: string;
  roomCode: string;
  roomName: string;
  periods: number[];
  periodCode: string;
  courseName: string;
  teacher: string;
  className: string;
  note: string;
  type: OccupancyType;
  count: number;
}

export enum JwcwxErrorKind {
  NETWORK = 'NETWORK',
  CREDENTIALS = 'CREDENTIALS',
  SESSION = 'SESSION',
  PROTOCOL = 'PROTOCOL'
}

export class JwcwxError extends Error {
  readonly kind: JwcwxErrorKind;

  constructor(message: string, kind: JwcwxErrorKind = JwcwxErrorKind.PROTOCOL) {
    super(message);
    this.kind = kind;
  }
}
