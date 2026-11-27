import { common } from '@kit.AbilityKit';
import { AppTheme } from '../../common/Theme';
import { AppNavActions } from '../../common/AppNavActions';
import { CoursePalette } from '../../common/CoursePalette';
import { CourseSheet } from '../../components/CourseSheet';
import {
  Course,
  CourseException,
  Event,
  ExpandedCourse,
  Semester,
  weekdayLabel
} from '../../domain/model/TimetableModels';
import { DEFAULT_PERIOD_TIMES } from '../../domain/model/Periods';
import { coursesOnDate, isCourseEndedOn, todayIso, weekOf, parseIsoDate } from '../../domain/timetable/TimetableEngine';
import { contentSignature } from '../../common/RenderKey';
import { TimetableRepository } from '../../data/TimetableRepository';
import { WidgetSnapshotService } from '../../services/widget/WidgetSnapshotService';

@Component
export struct TodayPage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  nav: AppNavActions = new AppNavActions();
  @StorageLink('timetableRevision') @Watch('onRevisionChange') revision: number = 0;
  @StorageLink('clockTick') @Watch('onClockTick') clockTick: number = 0;
  @State semester: Semester | null = null;
  @State courses: ExpandedCourse[] = [];
  @State dbEvents: Event[] = [];
  @State todayWeek: number = 0;
  @State loading: boolean = true;
  @State selectedCourse: ExpandedCourse | null = null;
  @State showCourseSheet: boolean = false;
  @State nowMs: number = Date.now();
  private dayAnchor: string = '';

  aboutToAppear(): void {
    this.dayAnchor = this.localDayKey(new Date());
    this.load();
  }

  aboutToDisappear(): void {
    this.dayAnchor = '';
  }

  private localDayKey(date: Date): string {
    return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
  }

  private onClockTick(): void {
    const now: Date = new Date();
    this.nowMs = now.getTime();
    const key: string = this.localDayKey(now);
    if (key !== this.dayAnchor) {
      this.dayAnchor = key;
      this.load();
    }
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
        this.dbEvents = [];
        this.todayWeek = 0;
        return;
      }
      this.dbEvents = await TimetableRepository.listEvents(this.context(), semester.id);
      const today: Date = new Date();
      const date: Date = new Date(Date.UTC(today.getFullYear(), today.getMonth(), today.getDate()));
      this.todayWeek = weekOf(semester.startDate, date);
      if (this.todayWeek < 1 || this.todayWeek > semester.totalWeeks) {
        this.courses = [];
        return;
      }
      const allCourses: Course[] = await TimetableRepository.listCourses(this.context(), semester.id);
      const exceptions: CourseException[] =
        await TimetableRepository.listExceptions(this.context(), semester.id);
      this.courses = coursesOnDate(allCourses, exceptions, semester.startDate, date, semester.totalWeeks);
      this.courses.sort((a: ExpandedCourse, b: ExpandedCourse) => a.startPeriod - b.startPeriod);
    } catch (error) {
      this.courses = [];
      this.dbEvents = [];
    } finally {
      this.loading = false;
      WidgetSnapshotService.write(this.context());
    }
  }

  private dateLabel(): string {
    const today: Date = new Date(this.nowMs);
    return `${today.getMonth() + 1}月${today.getDate()}日`;
  }

  private weekdayLabelToday(): string {
    const labels: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
    return labels[new Date(this.nowMs).getDay()];
  }

  private termLabel(): string {
    if (this.semester === null) {
      return '未设置学期';
    }
    if (this.todayWeek < 1) {
      return '学期未开始';
    }
    if (this.todayWeek > this.semester.totalWeeks) {
      return '学期已结束';
    }
    return `第 ${this.todayWeek} 周`;
  }

  private timeLabel(course: ExpandedCourse): string {
    const index: number = course.startPeriod - 1;
    return index >= 0 && index < DEFAULT_PERIOD_TIMES.length ? DEFAULT_PERIOD_TIMES[index][0] : '';
  }

  private minutes(value: string): number {
    const parts: string[] = value.split(':');
    if (parts.length !== 2) {
      return 0;
    }
    return Number.parseInt(parts[0], 10) * 60 + Number.parseInt(parts[1], 10);
  }

  private todayExams(): Event[] {
    const today: Date = new Date(this.nowMs);
    const start: number = Date.UTC(today.getFullYear(), today.getMonth(), today.getDate());
    const end: number = start + 86400000;
    const events: Event[] = this.dbEvents.filter((event: Event) =>
      event.startTime >= start && event.startTime < end);
    events.sort((a: Event, b: Event) => a.startTime - b.startTime);
    return events;
  }

  private examTime(event: Event): string {
    const start: Date = new Date(event.startTime);
    const end: Date = new Date(event.endTime);
    const pad = (value: number): string => `${value}`.padStart(2, '0');
    return `${pad(start.getUTCHours())}:${pad(start.getUTCMinutes())}–${pad(end.getUTCHours())}:${pad(end.getUTCMinutes())}`;
  }

  private nextCourse(): ExpandedCourse | null {
    const now: Date = new Date(this.nowMs);
    const current: number = now.getHours() * 60 + now.getMinutes();
    for (const course of this.courses) {
      const index: number = course.endPeriod - 1;
      if (index >= 0 && index < DEFAULT_PERIOD_TIMES.length) {
        if (this.minutes(DEFAULT_PERIOD_TIMES[index][1]) > current) {
          return course;
        }
      }
    }
    return null;
  }

  private timeRange(course: ExpandedCourse): string {
    const start: number = course.startPeriod - 1;
    const end: number = course.endPeriod - 1;
    if (start < 0 || end < 0 || start >= DEFAULT_PERIOD_TIMES.length || end >= DEFAULT_PERIOD_TIMES.length) {
      return `${course.startPeriod}–${course.endPeriod} 节`;
    }
    return `${DEFAULT_PERIOD_TIMES[start][0]}–${DEFAULT_PERIOD_TIMES[end][1]}`;
  }

  private isEnded(course: ExpandedCourse): boolean {
    const now: Date = new Date(this.nowMs);
    const today: Date = new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
    return isCourseEndedOn(today, course.endPeriod, now);
  }

  private courseBackground(course: ExpandedCourse): string {
    return this.isEnded(course)
      ? CoursePalette.PAST_BACKGROUND : CoursePalette.background(course.colorKey);
  }

  private courseForeground(course: ExpandedCourse): string {
    return this.isEnded(course)
      ? CoursePalette.PAST_FOREGROUND : CoursePalette.foreground(course.colorKey);
  }

  /** 与课表页一致：key 带上房间/教师/时段与「已结束」状态，否则改课不刷新。 */
  private cardKey(course: ExpandedCourse): string {
    const signature: number = contentSignature([
      course.name, course.room, course.teacher,
      `${course.weekday}`, `${course.startPeriod}`, `${course.endPeriod}`,
      course.isException ? '1' : '0', this.isEnded(course) ? '1' : '0'
    ]);
    return `${course.courseId}-${course.week}-${signature}`;
  }

  private openCourse(course: ExpandedCourse): void {
    if (this.todayWeek >= 1) {
      this.selectedCourse = course;
      this.showCourseSheet = true;
    }
  }

  private eventBackground(event: Event): string {
    return event.category === 'EXAM' ? '#FBE4E1' : '#DCEBF5';
  }

  private eventForeground(event: Event): string {
    return event.category === 'EXAM' ? '#5C1712' : '#203B52';
  }

  private openEvent(event: Event): void {
    if (this.semester !== null) {
      this.nav.onAddEvent(this.semester.id, todayIso(), event.id);
    }
  }

  @Builder
  examCard(event: Event) {
    Row({ space: AppTheme.SPACE_MD }) {
      Column({ space: 2 }) {
        Text(this.examTime(event))
          .fontSize(AppTheme.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.eventForeground(event))
        Text(event.category === 'EXAM' ? '考试' : '日程')
          .fontSize(9)
          .fontColor(this.eventForeground(event))
          .opacity(0.72)
      }
      .width(64)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 3 }) {
        Text(event.title)
          .fontSize(AppTheme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.eventForeground(event))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${event.location.length > 0 ? event.location : '地点待定'}${event.note.length > 0 ? ' · ' + event.note : ''}`)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(this.eventForeground(event))
          .opacity(0.8)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .height(70)
    .padding({ left: AppTheme.CARD_PADDING, right: AppTheme.CARD_PADDING })
    .backgroundColor(this.eventBackground(event))
    .borderRadius(14)
    .onClick(() => this.openEvent(event))
  }

  @Builder
  courseCard(course: ExpandedCourse) {
    Row({ space: AppTheme.SPACE_MD }) {
      Column({ space: 2 }) {
        Text(this.timeLabel(course))
          .fontSize(AppTheme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.courseForeground(course))
        Text(`${course.startPeriod}–${course.endPeriod} 节`)
          .fontSize(9)
          .fontColor(this.courseForeground(course))
          .opacity(0.72)
      }
      .width(52)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 2 }) {
        Row({ space: 4 }) {
          Text(course.name)
            .fontSize(AppTheme.FONT_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.courseForeground(course))
            .maxLines(1)
            .layoutWeight(1)
          if (course.isException) {
            Text('调整')
              .fontSize(9)
              .fontColor(this.courseForeground(course))
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              .border({ width: 0.5, color: this.courseForeground(course) })
              .borderRadius(6)
          }
        }
        .width('100%')

        Text(`${course.room.length > 0 ? course.room : '未填写教室'}${course.teacher.length > 0 ? ' · ' + course.teacher : ''}`)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(this.courseForeground(course))
          .opacity(0.78)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .height(70)
    .padding({ left: AppTheme.CARD_PADDING, right: AppTheme.CARD_PADDING })
    .backgroundColor(this.courseBackground(course))
    .borderRadius(14)
    .onClick(() => this.openCourse(course))
  }

  @Builder
  courseSheetBuilder() {
    CourseSheet({
      course: this.selectedCourse,
      week: this.todayWeek,
      onEdit: () => {
        this.showCourseSheet = false;
        if (this.semester !== null && this.selectedCourse !== null) {
          this.nav.onEditCourse(this.semester.id, this.selectedCourse.courseId);
        }
      },
      onAddMakeup: () => {
        if (this.semester !== null && this.selectedCourse !== null) {
          this.nav.onAddMakeup(this.semester.id, this.selectedCourse.courseId, this.todayWeek);
        }
        this.showCourseSheet = false;
      },
      onChanged: () => this.load(),
      onClose: () => {
        this.showCourseSheet = false;
      }
    })
  }

  build() {
    Scroll() {
      Column({ space: AppTheme.SPACE_LG }) {
        Column({ space: AppTheme.SPACE_XS }) {
          Text(this.dateLabel())
            .fontSize(AppTheme.FONT_DISPLAY)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TEXT_PRIMARY)
          Row({ space: AppTheme.SPACE_XS }) {
            Text(this.weekdayLabelToday())
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_SECONDARY)
            Text('·')
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_TERTIARY)
            Text(this.termLabel())
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_SECONDARY)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        if (this.semester === null) {
          Column({ space: AppTheme.SPACE_MD }) {
            SymbolGlyph($r('sys.symbol.calendar'))
              .fontSize(36)
              .fontColor([this.brandTextColor])
            Text($r('app.string.today_no_semester_title'))
              .fontSize(AppTheme.FONT_HEADING)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.TEXT_PRIMARY)
            Text($r('app.string.today_no_semester_desc'))
              .fontSize(AppTheme.FONT_BODY - 1)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
              .lineHeight(20)
            Button($r('app.string.today_create_semester'))
              .height(40)
              .onClick(() => this.nav.onOpenSync())
          }
          .width('100%')
          .padding(AppTheme.SPACE_XL)
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(AppTheme.CARD_RADIUS)
          .alignItems(HorizontalAlign.Center)
        } else if (this.courses.length > 0) {
          Column({ space: AppTheme.SPACE_SM }) {
            Row() {
              Text($r('app.string.today_courses'))
                .fontSize(AppTheme.FONT_TITLE)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.TEXT_PRIMARY)
              Blank()
              Text(`${this.courses.length} 门`)
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_SECONDARY)
            }
            .width('100%')

            ForEach(this.courses, (course: ExpandedCourse) => {
              this.courseCard(course)
            }, (course: ExpandedCourse) => this.cardKey(course))
          }
          .width('100%')
        } else {
          Column({ space: AppTheme.SPACE_MD }) {
            SymbolGlyph($r('sys.symbol.clock'))
              .fontSize(36)
              .fontColor([this.brandTextColor])
            Text($r('app.string.today_empty_title'))
              .fontSize(AppTheme.FONT_HEADING)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.TEXT_PRIMARY)
            Text($r('app.string.today_empty_desc'))
              .fontSize(AppTheme.FONT_BODY - 1)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
              .lineHeight(20)
            Row({ space: AppTheme.SPACE_MD }) {
              Button($r('app.string.today_add_course'))
                .fontSize(AppTheme.FONT_BODY)
                .height(38)
                .onClick(() => {
                  if (this.semester !== null) {
                    this.nav.onAddCourse(this.semester.id);
                  }
                })
            }
            .margin({ top: AppTheme.SPACE_XS })
          }
          .width('100%')
          .padding(AppTheme.SPACE_XL)
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(AppTheme.CARD_RADIUS)
          .alignItems(HorizontalAlign.Center)
        }

        if (this.todayExams().length > 0) {
          Column({ space: AppTheme.SPACE_SM }) {
            Row() {
              Text('今日日程')
                .fontSize(AppTheme.FONT_TITLE)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.TEXT_PRIMARY)
              Blank()
              Text(`${this.todayExams().length} 项`)
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_SECONDARY)
            }
            .width('100%')
            ForEach(this.todayExams(), (event: Event) => {
              this.examCard(event)
            }, (event: Event) => event.id)
          }
          .width('100%')
        }

        Column({ space: AppTheme.SPACE_SM }) {
          Row() {
            Text($r('app.string.today_next_title'))
              .fontSize(AppTheme.FONT_TITLE)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.TEXT_PRIMARY)
            Blank()
            Text(this.nextCourse() !== null
              ? this.timeRange(this.nextCourse() as ExpandedCourse)
              : $r('app.string.today_next_empty'))
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_SECONDARY)
          }
          .width('100%')

          if (this.nextCourse() !== null) {
            Text((this.nextCourse() as ExpandedCourse).name)
              .fontSize(AppTheme.FONT_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.TEXT_PRIMARY)
              .width('100%')
            Text(`${(this.nextCourse() as ExpandedCourse).room.length > 0 ? (this.nextCourse() as ExpandedCourse).room : '未填写教室'}${(this.nextCourse() as ExpandedCourse).teacher.length > 0 ? ' · ' + (this.nextCourse() as ExpandedCourse).teacher : ''}`)
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .width('100%')
          } else {
            Text($r('app.string.today_next_hint'))
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .width('100%')
          }
        }
        .width('100%')
        .padding(AppTheme.CARD_PADDING)
        .backgroundColor(AppTheme.CARD_BG)
        .borderRadius(AppTheme.CARD_RADIUS)
      }
      .width('100%')
      .padding({
        left: AppTheme.PAGE_PADDING,
        right: AppTheme.PAGE_PADDING,
        top: AppTheme.PAGE_PADDING,
        bottom: AppTheme.CONTENT_BOTTOM_INSET
      })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .backgroundColor(AppTheme.BG)
    .scrollBar(BarState.Off)
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
