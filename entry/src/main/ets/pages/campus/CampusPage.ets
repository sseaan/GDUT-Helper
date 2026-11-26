import { common, Want } from '@kit.AbilityKit';
import { AppTheme } from '../../common/Theme';
import { ThemeColor } from '../../common/ThemeColor';
import { NewsFeedCard, NewsHeroCard } from '../../components/NewsCards';
import { CampusDataCard } from '../../components/CampusDataCard';
import {
  PortalDashboard,
  PortalError,
  PortalNewsItem,
  PortalNewsPreview,
  PortalPersonalCard
} from '../../services/portal/PortalModels';
import {
  campusCardDisplay,
  libraryDisplay,
  networkDisplay,
  PortalCardDisplay
} from '../../services/portal/PortalFormat';
import { PortalService } from '../../services/portal/PortalService';
import { PortalSession } from '../../services/portal/PortalSession';
import { JxfwSession } from '../../services/jxfw/JxfwSession';

@Component
export struct CampusPage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  onOpenClassroom: () => void = () => {};
  onOpenGrades: () => void = () => {};
  onOpenPhysical: () => void = () => {};
  onOpenPlaceholder: (title: string) => void = () => {};
  onOpenSync: () => void = () => {};
  onOpenCampusNews: () => void = () => {};
  onOpenNewsArticle: (url: string) => void = () => {};
  onOpenLibrary: () => void = () => {};

  @StorageLink('clockTick') @Watch('onClockTick') clockTick: number = 0;
  @StorageLink('campusNewsEnabled') campusNewsEnabled: boolean = true;
  @StorageLink('campusDataEnabled') @Watch('onCampusDataToggle') campusDataEnabled: boolean = true;
  @StorageLink('jxfwSessionRevision') @Watch('onSessionRevision') sessionRevision: number = 0;
  @State news: PortalNewsPreview | null = null;
  @State campusValue: string = '--';
  @State campusSub: string = '未获取';
  @State libraryValue: string = '--';
  @State librarySub: string = '未获取';
  @State networkValue: string = '--';
  @State networkSub: string = '未获取';
  @State campusLink: string = '';
  @State libraryLink: string = '';
  @State networkLink: string = '';
  @State dashboardAt: number = 0;
  @State loading: boolean = false;
  @State newsLoading: boolean = false;
  @State loggedIn: boolean = false;
  @State error: string = '';
  @State newsError: string = '';
  @State nowMs: number = Date.now();

  aboutToAppear(): void {
    this.loadPortal(false);
  }

  private onClockTick(): void {
    this.nowMs = Date.now();
  }

  private onSessionRevision(): void {
    this.loadPortal(true);
  }

  private onCampusDataToggle(): void {
    if (this.campusDataEnabled) {
      this.loadPortal(true);
    }
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      // Toast is optional.
    }
  }

  private applyDashboard(dashboard: PortalDashboard): void {
    const campus: PortalCardDisplay = campusCardDisplay(dashboard.campusCard);
    const library: PortalCardDisplay = libraryDisplay(dashboard.library);
    const network: PortalCardDisplay = networkDisplay(dashboard.network);
    this.campusValue = campus.value;
    this.campusSub = campus.sub;
    this.libraryValue = library.value;
    this.librarySub = library.sub;
    this.networkValue = network.value;
    this.networkSub = network.sub;
    this.campusLink = CampusPage.linkOf(dashboard.campusCard);
    this.libraryLink = CampusPage.linkOf(dashboard.library);
    this.networkLink = CampusPage.linkOf(dashboard.network);
    this.dashboardAt = dashboard.fetchedAt;
  }

  private static linkOf(card: PortalPersonalCard | null): string {
    return card === null ? '' : card.linkUrl;
  }

  private async loadPortal(force: boolean): Promise<void> {
    if (this.loading) {
      return;
    }
    this.newsLoading = true;
    this.error = '';
    this.newsError = '';
    if (this.campusDataEnabled) {
      this.loading = true;
      try {
        const dashboard: PortalDashboard = await PortalService.loadDashboard(force);
        this.applyDashboard(dashboard);
      } catch (error) {
        const cached: PortalDashboard | null = PortalService.cachedDashboard();
        if (cached !== null) {
          this.applyDashboard(cached);
        }
        this.error = error instanceof PortalError ? error.message : '校园数据加载失败';
      } finally {
        this.loading = false;
      }
    } else {
      this.loading = false;
    }
    this.loggedIn = PortalSession.isLoggedIn();

    if (!this.campusNewsEnabled) {
      this.newsLoading = false;
      return;
    }
    try {
      const preview: PortalNewsPreview = await PortalService.loadNewsPreview(force);
      this.news = preview;
    } catch (error) {
      const cachedNews: PortalNewsPreview | null = PortalService.cachedNewsPreview();
      if (cachedNews !== null) {
        this.news = cachedNews;
      }
      this.newsError = error instanceof PortalError ? error.message : '校园新闻加载失败';
    } finally {
      this.newsLoading = false;
    }
  }

  private async openUrl(url: string): Promise<void> {
    if (url.length === 0) {
      return;
    }
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url
      };
      await this.context().startAbility(want);
    } catch (error) {
      this.toast('无法打开链接');
    }
  }

  private loginOrRetry(): void {
    if (this.loggedIn && this.error.length === 0) {
      this.loadPortal(true);
    } else {
      this.onOpenSync();
    }
  }

  @Builder
  serviceCard(icon: Resource, title: ResourceStr, desc: ResourceStr, action: () => void) {
    Column({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(26)
        .fontColor([this.brandTextColor])
      Text(title)
        .fontSize(AppTheme.FONT_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .maxLines(1)
      Text(desc)
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .maxLines(2)
        .lineHeight(15)
    }
    .width('100%')
    .height(118)
    .padding(14)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .onClick(action)
  }

  @Builder
  libraryServiceCard() {
    Column({ space: 6 }) {
      Image($r('app.media.ic_library_book'))
        .width(26)
        .height(26)
        .fillColor(this.brandTextColor)
      Text('图书馆')
        .fontSize(AppTheme.FONT_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .maxLines(1)
      Text('借阅 · 续借 · 馆藏')
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .maxLines(2)
        .lineHeight(15)
    }
    .width('100%')
    .height(118)
    .padding(14)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.onOpenLibrary())
  }

  @Builder
  wideEntry(icon: Resource, title: ResourceStr, desc: ResourceStr, action: () => void) {
    Row({ space: 14 }) {
      Stack() {
        SymbolGlyph(icon)
          .fontSize(21)
          .fontColor([this.brandTextColor])
      }
      .width(42)
      .height(42)
      .borderRadius(14)
      .backgroundColor(ThemeColor.alpha(this.brandColor, 0.1))
      .align(Alignment.Center)

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
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(18)
    .onClick(action)
  }

  @Builder
  newsHeader() {
    Row({ space: 8 }) {
      Text('校园新闻')
        .fontSize(AppTheme.FONT_HEADING)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_PRIMARY)
      Blank()
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([AppTheme.TEXT_TERTIARY])
    }
    .width('100%')
    .onClick(() => this.onOpenCampusNews())
  }

  @Builder
  newsPreview() {
    if (this.news !== null && this.news.hero !== null) {
      NewsHeroCard({
        item: this.news.hero,
        cardHeight: 180,
        onOpen: (item: PortalNewsItem) => {
          if (item.url.length > 0) {
            this.onOpenNewsArticle(item.url);
          }
        }
      })
      if (this.news.feed !== null) {
        NewsFeedCard({
          item: this.news.feed,
          onOpen: (item: PortalNewsItem) => {
            if (item.url.length > 0) {
              this.onOpenNewsArticle(item.url);
            }
          }
        })
      }
    } else if (this.newsLoading) {
      Column({ space: 8 }) {
        LoadingProgress()
          .width(24)
          .height(24)
          .color(this.brandTextColor)
        Text('正在加载校园新闻…')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_TERTIARY)
      }
      .width('100%')
      .height(140)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(AppTheme.CARD_BG)
      .borderRadius(16)
    } else {
      Column({ space: 8 }) {
        Text(this.newsError.length > 0 ? this.newsError : '登录统一认证后查看校园新闻')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .textAlign(TextAlign.Center)
        Text(this.loggedIn ? '重新加载' : '去登录')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(this.brandTextColor)
          .onClick(() => this.loginOrRetry())
      }
      .width('100%')
      .height(120)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(AppTheme.CARD_BG)
      .borderRadius(16)
    }
  }

  build() {
    Scroll() {
      Column({ space: AppTheme.SPACE_LG }) {
        if (this.campusNewsEnabled) {
          this.newsHeader()
          this.newsPreview()
        }

        Text($r('app.string.campus_services'))
          .fontSize(AppTheme.FONT_HEADING)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .width('100%')

        Row({ space: AppTheme.SPACE_MD }) {
          Column() {
            this.serviceCard(
              $r('sys.symbol.doc_plaintext'),
              $r('app.string.campus_grades'),
              $r('app.string.campus_grades_desc'),
              () => this.onOpenGrades()
            )
          }
          .layoutWeight(1)
          Column() {
            this.serviceCard(
              $r('sys.symbol.star_fill'),
              $r('app.string.campus_physical'),
              $r('app.string.campus_physical_desc'),
              () => this.onOpenPhysical()
            )
          }
          .layoutWeight(1)
        }
        .width('100%')

        Row({ space: AppTheme.SPACE_MD }) {
          Column() {
            this.serviceCard(
              $r('sys.symbol.list_square'),
              $r('app.string.campus_classroom'),
              $r('app.string.campus_classroom_desc'),
              () => this.onOpenClassroom()
            )
          }
          .layoutWeight(1)
          Column() {
            this.libraryServiceCard()
          }
          .layoutWeight(1)
        }
        .width('100%')

        this.wideEntry(
          $r('sys.symbol.square_fill_grid_2x2'),
          $r('app.string.campus_more_services'),
          $r('app.string.campus_more_services_desc'),
          () => this.onOpenPlaceholder('更多服务')
        )

        if (this.campusDataEnabled) {
          CampusDataCard({
            campusValue: this.campusValue,
            campusSub: this.campusSub,
            libraryValue: this.libraryValue,
            librarySub: this.librarySub,
            networkValue: this.networkValue,
            networkSub: this.networkSub,
            campusLink: this.campusLink,
            libraryLink: this.libraryLink,
            networkLink: this.networkLink,
            loading: this.loading,
            dashboardAt: this.dashboardAt,
            nowMs: this.nowMs,
            loggedIn: this.loggedIn,
            error: this.error,
            onLogin: () => this.onOpenSync(),
            onRefresh: () => this.loadPortal(true),
            onOpenLink: (url: string) => {
              if (url.includes('opac.gdut.edu.cn')) {
                this.onOpenLibrary();
              } else {
                this.openUrl(url);
              }
            }
          })
        }

      }
      .width('100%')
      .padding({
        left: AppTheme.PAGE_PADDING,
        right: AppTheme.PAGE_PADDING,
        top: AppTheme.TALL_PAGE_TOP_INSET + 8,
        bottom: AppTheme.CONTENT_BOTTOM_INSET
      })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .backgroundColor(AppTheme.BG)
    .scrollBar(BarState.Off)
  }
}
