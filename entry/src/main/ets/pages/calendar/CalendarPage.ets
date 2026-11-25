import { common } from '@kit.AbilityKit';
import { DividerMode, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { AppNavActions } from '../../common/AppNavActions';
import { CoursePalette } from '../../common/CoursePalette';
import { CourseSheet } from '../../components/CourseSheet';
import { ImmersiveMaterial } from '../../common/ImmersiveMaterial';
import { RoundIconButton } from '../../components/RoundIconButton';
import {
  Course,
  CourseException,
  Event,
  ExpandedCourse,
  Semester
} from '../../domain/model/TimetableModels';
import { DEFAULT_PERIOD_TIMES } from '../../domain/model/Periods';
import { expandWeek, isoDate, parseIsoDate, weekOf } from '../../domain/timetable/TimetableEngine';
import { TimetableRepository } from '../../data/TimetableRepository';
import { AgendaItem, AgendaKind, agendaForDate } from '../../domain/agenda/AgendaEngine';

interface CalendarCell {
  day: number;
  inMonth: boolean;
  date: Date;
}

@Component
export struct CalendarPage {
  nav: AppNavActions = new AppNavActions();
  @StorageLink('timetableRevision') @Watch('onRevisionChange') revision: number = 0;
  @StorageLink('immersiveEnabled') immersiveEnabled: boolean = true;
  @StorageLink('handednessEnabled') handednessEnabled: boolean = true;
  @State semester: Semester | null = null;
  @State monthOffset: number = 0;
  @State selectedDay: number = new Date().getDate();
  @State mode: string = 'month';
  @State courses: Course[] = [];
  @State selectedCourse: ExpandedCourse | null = null;
  @State showSheet: boolean = false;
  @State sheetMode: string = 'course';
  @State exceptions: CourseException[] = [];
  @State dbEvents: Event[] = [];
  private fabController: HdsTabsController = new HdsTabsController();
  private weekdays: string[] = ['一', '二', '三', '四', '五', '六', '日'];
  private weekdayShort: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  aboutToAppear(): void {
    this.load();
  }

  onRevisionChange(): void {
    this.load();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async load(): Promise<void> {
    try {
      const semester: Semester | null = await TimetableRepository.getCurrentSemester(this.context());
      this.semester = semester;
      if (semester === null) {
        this.courses = [];
        this.exceptions = [];
        this.dbEvents = [];
        return;
      }
      this.courses = await TimetableRepository.listCourses(this.context(), semester.id);
      this.exceptions = await TimetableRepository.listExceptions(this.context(), semester.id);
      this.dbEvents = await TimetableRepository.listEvents(this.context(), semester.id);
    } catch (error) {
      this.courses = [];
      this.exceptions = [];
    }
  }

  private currentMonth(): Date {
    const now: Date = new Date();
    return new Date(now.getFullYear(), now.getMonth() + this.monthOffset, 1);
  }

  private monthLabel(): string {
    const month: Date = this.currentMonth();
    return `${month.getFullYear()}年${month.getMonth() + 1}月`;
  }

  private weeks(): CalendarCell[][] {
    const month: Date = this.currentMonth();
    const firstDay: Date = new Date(Date.UTC(month.getFullYear(), month.getMonth(), 1));
    const firstWeekday: number = (firstDay.getUTCDay() + 6) % 7;
    const daysInMonth: number = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
    const previousMonthDays: number = new Date(month.getFullYear(), month.getMonth(), 0).getDate();
    const cells: CalendarCell[] = [];
    for (let i = firstWeekday; i > 0; i--) {
      const day: number = previousMonthDays - i + 1;
      cells.push({
        day: day,
        inMonth: false,
        date: new Date(Date.UTC(month.getFullYear(), month.getMonth() - 1, day))
      });
    }
    for (let day = 1; day <= daysInMonth; day++) {
      cells.push({
        day: day,
        inMonth: true,
        date: new Date(Date.UTC(month.getFullYear(), month.getMonth(), day))
      });
    }
    let nextDay: number = 1;
    while (cells.length % 7 !== 0) {
      cells.push({
        day: nextDay,
        inMonth: false,
        date: new Date(Date.UTC(month.getFullYear(), month.getMonth() + 1, nextDay))
      });
      nextDay++;
    }
    const result: CalendarCell[][] = [];
    for (let i = 0; i < cells.length; i += 7) {
      result.push(cells.slice(i, i + 7));
    }
    return result;
  }

  private selectedDate(): Date {
    const month: Date = this.currentMonth();
    const lastDay: number = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
    const day: number = Math.min(this.selectedDay, lastDay);
    return new Date(Date.UTC(month.getFullYear(), month.getMonth(), day));
  }

  private selectedDateLabel(): string {
    const date: Date = this.selectedDate();
    return `${date.getUTCMonth() + 1}月${date.getUTCDate()}日 ${this.weekdayShort[(date.getUTCDay() + 6) % 7]}`;
  }

  private coursesForDate(date: Date): ExpandedCourse[] {
    if (this.semester === null) {
      return [];
    }
    const week: number = weekOf(this.semester.startDate, date);
    if (week < 1 || week > this.semester.totalWeeks) {
      return [];
    }
    const weekday: number = (date.getUTCDay() + 6) % 7 + 1;
    const expanded: ExpandedCourse[] = expandWeek(this.courses, this.exceptions, week);
    const dayCourses: ExpandedCourse[] =
      expanded.filter((course: ExpandedCourse) => course.weekday === weekday);
    dayCourses.sort((a: ExpandedCourse, b: ExpandedCourse) => a.startPeriod - b.startPeriod);
    return dayCourses;
  }

  private selectedWeek(): number {
    if (this.semester === null) {
      return 0;
    }
    return weekOf(this.semester.startDate, this.selectedDate());
  }

  private events(): ExpandedCourse[] {
    return this.coursesForDate(this.selectedDate());
  }

  private examsForDate(date: Date): Event[] {
    const start: number = date.getTime();
    const end: number = start + 86400000;
    return this.dbEvents.filter((event: Event) =>
      event.startTime >= start && event.startTime < end);
  }

  private selectedExams(): Event[] {
    return this.examsForDate(this.selectedDate());
  }

  private agenda(): AgendaItem[] {
    if (this.semester === null) {
      return [];
    }
    return agendaForDate(this.courses, this.exceptions, this.dbEvents, this.semester, this.selectedDate());
  }

  private eventTime(event: Event): string {
    const start: Date = new Date(event.startTime);
    const end: Date = new Date(event.endTime);
    const pad = (value: number): string => `${value}`.padStart(2, '0');
    return `${pad(start.getUTCHours())}:${pad(start.getUTCMinutes())}–${pad(end.getUTCHours())}:${pad(end.getUTCMinutes())}`;
  }

  private isTodayDate(date: Date): boolean {
    const now: Date = new Date();
    return date.getUTCFullYear() === now.getFullYear()
      && date.getUTCMonth() === now.getMonth()
      && date.getUTCDate() === now.getDate();
  }

  private hasCoursesOn(date: Date): boolean {
    return this.coursesForDate(date).length > 0;
  }

  private hasExamOn(date: Date): boolean {
    const key: string = isoDate(date);
    return this.dbEvents.some((event: Event) => isoDate(new Date(event.startTime)) === key);
  }

  private previousMonth(): void {
    this.monthOffset = this.monthOffset - 1;
    this.selectedDay = 1;
  }

  private nextMonth(): void {
    this.monthOffset = this.monthOffset + 1;
    this.selectedDay = 1;
  }

  private weekStart(): Date {
    const selected: Date = this.selectedDate();
    const offset: number = (selected.getUTCDay() + 6) % 7;
    return new Date(Date.UTC(selected.getUTCFullYear(), selected.getUTCMonth(),
      selected.getUTCDate() - offset));
  }

  private weekDay(index: number): Date {
    const start: Date = this.weekStart();
    return new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate() + index));
  }

  private weekDate(index: number): string {
    const date: Date = this.weekDay(index);
    return `${date.getUTCMonth() + 1}/${date.getUTCDate()}`;
  }

  private addCourse(): void {
    this.sheetMode = 'add';
    this.showSheet = true;
  }

  private confirmAddCourse(): void {
    this.showSheet = false;
    if (this.semester !== null) {
      this.nav.onAddCourse(this.semester.id);
    } else {
      this.nav.onOpenSemester();
    }
  }

  private openCourse(course: ExpandedCourse): void {
    this.selectedCourse = course;
    this.sheetMode = 'course';
    this.showSheet = true;
  }

  private timeLabel(course: ExpandedCourse): string {
    const index: number = course.startPeriod - 1;
    if (index < 0 || index >= DEFAULT_PERIOD_TIMES.length) {
      return '';
    }
    return DEFAULT_PERIOD_TIMES[index][0];
  }

  @Builder
  modeButton(label: ResourceStr, value: string) {
    Text(label)
      .fontSize(AppTheme.FONT_CAPTION)
      .fontColor(this.mode === value ? AppTheme.TEXT_PRIMARY : AppTheme.TEXT_SECONDARY)
      .fontWeight(this.mode === value ? FontWeight.Medium : FontWeight.Normal)
      .height(32)
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.mode === value ? AppTheme.BG : Color.Transparent)
      .borderRadius(16)
      .textAlign(TextAlign.Center)
      .onClick(() => {
        this.mode = value;
      })
  }

  @Builder
  dayCell(cell: CalendarCell) {
    Column({ space: 2 }) {
      Text(`${cell.day}`)
        .fontSize(AppTheme.FONT_CHIP)
        .fontColor(
          cell.inMonth && cell.day === this.selectedDay
            ? AppTheme.ON_BRAND
            : (cell.inMonth && this.isTodayDate(cell.date) ? AppTheme.BRAND
              : (cell.inMonth ? AppTheme.TEXT_PRIMARY : AppTheme.TEXT_TERTIARY))
        )
        .width(28)
        .height(28)
        .textAlign(TextAlign.Center)
        .backgroundColor(cell.inMonth && cell.day === this.selectedDay ? AppTheme.BRAND : Color.Transparent)
        .borderRadius(14)
      Row({ space: 3 }) {
        if (this.hasCoursesOn(cell.date)) {
          Column()
            .width(4)
            .height(4)
            .borderRadius(2)
            .backgroundColor(AppTheme.BRAND)
        }
        if (this.hasExamOn(cell.date)) {
          Column()
            .width(4)
            .height(4)
            .borderRadius(2)
            .backgroundColor('#E96565')
        }
      }
      .height(4)
    }
    .layoutWeight(1)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      if (cell.inMonth) {
        this.selectedDay = cell.day;
      } else {
        const targetMonth: Date = new Date(cell.date.getUTCFullYear(), cell.date.getUTCMonth(), 1);
        const baseMonth: Date = new Date();
        this.monthOffset = (targetMonth.getFullYear() - baseMonth.getFullYear()) * 12 +
          targetMonth.getMonth() - baseMonth.getMonth();
        this.selectedDay = cell.day;
        this.mode = 'month';
      }
    })
  }

  @Builder
  eventCard(event: ExpandedCourse) {
    Row({ space: AppTheme.SPACE_MD }) {
      Column({ space: 2 }) {
        Text(this.timeLabel(event))
          .fontSize(AppTheme.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(CoursePalette.foreground(event.colorKey))
        Text(`${event.startPeriod}–${event.endPeriod} 节`)
          .fontSize(9)
          .fontColor(CoursePalette.foreground(event.colorKey))
          .opacity(0.7)
      }
      .width(50)
      .alignItems(HorizontalAlign.Start)
      Column({ space: 2 }) {
        Text(event.name)
          .fontSize(AppTheme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(CoursePalette.foreground(event.colorKey))
          .maxLines(1)
        Text(`${event.room.length > 0 ? event.room : '未填写教室'}${event.teacher.length > 0 ? ' · ' + event.teacher : ''}`)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(CoursePalette.foreground(event.colorKey))
          .opacity(0.8)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .height(64)
    .padding({ left: AppTheme.CARD_PADDING, right: AppTheme.CARD_PADDING })
    .backgroundColor(CoursePalette.background(event.colorKey))
    .borderRadius(14)
    .onClick(() => this.openCourse(event))
  }

  @Builder
  examCard(event: Event) {
    Row({ space: AppTheme.SPACE_MD }) {
      Column({ space: 2 }) {
        Text(this.eventTime(event))
          .fontSize(AppTheme.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(event.category === 'EXAM' ? '#A12B22' : '#315F7E')
        Text(event.category === 'EXAM' ? '考试' : '日程')
          .fontSize(9)
          .fontColor(event.category === 'EXAM' ? '#A12B22' : '#315F7E')
          .opacity(0.7)
      }
      .width(70)
      .alignItems(HorizontalAlign.Start)
      Column({ space: 2 }) {
        Text(event.title)
          .fontSize(AppTheme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(event.category === 'EXAM' ? '#5C1712' : '#203B52')
          .maxLines(1)
        Text(`${event.location.length > 0 ? event.location : '地点待定'}${event.note.length > 0 ? ' · ' + event.note : ''}`)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(event.category === 'EXAM' ? '#7B3028' : '#3F5A72')
          .opacity(0.8)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .height(64)
    .padding({ left: AppTheme.CARD_PADDING, right: AppTheme.CARD_PADDING })
    .backgroundColor(event.category === 'EXAM' ? '#FBE4E1' : '#DCEBF5')
    .borderRadius(14)
    .onClick(() => {
      if (event.category !== 'EXAM' && this.semester !== null) {
        this.nav.onAddEvent(this.semester.id, isoDate(this.selectedDate()), event.id);
      }
    })
  }

  @Builder
  fabContent() {
    Stack() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(24)
        .fontColor([AppTheme.BRAND])
    }
    .width(56)
    .height(56)
    .borderRadius(28)
    .backgroundColor(AppTheme.FAB_BG)
    .border({ width: 0.5, color: '#80FFFFFF' })
    .shadow({ radius: 18, color: '#24000000', offsetY: 6 })
    .align(Alignment.Center)
  }

  @Builder
  courseSheetBuilder() {
    CourseSheet({
      course: this.selectedCourse,
      week: this.selectedWeek(),
      onEdit: () => {
        this.showSheet = false;
        if (this.semester !== null && this.selectedCourse !== null) {
          this.nav.onEditCourse(this.semester.id, this.selectedCourse.courseId);
        }
      },
      onAddMakeup: () => {
        if (this.semester !== null && this.selectedCourse !== null) {
          this.nav.onAddMakeup(this.semester.id, this.selectedCourse.courseId, this.selectedWeek());
        }
        this.showSheet = false;
      },
      onChanged: () => this.load(),
      onClose: () => {
        this.showSheet = false;
      }
    })
  }

  @Builder
  addActionRow(icon: Resource, title: ResourceStr, desc: ResourceStr, action: () => void) {
    Row({ space: 14 }) {
      Stack() {
        SymbolGlyph(icon)
          .fontSize(21)
          .fontColor([AppTheme.BRAND])
      }
      .width(42)
      .height(42)
      .borderRadius(14)
      .backgroundColor('#1A0A59F7')
      Column({ space: 3 }) {
        Text(title)
          .fontSize(AppTheme.FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
        Text(desc)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([AppTheme.TEXT_TERTIARY])
    }
    .width('100%')
    .height(68)
    .padding({ left: 14, right: 14 })
    .backgroundColor(AppTheme.SHEET_CARD_BG)
    .borderRadius(20)
    .onClick(action)
  }

  @Builder
  addSheetBuilder() {
    Column({ space: AppTheme.SPACE_SM }) {
      Row() {
        Column()
          .width(36)
          .height(4)
          .borderRadius(2)
          .backgroundColor('#26000000')
      }
      .width('100%')
      .height(10)
      .justifyContent(FlexAlign.Center)
      Row() {
        Column({ space: 3 }) {
          Text($r('app.string.calendar_add_title'))
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TEXT_PRIMARY)
          Text('选择要添加的内容')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ bottom: AppTheme.SPACE_SM })
      this.addActionRow(
        $r('sys.symbol.calendar'),
        $r('app.string.today_add_course'),
        $r('app.string.calendar_add_course_desc'),
        () => this.confirmAddCourse()
      )
      this.addActionRow(
        $r('sys.symbol.clock'),
        $r('app.string.calendar_add_event'),
        $r('app.string.calendar_add_event_desc'),
        () => {
          this.showSheet = false;
          if (this.semester !== null) {
            this.nav.onAddEvent(this.semester.id, isoDate(this.selectedDate()), '');
          }
        }
      )
      this.addActionRow(
        $r('sys.symbol.arrow_clockwise'),
        $r('app.string.campus_sync'),
        $r('app.string.campus_sync_desc'),
        () => {
          this.showSheet = false;
          this.nav.onOpenSync();
        }
      )
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 4, bottom: AppTheme.SPACE_XXL })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  sheetBuilder() {
    if (this.sheetMode === 'add') {
      this.addSheetBuilder()
    } else {
      this.courseSheetBuilder()
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Scroll() {
        Column({ space: AppTheme.SPACE_LG }) {
          Row() {
            Column({ space: 2 }) {
              Text(this.monthLabel())
                .fontSize(AppTheme.FONT_DISPLAY)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppTheme.TEXT_PRIMARY)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Row({ space: 2 }) {
              this.modeButton($r('app.string.calendar_month'), 'month')
              this.modeButton($r('app.string.calendar_week'), 'week')
            }
            .padding(3)
            .backgroundColor(AppTheme.CARD_BG)
            .borderRadius(19)
          }
          .width('100%')

          Row() {
            RoundIconButton({
              icon: $r('sys.symbol.chevron_left'),
              onTap: () => this.previousMonth()
            })
            Blank()
            if (this.semester !== null) {
              Text(`${this.semester.name}`)
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_TERTIARY)
                .maxLines(1)
            }
            Blank()
            RoundIconButton({
              icon: $r('sys.symbol.chevron_right'),
              onTap: () => this.nextMonth()
            })
          }
          .width('100%')

          if (this.mode === 'month') {
            Column({ space: AppTheme.SPACE_XS }) {
              Row() {
                ForEach(this.weekdays, (day: string) => {
                  Text(day)
                    .layoutWeight(1)
                    .textAlign(TextAlign.Center)
                    .fontSize(AppTheme.FONT_TINY)
                    .fontColor(AppTheme.TEXT_SECONDARY)
                }, (day: string) => day)
              }
              .width('100%')

              ForEach(this.weeks(), (week: CalendarCell[], weekIndex: number) => {
                Row() {
                  ForEach(week, (cell: CalendarCell, dayIndex: number) => {
                    this.dayCell(cell)
                  }, (cell: CalendarCell, dayIndex: number) =>
                    `${this.monthLabel()}-${weekIndex}-${dayIndex}-${this.courses.length}-${this.dbEvents.length}-${this.selectedDay}`)
                }
                .width('100%')
              }, (week: CalendarCell[], weekIndex: number) =>
                `${this.monthLabel()}-week-${weekIndex}-${this.courses.length}-${this.dbEvents.length}`)
            }
            .width('100%')
            .padding({ left: AppTheme.SPACE_SM, right: AppTheme.SPACE_SM, top: AppTheme.SPACE_SM, bottom: AppTheme.SPACE_SM })
            .backgroundColor(AppTheme.CARD_BG)
            .borderRadius(AppTheme.CARD_RADIUS)
          } else {
            Row() {
              ForEach(this.weekdays, (day: string, index: number) => {
                Column({ space: 2 }) {
                  Text(this.weekdayShort[index])
                    .fontSize(AppTheme.FONT_TINY)
                    .fontColor(AppTheme.TEXT_SECONDARY)
                  Text(this.weekDate(index))
                    .fontSize(AppTheme.FONT_BODY)
                    .fontColor(AppTheme.TEXT_PRIMARY)
                  if (this.hasExamOn(this.weekDay(index))) {
                    Column()
                      .width(4)
                      .height(4)
                      .borderRadius(2)
                      .backgroundColor('#E96565')
                  } else {
                    Column().height(4)
                  }
                }
                .layoutWeight(1)
                .height(54)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  const date: Date = this.weekDay(index);
                  if (date.getUTCMonth() === this.currentMonth().getMonth()) {
                    this.selectedDay = date.getUTCDate();
                  }
                })
              }, (day: string, index: number) =>
                `${this.selectedDate().getTime()}-weekday-${index}-${this.dbEvents.length}`)
            }
            .width('100%')
            .padding(AppTheme.SPACE_SM)
            .backgroundColor(AppTheme.CARD_BG)
            .borderRadius(AppTheme.CARD_RADIUS)
          }

          Column({ space: AppTheme.SPACE_SM }) {
            Row() {
              Text(this.selectedDateLabel())
                .fontSize(AppTheme.FONT_TITLE)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.TEXT_PRIMARY)
              Blank()
              Text($r('app.string.calendar_event_count', this.agenda().length))
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_SECONDARY)
            }
            .width('100%')

            if (this.agenda().length > 0) {
              ForEach(this.agenda(), (item: AgendaItem) => {
                if (item.kind === AgendaKind.COURSE && item.course !== null) {
                  this.eventCard(item.course)
                } else if (item.event !== null) {
                  this.examCard(item.event)
                }
              }, (item: AgendaItem) => item.id)
            } else {
              Text(this.semester === null
                ? $r('app.string.today_no_semester_title') : $r('app.string.calendar_empty_title'))
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_TERTIARY)
                .width('100%')
                .padding(AppTheme.CARD_PADDING)
                .backgroundColor(AppTheme.CARD_BG)
                .borderRadius(AppTheme.CARD_RADIUS)
            }
          }
          .width('100%')
        }
        .width('100%')
        .padding({
          left: AppTheme.PAGE_PADDING,
          right: AppTheme.PAGE_PADDING,
          top: AppTheme.TALL_PAGE_TOP_INSET,
          bottom: 160
        })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .scrollBar(BarState.Off)

      HdsTabs({ controller: this.fabController }) {
        TabContent().tabBar(this.fabContent())
      }
      .barWidth(56)
      .barHeight(56)
      .barPosition(BarPosition.End)
      .barFloatingStyle({
        barSideMargin: 8,
        barBottomMargin: 12,
        adaptToHandedness: this.handednessEnabled,
        systemMaterialEffect: {
          materialType: ImmersiveMaterial.type(),
          materialLevel: ImmersiveMaterial.level()
        }
      })
      .onTabBarClick(() => {
        this.addCourse();
      })
      .width(80)
      .height(80)
      .margin({ right: 16, bottom: 92 })
      .divider({ mode: DividerMode.NONE })
      .clip(false)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .backgroundColor(AppTheme.BG)
    .bindSheet(this.showSheet, this.sheetBuilder(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
      backgroundColor: AppTheme.SHEET_BG,
      radius: { topLeft: 32, topRight: 32, bottomLeft: 0, bottomRight: 0 },
      onDisappear: () => {
        this.showSheet = false;
      }
    })
  }
}
