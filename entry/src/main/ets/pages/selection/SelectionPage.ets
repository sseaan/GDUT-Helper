import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { formatWeeks, weekdayLabel } from '../../domain/model/TimetableModels';
import { JxfwError, JxfwErrorKind } from '../../services/jxfw/JxfwModels';
import {
  SELECTION_QUEUE_REVISION_KEY,
  SelectionConflict,
  SelectionCourse,
  SelectionLesson,
  SelectionQueueItem,
  remainingSeats
} from '../../services/selection/SelectionModels';
import { SelectionService } from '../../services/selection/SelectionService';

/** 节次 + 周次归并后的展示行。 */
interface LessonRow {
  weekday: number;
  periods: number[];
  room: string;
  weeks: number[];
}

@Component
export struct SelectionPage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  @StorageLink(SELECTION_QUEUE_REVISION_KEY) @Watch('onQueueChange') queueRevision: number = 0;
  onOpenSync: () => void = () => {};
  onOpenTask: () => void = () => {};
  @State courses: SelectionCourse[] = [];
  @State queue: SelectionQueueItem[] = [];
  @State keyword: string = '';
  @State appliedKeyword: string = '';
  @State page: number = 1;
  @State hasMore: boolean = false;
  @State loading: boolean = true;
  @State appending: boolean = false;
  @State error: string = '';
  @State notice: string = '';
  @State showDetail: boolean = false;
  @State detail: SelectionCourse | null = null;
  @State detailLessons: SelectionLesson[] = [];
  @State detailConflicts: SelectionConflict[] = [];
  @State detailLoading: boolean = false;
  @State addingCode: string = '';

  aboutToAppear(): void {
    this.load(true);
    this.loadQueue();
  }

  onQueueChange(): void {
    this.loadQueue();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      // ignore
    }
  }

  private async loadQueue(): Promise<void> {
    try {
      this.queue = await SelectionService.queue(this.context());
    } catch (error) {
      this.queue = [];
    }
  }

  private async load(reset: boolean): Promise<void> {
    if (reset) {
      this.loading = true;
      this.page = 1;
      this.error = '';
    } else {
      this.appending = true;
    }
    try {
      const result = await SelectionService.loadCourses(this.page, this.appliedKeyword);
      const merged: SelectionCourse[] = reset ? result.courses : this.courses.slice();
      if (!reset) {
        for (const course of result.courses) {
          if (merged.findIndex((item: SelectionCourse) => item.kcrwdm === course.kcrwdm) < 0) {
            merged.push(course);
          }
        }
      }
      this.courses = merged;
      this.hasMore = result.hasMore;
    } catch (error) {
      if (error instanceof JxfwError) {
        this.error = error.kind === JxfwErrorKind.SESSION
          ? '教务登录已失效，请先到教务同步重新登录' : error.message;
      } else {
        this.error = '选课列表加载失败，请稍后重试';
      }
      this.hasMore = false;
    } finally {
      this.loading = false;
      this.appending = false;
    }
  }

  private async loadMore(): Promise<void> {
    if (this.appending || !this.hasMore) {
      return;
    }
    this.page++;
    await this.load(false);
  }

  private search(): void {
    this.appliedKeyword = this.keyword.trim();
    this.load(true);
  }

  private async openDetail(course: SelectionCourse): Promise<void> {
    this.detail = course;
    this.detailLessons = [];
    this.detailConflicts = [];
    this.showDetail = true;
    this.detailLoading = true;
    try {
      this.detailLessons = await SelectionService.loadLessons(course.kcrwdm);
      this.detailConflicts = await SelectionService.conflictsFor(this.context(), this.detailLessons);
    } catch (error) {
      this.toast(error instanceof Error ? error.message : '课程详情加载失败');
    } finally {
      this.detailLoading = false;
    }
  }

  private async addCourse(course: SelectionCourse): Promise<void> {
    if (this.addingCode.length > 0) {
      return;
    }
    this.addingCode = course.kcrwdm;
    try {
      const added: boolean = await SelectionService.addToQueue(this.context(), course);
      if (!added) {
        this.toast('该课程已在抢课队列中');
      } else {
        this.bumpQueue();
        let conflicts: SelectionConflict[] = [];
        try {
          conflicts = await SelectionService.conflictsFor(this.context(),
            await SelectionService.loadLessons(course.kcrwdm));
        } catch (error) {
          conflicts = [];
        }
        this.toast(conflicts.length > 0
          ? `已加入队列（与 ${conflicts[0].name} 时间冲突）` : '已加入抢课队列');
      }
      await this.loadQueue();
    } catch (error) {
      this.toast('加入队列失败');
    } finally {
      this.addingCode = '';
    }
  }

  private bumpQueue(): void {
    const value: number | undefined = AppStorage.get<number>(SELECTION_QUEUE_REVISION_KEY);
    AppStorage.setOrCreate(SELECTION_QUEUE_REVISION_KEY, (value === undefined ? 0 : value) + 1);
  }

  private inQueue(code: string): boolean {
    return this.queue.findIndex((item: SelectionQueueItem) => item.kcrwdm === code) >= 0;
  }

  private seatsText(course: SelectionCourse): string {
    const remain: number = remainingSeats(course);
    if (remain < 0) {
      return '名额未知';
    }
    if (remain <= 0) {
      return '已满';
    }
    return `余 ${remain}`;
  }

  private seatsColor(course: SelectionCourse): ResourceColor {
    const remain: number = remainingSeats(course);
    if (remain < 0) {
      return AppTheme.TEXT_TERTIARY;
    }
    if (remain <= 0) {
      return '#C7362B';
    }
    if (remain <= 5) {
      return '#C77700';
    }
    return '#2E7D4F';
  }

  private lessonRows(lessons: SelectionLesson[]): LessonRow[] {
    const rows: LessonRow[] = [];
    for (const lesson of lessons) {
      const key: string = `${lesson.weekday}-${lesson.periods.join(',')}-${lesson.room}`;
      let found: LessonRow | null = null;
      for (const row of rows) {
        const rowKey: string = `${row.weekday}-${row.periods.join(',')}-${row.room}`;
        if (rowKey === key) {
          found = row;
          break;
        }
      }
      if (found === null) {
        rows.push({
          weekday: lesson.weekday,
          periods: lesson.periods.slice(),
          room: lesson.room,
          weeks: [lesson.week]
        });
      } else if (found.weeks.indexOf(lesson.week) < 0) {
        found.weeks.push(lesson.week);
      }
    }
    for (const row of rows) {
      row.weeks.sort((a: number, b: number) => a - b);
    }
    rows.sort((a: LessonRow, b: LessonRow) => {
      if (a.weekday !== b.weekday) {
        return a.weekday - b.weekday;
      }
      return (a.periods[0] ?? 0) - (b.periods[0] ?? 0);
    });
    return rows;
  }

  private formatPeriods(periods: number[]): string {
    if (periods.length === 0) {
      return '—';
    }
    const first: number = periods[0];
    const last: number = periods[periods.length - 1];
    if (last - first === periods.length - 1) {
      return first === last ? `第 ${first} 节` : `${first}-${last} 节`;
    }
    return `${periods.join(',')} 节`;
  }

  @Builder
  queueBanner() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('抢课队列')
          .fontSize(AppTheme.FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
        Text(`${this.queue.length}`)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(this.brandTextColor)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor(this.brandColor)
          .borderRadius(9)
          .opacity(0.14)
        Blank()
        Text('参数与运行')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(this.brandTextColor)
          .onClick(() => this.onOpenTask())
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(12)
          .fontColor([AppTheme.TEXT_TERTIARY])
      }
      .width('100%')

      if (this.queue.length === 0) {
        Text('暂无待抢课程。在下方列表里点“加入”，再到“参数与运行”设定开始时间。')
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .width('100%')
          .lineHeight(17)
      } else {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.queue, (item: SelectionQueueItem) => {
              Text(item.name)
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_PRIMARY)
                .maxLines(1)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .backgroundColor(AppTheme.BG)
                .borderRadius(10)
            }, (item: SelectionQueueItem) => `${item.id}-${item.state}`)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .align(Alignment.TopStart)
      }
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
  }

  @Builder
  searchBar() {
    Row({ space: 8 }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(15)
          .fontColor([AppTheme.TEXT_TERTIARY])
        TextInput({ text: this.keyword, placeholder: '搜索课程名' })
          .layoutWeight(1)
          .height(38)
          .backgroundColor(Color.Transparent)
          .padding(0)
          .fontSize(AppTheme.FONT_BODY)
          .onChange((value: string) => {
            this.keyword = value;
          })
          .onSubmit(() => this.search())
      }
      .layoutWeight(1)
      .height(40)
      .padding({ left: 12, right: 8 })
      .backgroundColor(AppTheme.CARD_BG)
      .borderRadius(20)

      Text('搜索')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(this.onBrandColor)
        .padding({ left: 16, right: 16, top: 9, bottom: 9 })
        .backgroundColor(this.brandColor)
        .borderRadius(20)
        .onClick(() => this.search())
    }
    .width('100%')
  }

  @Builder
  courseCard(course: SelectionCourse) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(course.name)
          .fontSize(AppTheme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.seatsText(course))
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(this.seatsColor(course))
      }
      .width('100%')

      Text(`${course.teacher.length > 0 ? course.teacher : '教师未公布'}${course.category.length > 0 ? ' · ' + course.category : ''}${course.credit > 0 ? ' · ' + course.credit + ' 学分' : ''}`)
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .maxLines(1)
        .width('100%')

      Row({ space: 8 }) {
        Text(course.capacity > 0 ? `已选 ${course.chosen}/${course.capacity}` : `已选 ${course.chosen}`)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_TERTIARY)
        Text(`课程代码 ${course.kcrwdm}`)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_TERTIARY)
        Blank()
        Text(this.inQueue(course.kcrwdm) ? '已在队列' : '加入')
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(this.inQueue(course.kcrwdm) ? AppTheme.TEXT_TERTIARY : this.onBrandColor)
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .backgroundColor(this.inQueue(course.kcrwdm) ? AppTheme.BG : this.brandColor)
          .borderRadius(11)
          .onClick(() => {
            if (!this.inQueue(course.kcrwdm)) {
              this.addCourse(course);
            }
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.ROW_RADIUS)
    .onClick(() => this.openDetail(course))
  }

  @Builder
  detailSheet() {
    Column({ space: 12 }) {
      if (this.detail !== null) {
        Row({ space: 8 }) {
          Column({ space: 3 }) {
            Text(this.detail.name)
              .fontSize(AppTheme.FONT_TITLE)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.TEXT_PRIMARY)
              .maxLines(2)
            Text(`${this.detail.teacher.length > 0 ? this.detail.teacher : '教师未公布'}${this.detail.category.length > 0 ? ' · ' + this.detail.category : ''}`)
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_SECONDARY)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Column({ space: 2 }) {
            Text(this.seatsText(this.detail))
              .fontSize(AppTheme.FONT_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.seatsColor(this.detail))
            Text(this.detail.capacity > 0 ? `${this.detail.chosen}/${this.detail.capacity}` : `${this.detail.chosen}`)
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_TERTIARY)
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')

        Divider().color(AppTheme.DIVIDER).strokeWidth(0.5)

        if (this.detailLoading) {
          Row({ space: 8 }) {
            LoadingProgress().width(18).height(18).color(this.brandTextColor)
            Text('正在读取排课…')
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_SECONDARY)
          }
          .width('100%')
        } else if (this.detailLessons.length === 0) {
          Text('教务未返回该课程的排课明细')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_SECONDARY)
            .width('100%')
        } else {
          Column({ space: 6 }) {
            ForEach(this.lessonRows(this.detailLessons), (row: LessonRow) => {
              Row({ space: 8 }) {
                Text(weekdayLabel(row.weekday))
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(this.brandTextColor)
                  .width(40)
                Text(this.formatPeriods(row.periods))
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(AppTheme.TEXT_PRIMARY)
                  .width(64)
                Text(row.room.length > 0 ? row.room : '地点未公布')
                  .fontSize(AppTheme.FONT_TINY)
                  .fontColor(AppTheme.TEXT_SECONDARY)
                  .layoutWeight(1)
                  .maxLines(1)
                Text(row.weeks.length > 0 && row.weeks[0] > 0 ? formatWeeks(row.weeks) : '周次未公布')
                  .fontSize(AppTheme.FONT_TINY)
                  .fontColor(AppTheme.TEXT_TERTIARY)
              }
              .width('100%')
            }, (row: LessonRow) => `${row.weekday}-${row.periods.join(',')}-${row.room}`)
          }
          .width('100%')
        }

        if (this.detailConflicts.length > 0) {
          Column({ space: 4 }) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
                .fontSize(13)
                .fontColor(['#C7362B'])
              Text('与本地课表时间冲突')
                .fontSize(AppTheme.FONT_TINY)
                .fontColor('#C7362B')
            }
            ForEach(this.detailConflicts, (conflict: SelectionConflict) => {
              Text(`${conflict.name} · ${weekdayLabel(conflict.weekday)} ${this.formatPeriods(conflict.periods)} · ${formatWeeks(conflict.weeks)}`)
                .fontSize(AppTheme.FONT_TINY)
                .fontColor('#C7362B')
                .maxLines(2)
            }, (conflict: SelectionConflict) => `${conflict.name}-${conflict.weekday}`)
          }
          .width('100%')
          .padding(10)
          .backgroundColor('#FFF1EF')
          .borderRadius(12)
          .alignItems(HorizontalAlign.Start)
        }

        Text('选课按教务的开放时段与名额规则执行；本工具只按固定间隔顺序提交，不做并发请求。')
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .width('100%')
          .lineHeight(16)

        Button(this.inQueue(this.detail.kcrwdm) ? '已在抢课队列' : '加入抢课队列')
          .width('100%')
          .height(44)
          .backgroundColor(this.inQueue(this.detail.kcrwdm) ? AppTheme.BG : this.brandColor)
          .fontColor(this.inQueue(this.detail.kcrwdm) ? AppTheme.TEXT_SECONDARY : this.onBrandColor)
          .enabled(!this.inQueue(this.detail.kcrwdm))
          .onClick(() => {
            const course: SelectionCourse | null = this.detail;
            if (course !== null) {
              this.addCourse(course);
            }
          })
      }
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          if (this.error.length > 0) {
            Row({ space: 8 }) {
              Text(this.error)
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor('#C7362B')
                .layoutWeight(1)
              if (this.error.includes('登录')) {
                Text('去登录')
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(this.brandTextColor)
                  .onClick(() => this.onOpenSync())
              }
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#FFF0EE')
            .borderRadius(14)
          }

          this.queueBanner()
          this.searchBar()

          if (this.notice.length > 0) {
            Text(this.notice)
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .width('100%')
          }

          if (this.loading) {
            Column({ space: 8 }) {
              LoadingProgress().width(24).height(24).color(this.brandTextColor)
              Text('正在读取选课列表…')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_TERTIARY)
            }
            .width('100%')
            .padding(40)
          } else if (this.courses.length === 0) {
            Column({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.list_square'))
                .fontSize(34)
                .fontColor([AppTheme.TEXT_TERTIARY])
              Text('没有可选课程')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
              Text('选课通常只在开放时段返回课程；也可能当前学期没有预选任务。')
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_TERTIARY)
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .padding(36)
          } else {
            ForEach(this.courses, (course: SelectionCourse) => {
              this.courseCard(course)
            }, (course: SelectionCourse) => `${course.kcrwdm}-${course.capacity}-${course.chosen}`)

            if (this.hasMore) {
              Text(this.appending ? '加载中…' : '加载更多')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(this.brandTextColor)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 6, bottom: 6 })
                .onClick(() => this.loadMore())
            }
          }

          Text('选课结果与风险由使用者承担，请遵守学校选课规定。抢课期间请保持本页在前台。')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .width('100%')
            .lineHeight(17)
        }
        .width('100%')
        .padding({
          left: AppTheme.PAGE_PADDING,
          right: AppTheme.PAGE_PADDING,
          top: AppTheme.TALL_PAGE_TOP_INSET + 20,
          bottom: AppTheme.SPACE_XXL
        })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .titleBar(immersiveTitleBar('选课助手'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
    .bindSheet(this.showDetail, this.detailSheet(), {
      height: SheetSize.LARGE,
      dragBar: true,
      showClose: true,
      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
      backgroundColor: AppTheme.SHEET_BG,
      radius: { topLeft: 32, topRight: 32, bottomLeft: 0, bottomRight: 0 },
      onDisappear: () => {
        this.showDetail = false;
      }
    })
  }
}
