import { common } from '@kit.AbilityKit';
import { AppTheme } from '../common/Theme';
import { CoursePalette } from '../common/CoursePalette';
import {
  CourseException,
  ExceptionType,
  ExpandedCourse,
  weekdayLabel
} from '../domain/model/TimetableModels';
import { DEFAULT_PERIOD_TIMES } from '../domain/model/Periods';
import { TimetableRepository } from '../data/TimetableRepository';
import { TimetableState } from '../state/TimetableState';

@Component
export struct CourseSheet {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  @Prop course: ExpandedCourse | null = null;
  @Prop week: number = 1;
  onEdit: () => void = () => {};
  onAddMakeup: () => void = () => {};
  onChanged: () => void = () => {};
  onClose: () => void = () => {};

  @State showReschedule: boolean = false;
  @State newWeekday: number = 1;
  @State newStartPeriod: number = 1;
  @State newEndPeriod: number = 2;
  @State newRoom: string = '';
  @State saving: boolean = false;

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (error) {
      // Toast failure must not break the sheet.
    }
  }

  private timeRange(): string {
    if (this.course === null) {
      return '';
    }
    const start: number = this.course.startPeriod - 1;
    const end: number = this.course.endPeriod - 1;
    if (start < 0 || end < 0 || start >= DEFAULT_PERIOD_TIMES.length || end >= DEFAULT_PERIOD_TIMES.length) {
      return `第 ${this.course.startPeriod}–${this.course.endPeriod} 节`;
    }
    return `${DEFAULT_PERIOD_TIMES[start][0]} – ${DEFAULT_PERIOD_TIMES[end][1]} · 第 ${this.course.startPeriod}–${this.course.endPeriod} 节`;
  }

  private startReschedule(): void {
    if (this.course === null) {
      return;
    }
    this.newWeekday = this.course.weekday;
    this.newStartPeriod = this.course.startPeriod;
    this.newEndPeriod = this.course.endPeriod;
    this.newRoom = this.course.room;
    this.showReschedule = true;
  }

  private async saveException(type: ExceptionType): Promise<void> {
    if (this.course === null || this.saving) {
      return;
    }
    if (type === ExceptionType.RESCHEDULE && this.newStartPeriod > this.newEndPeriod) {
      this.toast('开始节次不能晚于结束节次');
      return;
    }
    this.saving = true;
    try {
      const exception: CourseException = {
        id: '',
        courseId: this.course.courseId,
        week: this.week,
        type: type,
        newWeekday: type === ExceptionType.RESCHEDULE ? this.newWeekday : 0,
        newStartPeriod: type === ExceptionType.RESCHEDULE ? this.newStartPeriod : 0,
        newEndPeriod: type === ExceptionType.RESCHEDULE ? this.newEndPeriod : 0,
        newRoom: type === ExceptionType.RESCHEDULE ? this.newRoom.trim() : '',
        note: '',
        source: 'MANUAL',
        createdAt: 0,
        updatedAt: 0
      };
      await TimetableRepository.saveException(this.context(), exception);
      TimetableState.bump();
      this.onChanged();
      this.onClose();
    } catch (error) {
      this.toast('保存本周调整失败');
    } finally {
      this.saving = false;
    }
  }

  private async restore(): Promise<void> {
    if (this.course === null || this.course.exceptionId.length === 0) {
      return;
    }
    try {
      await TimetableRepository.deleteExceptionById(this.context(), this.course.exceptionId);
      TimetableState.bump();
      this.onChanged();
      this.onClose();
    } catch (error) {
      this.toast('恢复课程失败');
    }
  }

  private periodOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (let i = 1; i <= 12; i++) {
      options.push({ value: `${i}` });
    }
    return options;
  }

  @Builder
  sheetChip(text: ResourceStr) {
    Text(text)
      .fontSize(AppTheme.FONT_TINY)
      .fontColor(AppTheme.TEXT_SECONDARY)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(AppTheme.SHEET_CARD_BG)
      .borderRadius(12)
  }

  @Builder
  infoLine(label: ResourceStr, value: string) {
    Row() {
      Text(label)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .width(48)
      Text(value.length > 0 ? value : '—')
        .fontSize(AppTheme.FONT_BODY)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .maxLines(1)
        .layoutWeight(1)
    }
    .width('100%')
    .height(34)
  }

  @Builder
  actionPill(icon: Resource, label: ResourceStr, action: () => void) {
    Row({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(17)
        .fontColor([AppTheme.TEXT_PRIMARY])
      Text(label)
        .fontSize(AppTheme.FONT_CHIP)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .maxLines(1)
    }
    .layoutWeight(1)
    .height(46)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppTheme.SHEET_CARD_BG)
    .borderRadius(23)
    .onClick(action)
  }

  build() {
    Column({ space: AppTheme.SPACE_MD }) {
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
      if (this.course !== null) {
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text(this.course.name)
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.TEXT_PRIMARY)
              .maxLines(1)
            Text(`${weekdayLabel(this.course.weekday)} · ${this.timeRange()}`)
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([AppTheme.TEXT_SECONDARY])
          }
          .width(36)
          .height(36)
          .backgroundColor(AppTheme.SHEET_CARD_BG)
          .onClick(() => this.onClose())
        }
        .width('100%')

        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          Row({ space: 6 }) {
            this.sheetChip(this.course.room.length > 0 ? this.course.room : '未填写教室')
            this.sheetChip(this.course.teacher.length > 0 ? this.course.teacher : '未填写教师')
            this.sheetChip(`第 ${this.week} 周`)
          }
          .width('100%')
        }
        .width('100%')

        Column() {
          this.infoLine('时间', this.timeRange())
          Divider().color(AppTheme.DIVIDER).opacity(0.55)
          this.infoLine('地点', this.course.room)
          Divider().color(AppTheme.DIVIDER).opacity(0.55)
          this.infoLine('教师', this.course.teacher)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 4, bottom: 4 })
        .backgroundColor(AppTheme.SHEET_CARD_BG)
        .borderRadius(20)

        Column({ space: 4 }) {
          Text($r('app.string.course_content'))
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_SECONDARY)
            .width('100%')
          Text(this.course.content.length > 0 ? this.course.content : '教务未提供本课程的授课内容')
            .fontSize(AppTheme.FONT_BODY)
            .fontColor(this.course.content.length > 0 ? AppTheme.TEXT_PRIMARY : AppTheme.TEXT_TERTIARY)
            .lineHeight(20)
            .width('100%')
        }
        .width('100%')
        .padding(14)
        .backgroundColor(AppTheme.SHEET_CARD_BG)
        .borderRadius(20)
        .alignItems(HorizontalAlign.Start)

        if (this.course.isException) {
          Column({ space: AppTheme.SPACE_SM }) {
            Text(this.course.exceptionType === ExceptionType.CANCEL ? '本周已停课' : '本周已调课')
              .fontSize(AppTheme.FONT_BODY)
              .fontColor(this.brandTextColor)
              .width('100%')
            Button($r('app.string.course_restore_week'))
              .width('100%')
              .height(46)
              .borderRadius(23)
              .backgroundColor(AppTheme.SHEET_CARD_BG)
              .fontColor(AppTheme.TEXT_PRIMARY)
              .onClick(() => {
                this.restore();
              })
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor(AppTheme.SHEET_BG)
          .borderRadius(20)
          .alignItems(HorizontalAlign.Start)
        } else if (!this.showReschedule) {
          Button($r('app.string.course_edit_action'))
            .width('100%')
            .height(48)
            .borderRadius(24)
            .onClick(() => this.onEdit())
          Row({ space: AppTheme.SPACE_SM }) {
            this.actionPill($r('sys.symbol.clock'), $r('app.string.course_cancel_week'), () => {
              this.saveException(ExceptionType.CANCEL);
            })
            this.actionPill($r('sys.symbol.arrow_clockwise'), $r('app.string.course_reschedule_week'), () => {
              this.startReschedule();
            })
            this.actionPill($r('sys.symbol.plus'), $r('app.string.course_makeup'), () => {
              this.onAddMakeup();
            })
          }
          .width('100%')
        } else {
          Column({ space: AppTheme.SPACE_SM }) {
            Text($r('app.string.course_weekday'))
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .width('100%')
            Row({ space: 4 }) {
              ForEach([1, 2, 3, 4, 5, 6, 7], (day: number) => {
                Text(weekdayLabel(day).replace('周', ''))
                  .layoutWeight(1)
                  .height(34)
                  .textAlign(TextAlign.Center)
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(this.newWeekday === day ? this.onBrandColor : AppTheme.TEXT_PRIMARY)
                  .backgroundColor(this.newWeekday === day ? this.brandColor : AppTheme.SHEET_CARD_BG)
                  .borderRadius(12)
                  .onClick(() => {
                    this.newWeekday = day;
                  })
              }, (day: number) => `sheet-day-${day}`)
            }
            .width('100%')

            Row({ space: AppTheme.SPACE_SM }) {
              Select(this.periodOptions())
                .selected(this.newStartPeriod - 1)
                .value(`${this.newStartPeriod}`)
                .onSelect((index: number) => {
                  this.newStartPeriod = index + 1;
                  if (this.newEndPeriod < this.newStartPeriod) {
                    this.newEndPeriod = this.newStartPeriod;
                  }
                })
              Select(this.periodOptions())
                .selected(this.newEndPeriod - 1)
                .value(`${this.newEndPeriod}`)
                .onSelect((index: number) => {
                  this.newEndPeriod = index + 1;
                })
              TextInput({ text: this.newRoom, placeholder: $r('app.string.course_room_hint') })
                .layoutWeight(1)
                .height(36)
                .backgroundColor(AppTheme.SHEET_CARD_BG)
                .borderRadius(12)
                .onChange((value: string) => {
                  this.newRoom = value;
                })
            }
            .width('100%')

            Row({ space: AppTheme.SPACE_SM }) {
              Button($r('app.string.course_save_adjust'))
                .layoutWeight(1)
                .height(44)
                .borderRadius(22)
                .enabled(!this.saving)
                .onClick(() => {
                  this.saveException(ExceptionType.RESCHEDULE);
                })
              Button($r('app.string.cancel'))
                .layoutWeight(1)
                .height(44)
                .borderRadius(22)
                .backgroundColor(AppTheme.SHEET_CARD_BG)
                .fontColor(AppTheme.TEXT_PRIMARY)
                .onClick(() => {
                  this.showReschedule = false;
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor(AppTheme.SHEET_BG)
          .borderRadius(20)
          .alignItems(HorizontalAlign.Start)
        }
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 4, bottom: AppTheme.SPACE_XXL })
    .alignItems(HorizontalAlign.Start)
  }
}
