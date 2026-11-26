import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { TzcsClient } from '../../services/tzcs/TzcsClient';
import { TzcsCacheService } from '../../services/tzcs/TzcsCache';
import { TzcsCache, TzcsError, TzcsItem, TzcsReport } from '../../services/tzcs/TzcsModels';
import { TZCS_SESSION_REVISION_KEY, TzcsSession } from '../../services/tzcs/TzcsSession';

interface DisplayItem {
  name: string;
  detail: string;
  score: string;
  grade: string;
  value: number;
}

@Component
export struct PhysicalTestPage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  onOpenLogin: () => void = () => {};
  @StorageLink(TZCS_SESSION_REVISION_KEY) @Watch('onSessionChange') sessionRevision: number = 0;
  @State reports: TzcsReport[] = [];
  @State selectedYear: number = 0;
  @State loading: boolean = true;
  @State fetching: boolean = false;
  @State error: string = '';
  @State updatedAt: string = '';
  @State showLogin: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  onSessionChange(): void {
    if (TzcsSession.isLoggedIn()) {
      this.fetchReports();
    }
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async load(): Promise<void> {
    try {
      const cache: TzcsCache | null = await TzcsCacheService.load(this.context());
      if (cache !== null) {
        this.reports = cache.reports;
        this.selectedYear = cache.reports.length > 0 ? cache.reports[0].year : 0;
        const date: Date = new Date(cache.updatedAt);
        this.updatedAt = `${date.getMonth() + 1}月${date.getDate()}日 ${`${date.getHours()}`.padStart(2, '0')}:${`${date.getMinutes()}`.padStart(2, '0')}`;
      }
      this.showLogin = this.reports.length === 0;
      if (TzcsSession.isLoggedIn()) {
        await this.fetchReports();
      }
    } finally {
      this.loading = false;
    }
  }

  private async fetchReports(): Promise<void> {
    if (this.fetching || !TzcsSession.isLoggedIn()) {
      return;
    }
    this.fetching = true;
    this.error = '';
    try {
      const client: TzcsClient = new TzcsClient();
      client.setCookieHeader(TzcsSession.getCookie());
      const reports: TzcsReport[] = await client.fetchReports();
      this.reports = reports;
      this.selectedYear = reports.length > 0 ? reports[0].year : 0;
      await TzcsCacheService.save(this.context(), reports);
      const date: Date = new Date();
      this.updatedAt = `${date.getMonth() + 1}月${date.getDate()}日 ${`${date.getHours()}`.padStart(2, '0')}:${`${date.getMinutes()}`.padStart(2, '0')}`;
      this.showLogin = false;
    } catch (error) {
      const message: string = error instanceof TzcsError ? error.message : '读取体测成绩失败';
      this.error = message;
      if (error instanceof TzcsError && error.kind === 'SESSION') {
        TzcsSession.clear();
        this.showLogin = true;
      }
    } finally {
      this.fetching = false;
    }
  }

  private refresh(): void {
    if (!TzcsSession.isLoggedIn()) {
      this.showLogin = true;
      this.onOpenLogin();
      return;
    }
    this.fetchReports();
  }

  private selectedReport(): TzcsReport | null {
    if (this.reports.length === 0) {
      return null;
    }
    return this.reports.find((report: TzcsReport) => report.year === this.selectedYear) ?? this.reports[0];
  }

  private measured(item: TzcsItem): boolean {
    const score: number = Number.parseFloat(item.score.replace(/[^\d.]/g, ''));
    if (!Number.isNaN(score) && score > 0) {
      return true;
    }
    const raw: number = Number.parseFloat(item.rawValue.replace(/[^\d.]/g, ''));
    return !Number.isNaN(raw) && raw > 0;
  }

  private blank(value: string): boolean {
    const text: string = value.trim();
    return text.length === 0 || text === '—' || text === '-' || text === '--';
  }

  private emptyItem(item: TzcsItem): boolean {
    const rawNumber: string = item.rawValue.replace(/[厘米公斤千克次秒分\.\s]/g, '').trim();
    const score: number = Number.parseFloat(item.score.replace(/[^\d.]/g, ''));
    const weighted: number = Number(item.weightedScore);
    return rawNumber.length === 0 && (Number.isNaN(score) || score <= 0) &&
      this.blank(item.grade) && (Number.isNaN(weighted) || weighted <= 0);
  }

  private displayItems(report: TzcsReport): DisplayItem[] {
    const items: TzcsItem[] = report.items;
    const result: DisplayItem[] = [];
    const height: TzcsItem | undefined = items.find((item: TzcsItem) => item.name.includes('身高'));
    const weight: TzcsItem | undefined = items.find((item: TzcsItem) => item.name.includes('体重') && !item.name.includes('BMI'));
    const bmi: TzcsItem | undefined = items.find((item: TzcsItem) => item.name.includes('BMI') || item.name.includes('体重指数'));
    if (height !== undefined && weight !== undefined) {
      result.push({
        name: '身高 · 体重（BMI）',
        detail: `${height.rawValue} · ${weight.rawValue}`,
        score: bmi !== undefined && bmi.score.length > 0 ? bmi.score : height.score,
        grade: bmi !== undefined && bmi.grade.length > 0 ? bmi.grade : height.grade,
        value: bmi !== undefined && bmi.weightedScore > 0 ? bmi.weightedScore : height.weightedScore
      });
    }

    const maleMeasured: boolean = items.some((item: TzcsItem) =>
      (item.name.includes('1000米') || item.name.includes('引体向上')) && this.measured(item));
    const femaleMeasured: boolean = items.some((item: TzcsItem) =>
      (item.name.includes('800米') || item.name.includes('仰卧起坐') || item.name.includes('往返跑')) &&
      this.measured(item));
    const male: boolean = maleMeasured || !femaleMeasured;

    for (const item of items) {
      if (item.name.includes('身高') || (item.name.includes('体重') && !item.name.includes('BMI')) ||
        item.name.includes('BMI') || item.name.includes('体重指数')) {
        continue;
      }
      if (item.name.trim().length === 0 || item.name.includes('标准分') || item.name.includes('总分') ||
        item.name.includes('等级') || item.name.includes('备注')) {
        continue;
      }
      if (male && (item.name.includes('800米') || item.name.includes('仰卧起坐') || item.name.includes('往返跑'))) {
        continue;
      }
      if (!male && (item.name.includes('1000米') || item.name.includes('引体向上'))) {
        continue;
      }
      if (this.emptyItem(item)) {
        continue;
      }
      result.push({
        name: item.name,
        detail: item.rawValue,
        score: item.score,
        grade: item.grade,
        value: item.weightedScore
      });
    }
    return result;
  }

  private recordedText(report: TzcsReport): string {
    const items: DisplayItem[] = this.displayItems(report);
    let recorded: number = 0;
    for (const item of items) {
      if (item.detail.length > 0 || item.score.length > 0) {
        recorded++;
      }
    }
    return `已测 ${recorded}/${items.length} 项`;
  }

  private isGoodScore(score: string): boolean {
    const value: number = Number.parseFloat(score);
    return Number.isNaN(value) || value >= 60;
  }

  private gradeColor(grade: string, score: string): string {
    if (grade.includes('优秀') || grade.includes('正常')) {
      return '#2F8F67';
    }
    if (grade.includes('良好')) {
      return '#2F6F9E';
    }
    if (grade.includes('及格')) {
      return '#B26A00';
    }
    if (grade.includes('不及格') || grade.includes('不合格') || grade.includes('未通过')) {
      return '#C7362B';
    }
    const value: number = Number.parseFloat(score);
    if (Number.isNaN(value)) {
      return '#65707D';
    }
    return value >= 90 ? '#2F8F67' : (value >= 60 ? '#B26A00' : '#C7362B');
  }

  private async logout(): Promise<void> {
    TzcsSession.clear();
    this.reports = [];
    this.selectedYear = 0;
    this.updatedAt = '';
    this.showLogin = true;
    await TzcsCacheService.clear(this.context());
  }

  @Builder
  detailRow(item: DisplayItem) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(item.name)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
        if (item.detail.length > 0) {
          Text(item.detail)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_SECONDARY)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column({ space: 4 }) {
        Text(`${item.score.length > 0 ? item.score : '—'} 分${item.grade.length > 0 ? ' · ' + item.grade : ''}`)
          .fontSize(AppTheme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.gradeColor(item.grade, item.score))
        if (item.value > 0) {
          Text(`分值 ${item.value}`)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_SECONDARY)
        }
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 14, bottom: 14 })
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(20)
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: 14 }) {
          if (this.error.length > 0) {
            Text(this.error)
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor('#C7362B')
              .width('100%')
              .padding(12)
              .backgroundColor('#FFF0EE')
              .borderRadius(14)
          }

          if (this.selectedReport() !== null) {
            Column({ space: 10 }) {
              Row() {
                Column({ space: 4 }) {
                  Text(`${this.selectedReport()?.year} 年体测总分`)
                    .fontSize(AppTheme.FONT_CAPTION)
                    .fontColor('#DCE8FF')
                  Row({ space: 8 }) {
                    Text(this.selectedReport()?.totalScore ?? '--')
                      .fontSize(34)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.White)
                    Text('分')
                      .fontSize(AppTheme.FONT_CAPTION)
                      .fontColor('#DCE8FF')
                    if ((this.selectedReport()?.totalGrade.length ?? 0) > 0) {
                      Text(this.selectedReport()?.totalGrade ?? '')
                        .fontSize(AppTheme.FONT_TINY)
                        .fontColor(this.gradeColor(this.selectedReport()?.totalGrade ?? '', this.selectedReport()?.totalScore ?? ''))
                        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        .backgroundColor('#F2FFFFFF')
                        .borderRadius(10)
                    }
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button(this.fetching ? '更新中…' : '刷新成绩')
                  .height(42)
                  .borderRadius(21)
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(this.brandTextColor)
                  .backgroundColor(Color.White)
                  .onClick(() => this.refresh())
              }
              .width('100%')

              Text(`${this.recordedText(this.selectedReport() as TzcsReport)} · 更新于 ${this.updatedAt.length > 0 ? this.updatedAt : '本地缓存'}`)
                .fontSize(AppTheme.FONT_TINY)
                .fontColor('#DCE8FF')
                .width('100%')
              Text('以体测平台官方数据为准')
                .fontSize(AppTheme.FONT_TINY)
                .fontColor('#BFD3FF')
                .width('100%')
            }
            .width('100%')
            .padding(18)
            .backgroundColor(this.brandColor)
            .borderRadius(24)

            if (this.reports.length > 1) {
              Scroll() {
                Row({ space: 8 }) {
                  ForEach(this.reports, (report: TzcsReport) => {
                    Text(`${report.year} 学年`)
                      .fontSize(AppTheme.FONT_CAPTION)
                      .fontColor(this.selectedYear === report.year ? this.onBrandColor : AppTheme.TEXT_PRIMARY)
                      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                      .backgroundColor(this.selectedYear === report.year ? '#2F8F67' : AppTheme.CARD_BG)
                      .borderRadius(16)
                      .onClick(() => { this.selectedYear = report.year; })
                  }, (report: TzcsReport) => `${report.year}`)
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
            }

            Text(`测试项目 · ${this.displayItems(this.selectedReport() as TzcsReport).length}`)
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .width('100%')
              .padding({ left: 4, top: 2 })

            ForEach(this.displayItems(this.selectedReport() as TzcsReport), (item: DisplayItem, index: number) => {
              this.detailRow(item)
            }, (item: DisplayItem, index: number) => `item-${index}`)

            Row() {
              Text(`学号 ${this.selectedReport()?.studentNo ?? ''}`)
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_TERTIARY)
              Blank()
              Text('退出体测登录')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor('#C7362B')
                .onClick(() => this.logout())
            }
            .width('100%')
            .padding({ top: AppTheme.SPACE_MD, bottom: AppTheme.SPACE_MD })
          } else if (!this.loading) {
            Column({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.star_fill'))
                .fontSize(34)
                .fontColor([AppTheme.TEXT_TERTIARY])
              Text('暂无体测成绩')
                .fontSize(AppTheme.FONT_BODY)
                .fontColor(AppTheme.TEXT_PRIMARY)
              Text('请在校园网/VPN 环境登录体测平台')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
              Button('登录体测平台')
                .height(42)
                .borderRadius(21)
                .onClick(() => this.onOpenLogin())
            }
            .width('100%')
            .padding(28)
            .backgroundColor(AppTheme.CARD_BG)
            .borderRadius(20)
          }
        }
        .width('100%')
        .padding({
          left: AppTheme.PAGE_PADDING,
          right: AppTheme.PAGE_PADDING,
          top: AppTheme.TALL_PAGE_TOP_INSET + 18,
          bottom: AppTheme.CONTENT_BOTTOM_INSET
        })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
    }
    .titleBar(immersiveTitleBar($r('app.string.campus_physical')))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
