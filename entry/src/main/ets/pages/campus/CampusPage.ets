import { common } from '@kit.AbilityKit';
import { AppTheme } from '../../common/Theme';
import { NewsFeedCard, NewsHeroCard } from '../../components/NewsCards';
import {
  PortalError,
  PortalNewsItem,
  PortalNewsPreview
} from '../../services/portal/PortalModels';
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
  onOpenMoreServices: () => void = () => {};
  onOpenSync: () => void = () => {};
  onOpenCampusNews: () => void = () => {};
  onOpenNewsArticle: (url: string) => void = () => {};

  @StorageLink('campusNewsEnabled') campusNewsEnabled: boolean = true;
  @StorageLink('jxfwSessionRevision') @Watch('onSessionRevision') sessionRevision: number = 0;
  @State news: PortalNewsPreview | null = null;
  @State newsLoading: boolean = false;
  @State loggedIn: boolean = false;
  @State newsError: string = '';

  aboutToAppear(): void {
    this.loadNews(false);
  }

  private onSessionRevision(): void {
    this.loadNews(true);
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async loadNews(force: boolean): Promise<void> {
    if (!this.campusNewsEnabled) {
      this.newsLoading = false;
      return;
    }
    this.newsLoading = true;
    this.newsError = '';
    this.loggedIn = PortalSession.isLoggedIn();
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
      this.loggedIn = PortalSession.isLoggedIn();
    }
  }

  private loginOrRetry(): void {
    if (this.loggedIn && this.newsError.length === 0) {
      this.loadNews(true);
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
            this.serviceCard(
              $r('sys.symbol.square_fill_grid_2x2'),
              $r('app.string.campus_more_services'),
              $r('app.string.campus_more_services_desc'),
              () => this.onOpenMoreServices()
            )
          }
          .layoutWeight(1)
        }
        .width('100%')

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
