export interface CourseEditParam {
  semesterId: string;
  courseId: string;
  sourceCourseId?: string;
  makeupWeek?: number;
}

export interface CourseDetailParam {
  courseId: string;
  week: number;
}


export interface EventEditParam {
  semesterId: string;
  date: string;
  eventId: string;
}
