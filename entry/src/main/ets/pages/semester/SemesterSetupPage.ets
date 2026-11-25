import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { Semester } from '../../domain/model/TimetableModels';
import { TimetableRepository } from '../../data/TimetableRepository';
import { TimetableState } from '../../state/TimetableState';

@Component
export struct SemesterSetupPage {
  onDone: () => void = () => {};

  @State current: Semester | null = null;
  @State name: string = '2026 秋季学期';
  @State startDate: string = '2026-08-31';
  @State totalWeeks: string = '20';
  @State termCode: string = '202601';
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

  private async create(): Promise<void> {
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

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: AppTheme.SPACE_MD }) {
          if (this.current !== null) {
            Column({ space: AppTheme.SPACE_SM }) {
              Text($r('app.string.semester_current'))
                .fontSize(AppTheme.FONT_TITLE)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.TEXT_PRIMARY)
              Text(this.current.name)
                .fontSize(AppTheme.FONT_HEADING)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppTheme.TEXT_PRIMARY)
              Text(`${this.current.startDate} 开学 · 共 ${this.current.totalWeeks} 周`)
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
              Text($r('app.string.semester_current_hint'))
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
                .lineHeight(19)
              Button($r('app.string.semester_back'))
                .width('100%')
                .height(42)
                .onClick(() => this.onDone())
            }
            .width('100%')
            .padding(AppTheme.CARD_PADDING)
            .backgroundColor(AppTheme.CARD_BG)
            .borderRadius(AppTheme.CARD_RADIUS)
            .alignItems(HorizontalAlign.Start)
          } else {
            Column({ space: AppTheme.SPACE_SM }) {
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
            }
            .width('100%')
            .padding(AppTheme.CARD_PADDING)
            .backgroundColor(AppTheme.CARD_BG)
            .borderRadius(AppTheme.CARD_RADIUS)
            .alignItems(HorizontalAlign.Start)

            Text($r('app.string.semester_hint'))
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_TERTIARY)
              .lineHeight(18)
              .width('100%')

            Button($r('app.string.semester_create'))
              .width('100%')
              .height(44)
              .enabled(!this.saving && !this.loading)
              .onClick(() => {
                this.create();
              })
          }
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
