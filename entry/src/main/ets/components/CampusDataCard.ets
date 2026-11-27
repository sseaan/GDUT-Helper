import { AppTheme } from '../common/Theme';
import { updateTimeLabel } from '../services/portal/PortalFormat';

/** 三项数据各用一种强调色，方便一眼区分；不再统一走主题色。 */
const ACCENT_CAMPUS: string = '#2D7FF9';
const ACCENT_LIBRARY: string = '#F07B43';
const ACCENT_NETWORK: string = '#3FAE5A';

/**
 * 单列指标。
 *
 * 必须是独立组件而不是 `@Builder`：多参数 `@Builder` 是**按值传递**的，
 * 参数变化不会触发重绘，异步数据回来时会一直停在首帧的 `--`。
 * `@Prop` 走父级刷新，才能跟着数据更新。
 */
@Component
struct CampusMetricCell {
  @Prop label: string = '';
  @Prop value: string = '--';
  @Prop sub: string = '';
  @Prop accent: string = '#2D7FF9';
  onTap: () => void = () => {};

  build() {
    Column({ space: 3 }) {
      Text(this.value)
        .fontSize(AppTheme.FONT_HEADING)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.value === '--' ? AppTheme.TEXT_TERTIARY : this.accent)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.label)
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .maxLines(1)
      Text(this.sub)
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => this.onTap())
  }
}

/**
 * 校园数据：校园卡 / 图书借阅 / 校园网三列数字。
 *
 * 三项都只有「一个数值 + 一句副标题」，所以不做仪表盘：一层卡片底、两条细分隔线，
 * 标题行直接坐在页面背景上。
 */
@Component
export struct CampusDataCard {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  @Prop campusValue: string = '--';
  @Prop campusSub: string = '未获取';
  @Prop libraryValue: string = '--';
  @Prop librarySub: string = '未获取';
  @Prop networkValue: string = '--';
  @Prop networkSub: string = '未获取';
  @Prop campusLink: string = '';
  @Prop libraryLink: string = '';
  @Prop networkLink: string = '';
  @Prop loading: boolean = false;
  @Prop dashboardAt: number = 0;
  @Prop nowMs: number = 0;
  @Prop loggedIn: boolean = false;
  @Prop error: string = '';
  onLogin: () => void = () => {};
  onRefresh: () => void = () => {};
  onOpenLink: (url: string) => void = () => {};

  private updateLabel(): string {
    return updateTimeLabel(this.dashboardAt, this.nowMs, this.loading, this.loggedIn, this.error);
  }

  private tapHeader(): void {
    if (this.loggedIn && this.error.length === 0) {
      this.onRefresh();
    } else {
      this.onLogin();
    }
  }

  private statusText(): string {
    if (!this.loggedIn) {
      return this.error.length > 0 ? this.error : '登录统一认证后查看校园卡、借阅和校园网余额';
    }
    return this.error.length > 0 ? '数据更新失败' : '';
  }

  private openLink(url: string): void {
    if (url.length > 0) {
      this.onOpenLink(url);
    }
  }

  @Builder
  metricDivider() {
    Column()
      .width(0.5)
      .height(38)
      .backgroundColor(AppTheme.DIVIDER)
      .opacity(0.7)
  }

  build() {
    Column({ space: AppTheme.SPACE_SM }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.square_fill_grid_2x2'))
          .fontSize(14)
          .fontColor([AppTheme.TEXT_TERTIARY])
        Text('校园数据')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_SECONDARY)
        Blank()
        if (this.loading) {
          LoadingProgress()
            .width(12)
            .height(12)
            .color(this.brandTextColor)
        }
        Text(this.updateLabel())
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .maxLines(1)
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(14)
          .fontColor([this.brandTextColor])
      }
      .width('100%')
      .height(26)
      .onClick(() => this.tapHeader())

      Row() {
        CampusMetricCell({
          label: '校园卡',
          value: this.campusValue,
          sub: this.campusSub,
          accent: ACCENT_CAMPUS,
          onTap: () => this.openLink(this.campusLink)
        })
        this.metricDivider()
        CampusMetricCell({
          label: '图书借阅',
          value: this.libraryValue,
          sub: this.librarySub,
          accent: ACCENT_LIBRARY,
          onTap: () => this.openLink(this.libraryLink)
        })
        this.metricDivider()
        CampusMetricCell({
          label: '校园网',
          value: this.networkValue,
          sub: this.networkSub,
          accent: ACCENT_NETWORK,
          onTap: () => this.openLink(this.networkLink)
        })
      }
      .width('100%')
      .padding({ left: AppTheme.SPACE_SM, right: AppTheme.SPACE_SM, top: 14, bottom: 14 })
      .backgroundColor(AppTheme.CARD_BG)
      .borderRadius(AppTheme.CARD_RADIUS)

      if (this.statusText().length > 0) {
        Row({ space: AppTheme.SPACE_SM }) {
          Text(this.statusText())
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .maxLines(2)
            .layoutWeight(1)
          Text(this.loggedIn ? '重试' : '去登录')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(this.brandTextColor)
            .onClick(() => {
              if (this.loggedIn) {
                this.onRefresh();
              } else {
                this.onLogin();
              }
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
