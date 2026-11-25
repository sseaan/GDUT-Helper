/**
 * Navigation callbacks shared by tab content. Kept as a class so V1 components
 * can receive one stable object instead of a long list of function props.
 */
export class AppNavActions {
  onOpenSemester: () => void = () => {};
  onAddCourse: (semesterId: string) => void = () => {};
  onAddMakeup: (semesterId: string, sourceCourseId: string, week: number) => void = () => {};
  onEditCourse: (semesterId: string, courseId: string) => void = () => {};
  onOpenSync: () => void = () => {};
  onAddEvent: (semesterId: string, date: string, eventId: string) => void = () => {};
}
