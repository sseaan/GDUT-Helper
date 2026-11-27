import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { CoursePalette } from '../../common/CoursePalette';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { Course, Semester, weekdayLabel } from '../../domain/model/TimetableModels';
import { CourseEditParam } from '../../domain/model/NavParams';
import { TimetableRepository } from '../../data/TimetableRepository';
import { TimetableState } from '../../state/TimetableState';

@Component
export struct CourseEditPage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  param: CourseEditParam = { semesterId: '', courseId: '' };
  onDone: () => void = () => {};

  @State semester: Semester | null = null;
  @State name: string = '';
  @State teacher: string = '';
  @State room: string = '';
  @State weekday: number = 1;
  @State startPeriod: number = 1;
  @State endPeriod: number = 2;
  @State selectedWeeks: number[] = [];
  @State colorKey: number = 0;
  @State createdAt: number = 0;
  @State note: string = '';
  @State content: string = '';
  /** 保留原课程来源：编辑同步课程不应把它变成 MANUAL。 */
  @State source: string = 'MANUAL';
  @State loading: boolean = true;
  @State saving: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async load(): Promise<void> {
    try {
      const semester: Semester | null =
        await TimetableRepository.getSemester(this.context(), this.param.semesterId);
      this.semester = semester;
      if (this.param.courseId.length > 0) {
        const course: Course | null =
          await TimetableRepository.getCourse(this.context(), this.param.courseId);
        if (course !== null) {
          this.name = course.name;
          this.teacher = course.teacher;
          this.room = course.room;
          this.weekday = course.weekday;
          this.startPeriod = course.startPeriod;
          this.endPeriod = course.endPeriod;
          this.selectedWeeks = course.weeks.slice();
          this.colorKey = course.colorKey;
          this.note = course.note;
          this.content = course.content;
          this.createdAt = course.createdAt;
          if (course.source.length > 0) {
            this.source = course.source;
          }
        }
      } else if (this.param.sourceCourseId !== undefined && this.param.sourceCourseId.length > 0) {
        const source: Course | null =
          await TimetableRepository.getCourse(this.context(), this.param.sourceCourseId);
        if (source !== null) {
          this.name = source.name;
          this.teacher = source.teacher;
          this.room = source.room;
          this.weekday = source.weekday;
          this.startPeriod = source.startPeriod;
          this.endPeriod = source.endPeriod;
          this.colorKey = source.colorKey;
          this.note = source.note;
          this.content = source.content;
          const week: number = this.param.makeupWeek !== undefined ? this.param.makeupWeek : 1;
          this.selectedWeeks = [week];
        }
      } else if (semester !== null) {
        const weeks: number[] = [];
        for (let i = 1; i <= semester.totalWeeks; i++) {
          weeks.push(i);
        }
        this.selectedWeeks = weeks;
      }
    } catch (error) {
      this.toast('读取课程失败');
    } finally {
      this.loading = false;
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (error) {
      // Toast failure must not break the form.
    }
  }

  private allWeeks(): number[] {
    const result: number[] = [];
    const total: number = this.semester === null ? 20 : this.semester.totalWeeks;
    for (let i = 1; i <= total; i++) {
      result.push(i);
    }
    return result;
  }

  private toggleWeek(week: number): void {
    const index: number = this.selectedWeeks.indexOf(week);
    const next: number[] = this.selectedWeeks.slice();
    if (index >= 0) {
      next.splice(index, 1);
    } else {
      next.push(week);
      next.sort((a: number, b: number) => a - b);
    }
    this.selectedWeeks = next;
  }

  private periodOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (let i = 1; i <= 12; i++) {
      options.push({ value: `${i}` });
    }
    return options;
  }

  private async save(): Promise<void> {
    if (this.saving) {
      return;
    }
    const name: string = this.name.trim();
    if (name.length === 0) {
      this.toast('请填写课程名称');
      return;
    }
    if (this.selectedWeeks.length === 0) {
      this.toast('至少选择一个上课周次');
      return;
    }
    if (this.startPeriod > this.endPeriod) {
      this.toast('开始节次不能晚于结束节次');
      return;
    }
    if (this.semester === null) {
      this.toast('学期尚未初始化');
      return;
    }
    this.saving = true;
    try {
      const course: Course = {
        id: this.param.courseId,
        semesterId: this.semester.id,
        name: name,
        teacher: this.teacher.trim(),
        room: this.room.trim(),
        weekday: this.weekday,
        startPeriod: this.startPeriod,
        endPeriod: this.endPeriod,
        weeks: this.selectedWeeks.slice(),
        colorKey: this.colorKey,
        content: this.content,
        note: this.note.trim(),
        source: this.source,
        createdAt: this.createdAt,
        updatedAt: 0
      };
      await TimetableRepository.saveCourse(this.context(), course);
      TimetableState.bump();
      this.onDone();
    } catch (error) {
      this.toast('保存课程失败');
    } finally {
      this.saving = false;
    }
  }

  private deleteCourse(): void {
    if (this.param.courseId.length === 0) {
      return;
    }
    AlertDialog.show({
      title: '删除课程',
      message: `确定删除“${this.name}”及其单周调整吗？`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Color.Red,
        action: () => {
          this.confirmDelete();
        }
      }
    });
  }

  private async confirmDelete(): Promise<void> {
    try {
      await TimetableRepository.deleteCourse(this.context(), this.param.courseId);
      TimetableState.bump();
      this.onDone();
    } catch (error) {
      this.toast('删除课程失败');
    }
  }

  @Builder
  sectionTitle(title: ResourceStr) {
    Text(title)
      .fontSize(AppTheme.FONT_TITLE)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppTheme.TEXT_PRIMARY)
      .width('100%')
  }

  @Builder
  fieldLabel(label: ResourceStr) {
    Text(label)
      .fontSize(AppTheme.FONT_CAPTION)
      .fontColor(AppTheme.TEXT_SECONDARY)
      .width('100%')
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: AppTheme.SPACE_MD }) {
          this.sectionTitle($r('app.string.course_basic_info'))
          Column({ space: AppTheme.SPACE_SM }) {
            this.fieldLabel($r('app.string.course_name'))
            TextInput({ text: this.name, placeholder: $r('app.string.course_name_hint') })
              .height(44)
              .backgroundColor(AppTheme.BG)
              .borderRadius(12)
              .onChange((value: string) => {
                this.name = value;
              })
            this.fieldLabel($r('app.string.course_teacher'))
            TextInput({ text: this.teacher, placeholder: $r('app.string.course_teacher_hint') })
              .height(44)
              .backgroundColor(AppTheme.BG)
              .borderRadius(12)
              .onChange((value: string) => {
                this.teacher = value;
              })
            this.fieldLabel($r('app.string.course_room'))
            TextInput({ text: this.room, placeholder: $r('app.string.course_room_hint') })
              .height(44)
              .backgroundColor(AppTheme.BG)
              .borderRadius(12)
              .onChange((value: string) => {
                this.room = value;
              })
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(AppTheme.CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)

          this.sectionTitle($r('app.string.course_schedule'))
          Column({ space: AppTheme.SPACE_SM }) {
            this.fieldLabel($r('app.string.course_weekday'))
            Row({ space: 4 }) {
              ForEach([1, 2, 3, 4, 5, 6, 7], (day: number) => {
                Text(weekdayLabel(day).replace('周', ''))
                  .fontSize(AppTheme.FONT_CAPTION)
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)
                  .height(36)
                  .fontColor(this.weekday === day ? this.onBrandColor : AppTheme.TEXT_PRIMARY)
                  .backgroundColor(this.weekday === day ? this.brandColor : AppTheme.BG)
                  .borderRadius(10)
                  .onClick(() => {
                    this.weekday = day;
                  })
              }, (day: number) => `day-${day}`)
            }
            .width('100%')

            Row({ space: AppTheme.SPACE_SM }) {
              Column({ space: 4 }) {
                this.fieldLabel($r('app.string.course_period_start'))
                Select(this.periodOptions())
                  .selected(this.startPeriod - 1)
                  .value(`${this.startPeriod}`)
                  .onSelect((index: number) => {
                    this.startPeriod = index + 1;
                    if (this.endPeriod < this.startPeriod) {
                      this.endPeriod = this.startPeriod;
                    }
                  })
              }
              .layoutWeight(1)
              Column({ space: 4 }) {
                this.fieldLabel($r('app.string.course_period_end'))
                Select(this.periodOptions())
                  .selected(this.endPeriod - 1)
                  .value(`${this.endPeriod}`)
                  .onSelect((index: number) => {
                    this.endPeriod = index + 1;
                  })
              }
              .layoutWeight(1)
            }
            .width('100%')

            this.fieldLabel($r('app.string.course_weeks'))
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.allWeeks(), (week: number) => {
                Text(`${week}`)
                  .fontSize(AppTheme.FONT_TINY)
                  .width(34)
                  .height(30)
                  .textAlign(TextAlign.Center)
                  .margin(2)
                  .fontColor(this.selectedWeeks.indexOf(week) >= 0 ? this.onBrandColor : AppTheme.TEXT_PRIMARY)
                  .backgroundColor(this.selectedWeeks.indexOf(week) >= 0 ? this.brandColor : AppTheme.BG)
                  .borderRadius(8)
                  .onClick(() => this.toggleWeek(week))
              }, (week: number) => `week-${week}`)
            }
            .width('100%')

            this.fieldLabel($r('app.string.course_color'))
            Row({ space: 6 }) {
              ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], (key: number) => {
                Stack() {
                  if (this.colorKey === key) {
                    SymbolGlyph($r('sys.symbol.checkmark'))
                      .fontSize(14)
                      .fontColor([CoursePalette.foreground(key)])
                  }
                }
                .width(24)
                .height(24)
                .borderRadius(12)
                .backgroundColor(CoursePalette.background(key))
                .border({
                  width: this.colorKey === key ? 2 : 1,
                  color: this.colorKey === key ? CoursePalette.foreground(key) : AppTheme.DIVIDER
                })
                .onClick(() => {
                  this.colorKey = key;
                })
              }, (key: number) => `color-${key}`)
            }
            .width('100%')
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(AppTheme.CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)

          this.sectionTitle($r('app.string.course_content'))
          TextArea({ text: this.content, placeholder: '教务同步的授课内容，可手动补充或修改' })
            .height(80)
            .backgroundColor(AppTheme.CARD_BG)
            .borderRadius(AppTheme.CARD_RADIUS)
            .padding(AppTheme.CARD_PADDING)
            .onChange((value: string) => {
              this.content = value;
            })

          this.sectionTitle($r('app.string.course_note'))
          TextArea({ text: this.note, placeholder: $r('app.string.course_note_hint') })
            .height(80)
            .backgroundColor(AppTheme.CARD_BG)
            .borderRadius(AppTheme.CARD_RADIUS)
            .padding(AppTheme.CARD_PADDING)
            .onChange((value: string) => {
              this.note = value;
            })

          Button(this.param.courseId.length > 0 ? $r('app.string.course_save') : $r('app.string.course_create'))
            .width('100%')
            .height(44)
            .enabled(!this.saving && !this.loading)
            .onClick(() => {
              this.save();
            })

          if (this.param.courseId.length > 0) {
            Button($r('app.string.course_delete'))
              .width('100%')
              .height(44)
              .fontColor(Color.Red)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.deleteCourse();
              })
          }
        }
        .width('100%')
        .padding({
          left: AppTheme.PAGE_PADDING,
          right: AppTheme.PAGE_PADDING,
          top: AppTheme.TALL_PAGE_TOP_INSET + 40,
          bottom: AppTheme.SPACE_XXL
        })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
    }
    .titleBar(immersiveTitleBar(this.param.courseId.length > 0
      ? $r('app.string.course_edit_title') : $r('app.string.course_add_title')))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
