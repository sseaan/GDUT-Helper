import { common } from '@kit.AbilityKit';
import { AppTheme } from '../../common/Theme';
import { AppNavActions } from '../../common/AppNavActions';
import { CoursePalette } from '../../common/CoursePalette';
import { CourseSheet } from '../../components/CourseSheet';
import {
  Conflict,
  Course,
  CourseException,
  ExpandedCourse,
  Semester,
  weekdayLabel
} from '../../domain/model/TimetableModels';
import { DEFAULT_PERIOD_TIMES } from '../../domain/model/Periods';
import {
  dateForWeekDay,
  detectConflicts,
  expandWeek,
  todayIso,
  weekDateRange,
  weekOf,
  parseIsoDate
} from '../../domain/timetable/TimetableEngine';
import { TimetableRepository } from '../../data/TimetableRepository';
import { DisplaySettings } from '../../state/DisplaySettings';

@Component
export struct TimetablePage {
  nav: AppNavActions = new AppNavActions();
  @StorageLink('timetableRevision') @Watch('onRevisionChange') revision: number = 0;
  @State semester: Semester | null = null;
  @State week: number = 1;
  @State expanded: ExpandedCourse[] = [];
  @StorageLink('showCourseContent') showCourseContent: boolean = false;
  @State conflicts: Conflict[] = [];
  @State loading: boolean = true;
  @State selectedCourse: ExpandedCourse | null = null;
  @State showCourseSheet: boolean = false;
  private courses: Course[] = [];
  private exceptions: CourseException[] = [];
  private initializedWeek: boolean = false;
  private scroller: Scroller = new Scroller();
  private readonly rowHeight: number = 56;
  private readonly timeColumnWidth: number = 32;

  aboutToAppear(): void {
    DisplaySettings.load(this.context());
    this.loadAll();
  }

  onRevisionChange(): void {
    this.loadAll();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async loadAll(): Promise<void> {
    try {
      const semester: Semester | null = await TimetableRepository.getCurrentSemester(this.context());
      this.semester = semester;
      if (semester === null) {
        this.courses = [];
        this.exceptions = [];
        this.expanded = [];
        this.conflicts = [];
        this.loading = false;
        return;
      }
      this.courses = await TimetableRepository.listCourses(this.context(), semester.id);
      this.exceptions = await TimetableRepository.listExceptions(this.context(), semester.id);
      if (!this.initializedWeek) {
        const now: Date = new Date();
        const today: Date = new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
        const current: number = weekOf(semester.startDate, today);
        this.week = current >= 1 && current <= semester.totalWeeks ? current : 1;
        this.initializedWeek = true;
      }
      this.rebuild();
    } catch (error) {
      this.expanded = [];
      this.conflicts = [];
    } finally {
      this.loading = false;
    }
  }

  private rebuild(): void {
    if (this.semester === null) {
      return;
    }
    this.expanded = expandWeek(this.courses, this.exceptions, this.week);
    this.conflicts = detectConflicts(this.expanded);
  }

  private previousWeek(): void {
    if (this.semester !== null && this.week > 1) {
      this.week = this.week - 1;
      this.rebuild();
    }
  }

  private nextWeek(): void {
    if (this.semester !== null && this.week < this.semester.totalWeeks) {
      this.week = this.week + 1;
      this.rebuild();
    }
  }

  private rangeLabel(): string {
    if (this.semester === null) {
      return '';
    }
    return weekDateRange(this.semester.startDate, this.week);
  }

  private dayDate(index: number): Date {
    if (this.semester === null) {
      return new Date();
    }
    return dateForWeekDay(this.semester.startDate, this.week, index + 1);
  }

  private dateLabel(index: number): string {
    if (this.semester === null) {
      return '';
    }
    const date: Date = this.dayDate(index);
    return `${date.getUTCMonth() + 1}/${date.getUTCDate()}`;
  }

  private todayIndex(): number {
    if (this.semester === null) {
      return -1;
    }
    const now: Date = new Date();
    const today: Date = new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
    const currentWeek: number = weekOf(this.semester.startDate, today);
    if (currentWeek !== this.week) {
      return -1;
    }
    return (today.getUTCDay() + 6) % 7;
  }

  private coursesForDay(day: number): ExpandedCourse[] {
    return this.expanded.filter((course: ExpandedCourse) => course.weekday === day);
  }

  private openCourseSheet(course: ExpandedCourse): void {
    this.selectedCourse = course;
    this.showCourseSheet = true;
  }

  private addCourse(): void {
    if (this.semester !== null) {
      this.nav.onAddCourse(this.semester.id);
    } else {
      this.nav.onOpenSemester();
    }
  }

  private addWeeksHint(): string {
    return this.semester === null ? '' : `${this.semester.totalWeeks} 周`;
  }

  @Builder
  dayHeader(index: number) {
    Column({ space: 3 }) {
      Text(weekdayLabel(index + 1).replace('周', ''))
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(index === this.todayIndex() ? AppTheme.BRAND : AppTheme.TEXT_SECONDARY)
      Text(this.dateLabel(index))
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(index === this.todayIndex() ? AppTheme.BRAND : AppTheme.TEXT_TERTIARY)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .backgroundColor(index === this.todayIndex() ? '#1A0A59F7' : Color.Transparent)
        .borderRadius(8)
    }
    .layoutWeight(1)
    .height(48)
    .justifyContent(FlexAlign.Center)
  }

  private isPastCourse(course: ExpandedCourse): boolean {
    if (this.semester === null) {
      return false;
    }
    const now: Date = new Date();
    const today: Date = new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
    const currentWeek: number = weekOf(this.semester.startDate, today);
    if (this.week < currentWeek) {
      return true;
    }
    if (this.week > currentWeek) {
      return false;
    }
    const todayWeekday: number = (today.getUTCDay() + 6) % 7 + 1;
    if (course.weekday < todayWeekday) {
      return true;
    }
    if (course.weekday > todayWeekday) {
      return false;
    }
    const endIndex: number = Math.min(course.endPeriod - 1, DEFAULT_PERIOD_TIMES.length - 1);
    if (endIndex < 0) {
      return false;
    }
    const endParts: string[] = DEFAULT_PERIOD_TIMES[endIndex][1].split(':');
    const endMinutes: number = Number.parseInt(endParts[0], 10) * 60 +
      Number.parseInt(endParts[1], 10);
    return now.getHours() * 60 + now.getMinutes() >= endMinutes;
  }

  private courseBackground(course: ExpandedCourse): string {
    return this.isPastCourse(course) ? '#ECEFF1' : CoursePalette.background(course.colorKey);
  }

  private courseForeground(course: ExpandedCourse): string {
    return this.isPastCourse(course) ? '#9AA1A8' : CoursePalette.foreground(course.colorKey);
  }

  @Builder
  courseBlock(course: ExpandedCourse) {
    Column({ space: 1 }) {
      Text(course.name)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.courseForeground(course))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(course.room.length > 0 ? course.room : '未填写教室')
        .fontSize(9)
        .fontColor(this.courseForeground(course))
        .opacity(0.82)
        .maxLines(1)
      if (course.teacher.length > 0) {
        Text(course.teacher)
          .fontSize(9)
          .fontColor(this.courseForeground(course))
          .opacity(0.72)
          .maxLines(1)
      }
      if (this.showCourseContent && course.content.length > 0) {
        Text(course.content)
          .fontSize(8)
          .fontColor(this.courseForeground(course))
          .opacity(0.7)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (course.isException) {
        Text('调整')
          .fontSize(8)
          .fontColor(this.courseForeground(course))
          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
          .border({ width: 0.5, color: this.courseForeground(course) })
          .borderRadius(5)
      }
    }
    .width('100%')
    .height((course.endPeriod - course.startPeriod + 1) * this.rowHeight - 6)
    .padding(5)
    .backgroundColor(this.courseBackground(course))
    .borderRadius(10)
    .border({ width: 0.5, color: '#66FFFFFF' })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .position({ x: 0, y: (course.startPeriod - 1) * this.rowHeight + 3 })
    .onClick(() => this.openCourseSheet(course))
  }

  @Builder
  dayColumn(day: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height(DEFAULT_PERIOD_TIMES.length * this.rowHeight)
        .onClick(() => this.addCourse())

      Divider()
        .width('100%')
        .strokeWidth(1)
        .color(AppTheme.DIVIDER)
        .opacity(0.6)
        .position({ x: 0, y: 4 * this.rowHeight })

      ForEach(this.coursesForDay(day), (course: ExpandedCourse) => {
        this.courseBlock(course)
      }, (course: ExpandedCourse) => `${course.courseId}-${course.exceptionId}`)
    }
    .layoutWeight(1)
    .height(DEFAULT_PERIOD_TIMES.length * this.rowHeight)
    .padding({ left: 2, right: 2 })
    .clip(false)
  }

  @Builder
  courseSheetBuilder() {
    CourseSheet({
      course: this.selectedCourse,
      week: this.week,
      onEdit: () => {
        this.showCourseSheet = false;
        if (this.semester !== null && this.selectedCourse !== null) {
          this.nav.onEditCourse(this.semester.id, this.selectedCourse.courseId);
        }
      },
      onAddMakeup: () => {
        if (this.semester !== null && this.selectedCourse !== null) {
          this.nav.onAddMakeup(this.semester.id, this.selectedCourse.courseId, this.week);
        }
        this.showCourseSheet = false;
      },
      onChanged: () => this.loadAll(),
      onClose: () => {
        this.showCourseSheet = false;
      }
    })
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: AppTheme.SPACE_MD }) {
        Row({ space: AppTheme.SPACE_SM }) {
          Row({ space: 4 }) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(15)
                .fontColor([this.semester !== null && this.week > 1 ? AppTheme.TEXT_PRIMARY : AppTheme.TEXT_TERTIARY])
            }
            .width(30)
            .height(30)
            .padding(0)
            .backgroundColor(AppTheme.CARD_BG)
            .enabled(this.semester !== null && this.week > 1)
            .onClick(() => this.previousWeek())

            Text(this.semester === null ? $r('app.string.semester_unset') : $r('app.string.week_label', this.week))
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.TEXT_PRIMARY)
              .width(118)
              .maxLines(1)
              .textAlign(TextAlign.Center)

            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(15)
                .fontColor([this.semester !== null && this.week < (this.semester.totalWeeks)
                  ? AppTheme.TEXT_PRIMARY : AppTheme.TEXT_TERTIARY])
            }
            .width(30)
            .height(30)
            .padding(0)
            .backgroundColor(AppTheme.CARD_BG)
            .enabled(this.semester !== null && this.week < this.semester.totalWeeks)
            .onClick(() => this.nextWeek())
          }

          Column({ space: 2 }) {
            Text(this.rangeLabel())
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_SECONDARY)
            Text(this.addWeeksHint())
              .fontSize(9)
              .fontColor(AppTheme.TEXT_TERTIARY)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(20)
            .fontColor([AppTheme.TEXT_PRIMARY])
            .padding(6)
            .onClick(() => this.addCourse())
        }
        .width('100%')

        if (this.conflicts.length > 0) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
              .fontSize(14)
              .fontColor(['#B26A00'])
            Text(`本周有 ${this.conflicts.length} 处课程冲突`)
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor('#B26A00')
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor('#1FB26A00')
          .borderRadius(10)
        }

        if (this.semester === null) {
          Column({ space: AppTheme.SPACE_MD }) {
            SymbolGlyph($r('sys.symbol.calendar'))
              .fontSize(36)
              .fontColor([AppTheme.BRAND])
            Text($r('app.string.timetable_no_semester_title'))
              .fontSize(AppTheme.FONT_HEADING)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.TEXT_PRIMARY)
            Text($r('app.string.timetable_no_semester_desc'))
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
            Button($r('app.string.today_create_semester'))
              .height(38)
              .onClick(() => this.nav.onOpenSemester())
          }
          .width('100%')
          .padding(AppTheme.SPACE_XL)
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(AppTheme.CARD_RADIUS)
          .alignItems(HorizontalAlign.Center)
        } else {
          Column({ space: 0 }) {
            Row() {
              Text('')
                .width(this.timeColumnWidth)
              ForEach([0, 1, 2, 3, 4, 5, 6], (index: number) => {
                this.dayHeader(index)
              }, (index: number) => `header-${index}`)
            }
            .width('100%')

            Row() {
              Column() {
                ForEach(DEFAULT_PERIOD_TIMES, (time: string[], index: number) => {
                  Column({ space: 1 }) {
                    Text(`${index + 1}`)
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(AppTheme.TEXT_TERTIARY)
                    Text(time[0])
                      .fontSize(8)
                      .fontColor(AppTheme.TEXT_TERTIARY)
                      .opacity(0.75)
                  }
                  .width('100%')
                  .height(this.rowHeight)
                  .justifyContent(FlexAlign.Center)
                }, (time: string[], index: number) => `time-${index}`)
              }
              .width(this.timeColumnWidth)

              ForEach([1, 2, 3, 4, 5, 6, 7], (day: number) => {
                this.dayColumn(day)
              }, (day: number) => `column-${day}`)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)

            if (this.expanded.length === 0) {
              Text($r('app.string.timetable_empty_title'))
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_TERTIARY)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: AppTheme.SPACE_MD })
            }
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding({
        left: AppTheme.PAGE_PADDING,
        right: AppTheme.PAGE_PADDING,
        top: AppTheme.TALL_PAGE_TOP_INSET + 20,
        bottom: AppTheme.CONTENT_BOTTOM_INSET
      })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG)
    .scrollBar(BarState.Off)
    .onAppear(() => {
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    })
    .bindSheet(this.showCourseSheet, this.courseSheetBuilder(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
      backgroundColor: AppTheme.SHEET_BG,
      radius: { topLeft: 32, topRight: 32, bottomLeft: 0, bottomRight: 0 },
      onDisappear: () => {
        this.showCourseSheet = false;
      }
    })
  }
}
