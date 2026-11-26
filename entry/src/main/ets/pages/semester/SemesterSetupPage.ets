import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { ThemeColor } from '../../common/ThemeColor';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { Semester } from '../../domain/model/TimetableModels';
import { TimetableRepository } from '../../data/TimetableRepository';
import { TimetableState } from '../../state/TimetableState';

@Component
export struct SemesterSetupPage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  onDone: () => void = () => {};
  onOpenSync: () => void = () => {};

  @StorageLink('timetableRevision') @Watch('onRevisionChange') revision: number = 0;
  @State current: Semester | null = null;
  @State semesters: Semester[] = [];
  @State showCreate: boolean = false;
  @State name: string = '2026 秋季学期';
  @State startDate: string = '2026-08-31';
  @State totalWeeks: string = '20';
  @State termCode: string = '202601';
  @State loading: boolean = true;
  @State saving: boolean = false;

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
      this.semesters = await TimetableRepository.listSemesters(this.context());
      this.current = await TimetableRepository.getCurrentSemester(this.context());
    } catch (error) {
      this.toast('读取学期失败');
    } finally {
      this.loading = false;
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (error) {
      // Toast failure must not break the page.
    }
  }

  private semesterDetail(semester: Semester): string {
    const term: string = semester.termCode.length > 0 ? ` · ${semester.termCode}` : '';
    return `${semester.startDate} 开学 · 共 ${semester.totalWeeks} 周${term}`;
  }

  private async switchTo(semester: Semester): Promise<void> {
    if (semester.isCurrent) {
      return;
    }
    try {
      await TimetableRepository.setCurrentSemester(this.context(), semester.id);
      await this.load();
      TimetableState.bump();
      this.toast(`已切换到 ${semester.name}`);
    } catch (error) {
      this.toast('切换学期失败');
    }
  }

  private async createSemester(): Promise<void> {
    if (this.saving) {
      return;
    }
    const name: string = this.name.trim();
    if (name.length === 0) {
      this.toast('请填写学期名称');
      return;
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(this.startDate)) {
      this.toast('开学日期格式应为 YYYY-MM-DD');
      return;
    }
    const weeks: number = Number.parseInt(this.totalWeeks, 10);
    if (Number.isNaN(weeks) || weeks < 1 || weeks > 30) {
      this.toast('总周数应为 1–30');
      return;
    }
    this.saving = true;
    try {
      await TimetableRepository.createSemester(
        this.context(), name, this.startDate, weeks, this.termCode.trim()
      );
      TimetableState.bump();
      await this.load();
      this.showCreate = false;
      this.onDone();
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, 'M1DB', 'createSemester failed: %{public}s', JSON.stringify(error));
      this.toast(`创建学期失败: ${err.code} ${err.message}`);
    } finally {
      this.saving = false;
    }
  }

  @Builder
  label(text: ResourceStr) {
    Text(text)
      .fontSize(AppTheme.FONT_CAPTION)
      .fontColor(AppTheme.TEXT_SECONDARY)
      .width('100%')
  }

  @Builder
  semesterRow(semester: Semester) {
    Row({ space: 12 }) {
      Stack() {
        if (semester.isCurrent) {
          Column()
            .width(10)
            .height(10)
            .borderRadius(5)
            .backgroundColor(this.brandColor)
        }
      }
      .width(20)
      .height(20)
      .borderRadius(10)
      .border({
        width: semester.isCurrent ? 1.5 : 1,
        color: semester.isCurrent ? this.brandColor : AppTheme.TEXT_TERTIARY
      })
      .align(Alignment.Center)

      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(semester.name)
            .fontSize(AppTheme.FONT_BODY)
            .fontWeight(semester.isCurrent ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(AppTheme.TEXT_PRIMARY)
            .maxLines(1)
          if (semester.termCode.length > 0) {
            Text(semester.termCode)
              .fontSize(9)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              .backgroundColor(AppTheme.BG)
              .borderRadius(6)
          }
        }
        Text(this.semesterDetail(semester))
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (semester.isCurrent) {
        Text('当前')
          .fontSize(10)
          .fontColor(this.brandTextColor)
      }
    }
    .width('100%')
    .height(66)
    .padding({ left: 14, right: 14 })
    .backgroundColor(semester.isCurrent ? ThemeColor.alpha(this.brandColor, 0.07) : AppTheme.BG)
    .borderRadius(16)
    .border({
      width: semester.isCurrent ? 1.2 : 0.5,
      color: semester.isCurrent ? this.brandColor : '#14000000'
    })
    .onClick(() => this.switchTo(semester))
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: AppTheme.SPACE_MD }) {
          Column({ space: AppTheme.SPACE_SM }) {
            this.label('学期管理')
            Text($r('app.string.semester_current_hint'))
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .lineHeight(19)
            Button($r('app.string.profile_sync_hint'))
              .width('100%')
              .height(44)
              .onClick(() => this.onOpenSync())
            Text('推荐登录教务系统后直接选择当前学期或前后一学期，课表、开学日期和考试会自动导入。')
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_TERTIARY)
              .lineHeight(18)
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(AppTheme.CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)

          Column({ space: AppTheme.SPACE_SM }) {
            Row() {
              this.label('本地学期')
              Blank()
              if (this.current !== null) {
                Text(`当前：${this.current.name}`)
                  .fontSize(AppTheme.FONT_TINY)
                  .fontColor(AppTheme.TEXT_SECONDARY)
                  .maxLines(1)
              }
            }
            .width('100%')

            if (this.semesters.length === 0) {
              Text('还没有学期，去教务系统抓取一个吧。')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_TERTIARY)
                .width('100%')
                .padding({ top: 4, bottom: 4 })
            } else {
              ForEach(this.semesters, (semester: Semester) => {
                this.semesterRow(semester)
              }, (semester: Semester) => `${semester.id}-${semester.isCurrent}`)
            }
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(AppTheme.CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)

          Column({ space: AppTheme.SPACE_SM }) {
            Row() {
              Text('手动创建学期')
                .fontSize(AppTheme.FONT_BODY)
                .fontColor(AppTheme.TEXT_PRIMARY)
              Blank()
              Text(this.showCreate ? '收起' : '展开')
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(this.brandTextColor)
            }
            .width('100%')
            .onClick(() => {
              this.showCreate = !this.showCreate;
            })

            if (this.showCreate) {
              this.label($r('app.string.semester_name'))
              TextInput({ text: this.name })
                .height(42)
                .backgroundColor(AppTheme.BG)
                .borderRadius(10)
                .onChange((value: string) => {
                  this.name = value;
                })
              this.label($r('app.string.semester_start_date'))
              TextInput({ text: this.startDate })
                .height(42)
                .backgroundColor(AppTheme.BG)
                .borderRadius(10)
                .onChange((value: string) => {
                  this.startDate = value;
                })
              this.label($r('app.string.semester_term_code'))
              TextInput({ text: this.termCode })
                .height(42)
                .backgroundColor(AppTheme.BG)
                .borderRadius(10)
                .onChange((value: string) => {
                  this.termCode = value;
                })
              this.label($r('app.string.semester_total_weeks'))
              TextInput({ text: this.totalWeeks })
                .type(InputType.Number)
                .height(42)
                .backgroundColor(AppTheme.BG)
                .borderRadius(10)
                .onChange((value: string) => {
                  this.totalWeeks = value;
                })
              Text($r('app.string.semester_hint'))
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_TERTIARY)
                .lineHeight(18)
                .width('100%')
              Button($r('app.string.semester_create'))
                .width('100%')
                .height(44)
                .enabled(!this.saving && !this.loading)
                .onClick(() => this.createSemester())
            }
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(AppTheme.CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({
          left: AppTheme.PAGE_PADDING,
          right: AppTheme.PAGE_PADDING,
          top: AppTheme.PAGE_PADDING,
          bottom: AppTheme.SPACE_XXL
        })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
    }
    .titleBar(immersiveTitleBar($r('app.string.semester_title')))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
