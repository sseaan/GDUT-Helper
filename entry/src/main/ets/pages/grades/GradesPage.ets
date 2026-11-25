import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { GradeCache, GradeSummary, JxfwGrade } from '../../domain/model/GradeModels';
import { GradeService } from '../../services/grades/GradeService';
import { JxfwGradeParser } from '../../services/jxfw/JxfwGradeParser';
import { JxfwError, JxfwErrorKind } from '../../services/jxfw/JxfwModels';

@Component
struct GradeStat {
  @Prop label: ResourceStr = '';
  @Prop value: string = '';

  build() {
    Column({ space: 3 }) {
      Text(this.value)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.BRAND)
      Text(this.label)
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(AppTheme.TEXT_SECONDARY)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }
}

@Component
export struct GradesPage {
  onOpenSync: () => void = () => {};
  @State grades: JxfwGrade[] = [];
  @State summary: GradeSummary = {
    totalCredits: 0,
    earnedCredits: 0,
    gpaCredits: 0,
    weightedGpa: 0,
    count: 0
  };
  @State terms: string[] = [];
  @State selectedTerm: string = '';
  @State categories: string[] = [];
  @State selectedCategory: string = '';
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State updatedAt: string = '';
  @State error: string = '';

  aboutToAppear(): void {
    this.load();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async load(): Promise<void> {
    try {
      const cache: GradeCache | null = await GradeService.loadCache(this.context());
      if (cache !== null) {
        this.apply(cache);
      }
    } catch (error) {
      // Cache is optional.
    } finally {
      this.loading = false;
    }
    await this.refresh(false);
  }

  private async refresh(manual: boolean = true): Promise<void> {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    this.error = '';
    try {
      const cache: GradeCache = await GradeService.sync(this.context());
      this.apply(cache);
      if (manual) {
        this.toast('成绩已更新');
      }
    } catch (error) {
      if (error instanceof JxfwError) {
        this.error = error.kind === JxfwErrorKind.SESSION
          ? '教务登录已失效，请先到教务同步重新登录'
          : error.message;
      } else {
        this.error = '成绩更新失败，当前显示本地缓存';
      }
    } finally {
      this.refreshing = false;
    }
  }

  private apply(cache: GradeCache): void {
    this.grades = cache.grades;
    this.summary = JxfwGradeParser.summary(cache.grades);
    const terms: string[] = [];
    for (const grade of cache.grades) {
      if (terms.indexOf(grade.term) < 0) {
        terms.push(grade.term);
      }
    }
    terms.sort((a: string, b: string) => b.localeCompare(a));
    this.terms = terms;
    if (this.selectedTerm.length > 0 && terms.indexOf(this.selectedTerm) < 0) {
      this.selectedTerm = '';
    }
    const categories: string[] = [];
    for (const grade of cache.grades) {
      const key: string = this.categoryKey(grade);
      if (categories.indexOf(key) < 0) {
        categories.push(key);
      }
    }
    categories.sort((a: string, b: string) => a.localeCompare(b));
    this.categories = categories;
    if (this.selectedCategory.length > 0 && categories.indexOf(this.selectedCategory) < 0) {
      this.selectedCategory = '';
    }
    this.updatedAt = this.formatTime(cache.updatedAt);
  }

  private formatTime(value: number): string {
    if (value <= 0) {
      return '';
    }
    const date: Date = new Date(value);
    return `更新于 ${date.getMonth() + 1}月${date.getDate()}日 ${`${date.getHours()}`.padStart(2, '0')}:${`${date.getMinutes()}`.padStart(2, '0')}`;
  }

  private categoryKey(grade: JxfwGrade): string {
    return grade.category.length > 0 ? grade.category : '__none__';
  }

  private categoryLabel(category: string): string {
    return category === '__none__' ? '未分类' : category;
  }

  private filtered(): JxfwGrade[] {
    return this.grades.filter((grade: JxfwGrade) => {
      if (this.selectedTerm.length > 0 && grade.term !== this.selectedTerm) {
        return false;
      }
      if (this.selectedCategory.length > 0 && this.categoryKey(grade) !== this.selectedCategory) {
        return false;
      }
      return true;
    });
  }

  private gpaText(): string {
    return this.summary.weightedGpa > 0 ? this.summary.weightedGpa.toFixed(2) : '--';
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (error) {
      // ignore
    }
  }

  @Builder
  gradeRow(grade: JxfwGrade) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(grade.name)
          .fontSize(AppTheme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .maxLines(1)
        Text(`${grade.code} · ${grade.credit} 学分${grade.category.length > 0 ? ' · ' + grade.category : ''}`)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Column({ space: 2 }) {
        Text(grade.score.length > 0 ? grade.score : '待出分')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(JxfwGradeParser.isPassed(grade) || grade.score.length === 0
            ? AppTheme.TEXT_PRIMARY : '#C7362B')
        Text(grade.gpa > 0 ? `绩点 ${grade.gpa.toFixed(1)}` : grade.status)
          .fontSize(9)
          .fontColor(AppTheme.TEXT_TERTIARY)
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
    .onClick(() => {
      // Detail expansion is intentionally minimal; the row already shows score and GPA.
    })
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: 14 }) {
          if (this.error.length > 0) {
            Row({ space: 8 }) {
              Text(this.error)
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor('#C7362B')
                .layoutWeight(1)
              if (this.error.includes('登录')) {
                Text('去登录')
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(AppTheme.BRAND)
                  .onClick(() => this.onOpenSync())
              }
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#FFF0EE')
            .borderRadius(14)
          }

          Row() {
            GradeStat({ label: '学分加权均绩', value: this.gpaText() })
            GradeStat({ label: '已修学分', value: this.summary.earnedCredits.toFixed(1) })
            GradeStat({ label: '课程数', value: `${this.summary.count}` })
          }
          .width('100%')
          .padding({ top: 16, bottom: 16 })
          .backgroundColor($r('app.color.profile_card_bg'))
          .borderRadius(24)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 0.5, color: '#66FFFFFF' })

          Row() {
            Text(this.updatedAt.length > 0 ? this.updatedAt : '本地缓存')
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_TERTIARY)
            Blank()
            Text(this.refreshing ? '更新中…' : '刷新')
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.BRAND)
              .onClick(() => this.refresh(true))
          }
          .width('100%')

          Scroll() {
            Row({ space: 8 }) {
              Text('全部学期')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(this.selectedTerm.length === 0 ? AppTheme.ON_BRAND : AppTheme.TEXT_PRIMARY)
                .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                .backgroundColor(this.selectedTerm.length === 0 ? AppTheme.BRAND : AppTheme.CARD_BG)
                .borderRadius(16)
                .onClick(() => { this.selectedTerm = ''; })
              ForEach(this.terms, (term: string) => {
                Text(JxfwGradeParser.termLabel(term))
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(this.selectedTerm === term ? AppTheme.ON_BRAND : AppTheme.TEXT_PRIMARY)
                  .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                  .backgroundColor(this.selectedTerm === term ? AppTheme.BRAND : AppTheme.CARD_BG)
                  .borderRadius(16)
                  .onClick(() => { this.selectedTerm = term; })
              }, (term: string) => term)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .align(Alignment.TopStart)
          .width('100%')

          if (this.categories.length > 0) {
            Scroll() {
              Row({ space: 8 }) {
                Text('全部类别')
                  .fontSize(AppTheme.FONT_TINY)
                  .fontColor(this.selectedCategory.length === 0 ? AppTheme.ON_BRAND : AppTheme.TEXT_PRIMARY)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(this.selectedCategory.length === 0 ? AppTheme.BRAND : AppTheme.CARD_BG)
                  .borderRadius(14)
                  .onClick(() => { this.selectedCategory = ''; })
                ForEach(this.categories, (category: string) => {
                  Text(this.categoryLabel(category))
                    .fontSize(AppTheme.FONT_TINY)
                    .fontColor(this.selectedCategory === category ? AppTheme.ON_BRAND : AppTheme.TEXT_PRIMARY)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor(this.selectedCategory === category ? AppTheme.BRAND : AppTheme.CARD_BG)
                    .borderRadius(14)
                    .onClick(() => { this.selectedCategory = category; })
                }, (category: string) => category)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }

          if (this.filtered().length === 0) {
            Column({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.doc_plaintext'))
                .fontSize(34)
                .fontColor([AppTheme.TEXT_TERTIARY])
              Text(this.loading ? '正在读取成绩…' : '暂无成绩')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
            }
            .width('100%')
            .padding(40)
          } else {
            ForEach(this.filtered(), (grade: JxfwGrade) => {
              Column() {
                this.gradeRow(grade)
              }
              .width('100%')
              .backgroundColor(AppTheme.CARD_BG)
              .borderRadius(16)
            }, (grade: JxfwGrade) => `${grade.term}-${grade.code}-${grade.name}`)
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
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .titleBar(immersiveTitleBar($r('app.string.campus_grades')))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
