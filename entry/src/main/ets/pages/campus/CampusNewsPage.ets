import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { NewsFeedCard, NewsHeroCard } from '../../components/NewsCards';
import {
  PortalError,
  PortalNewsItem,
  PortalNewsPage,
  PORTAL_NEWS_CHANNELS,
  PortalNewsChannel
} from '../../services/portal/PortalModels';
import { PortalService } from '../../services/portal/PortalService';
import { PortalSession } from '../../services/portal/PortalSession';

@Component
export struct CampusNewsPage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  onOpenSync: () => void = () => {};
  onOpenNewsArticle: (url: string) => void = () => {};

  @StorageLink('jxfwSessionRevision') @Watch('onSessionRevision') sessionRevision: number = 0;
  @StorageLink('immersiveEnabled') immersiveEnabled: boolean = true;
  @State channelId: string = PORTAL_NEWS_CHANNELS[0].id;
  @State items: PortalNewsItem[] = [];
  @State total: number = 0;
  @State page: number = 1;
  @State loading: boolean = false;
  @State error: string = '';
  @State loggedIn: boolean = false;

  aboutToAppear(): void {
    this.loadChannel(true);
  }

  private onSessionRevision(): void {
    this.loadChannel(true);
  }

  private async loadChannel(reset: boolean): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.error = '';
    const targetPage: number = reset ? 1 : this.page + 1;
    try {
      const result: PortalNewsPage =
        await PortalService.loadNews(this.channelId, targetPage, reset);
      if (reset) {
        this.items = result.items;
      } else {
        const merged: PortalNewsItem[] = this.items.slice();
        for (const item of result.items) {
          if (!merged.some((existing: PortalNewsItem) => existing.wid === item.wid)) {
            merged.push(item);
          }
        }
        this.items = merged;
      }
      this.page = result.page;
      this.total = result.total;
      this.loggedIn = PortalSession.isLoggedIn();
    } catch (error) {
      this.loggedIn = PortalSession.isLoggedIn();
      this.error = error instanceof PortalError ? error.message : '校园新闻加载失败';
    } finally {
      this.loading = false;
    }
  }

  private selectChannel(channel: PortalNewsChannel): void {
    if (channel.id === this.channelId) {
      return;
    }
    this.channelId = channel.id;
    this.items = [];
    this.total = 0;
    this.page = 1;
    this.loadChannel(true);
  }

  private heroItem(): PortalNewsItem | null {
    if (this.items.length === 0) {
      return null;
    }
    const withImage: PortalNewsItem | undefined =
      this.items.find((item: PortalNewsItem) => item.picUrl.length > 0);
    return withImage === undefined ? this.items[0] : withImage;
  }

  private restItems(): PortalNewsItem[] {
    const hero: PortalNewsItem | null = this.heroItem();
    if (hero === null) {
      return [];
    }
    return this.items.filter((item: PortalNewsItem) => item.wid !== hero.wid);
  }

  @Builder
  channelBar() {
    Row({ space: 8 }) {
      ForEach(PORTAL_NEWS_CHANNELS, (channel: PortalNewsChannel) => {
        Text(channel.name)
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(this.channelId === channel.id ? this.onBrandColor : AppTheme.TEXT_PRIMARY)
          .fontWeight(this.channelId === channel.id ? FontWeight.Medium : FontWeight.Normal)
          .height(44)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.channelId === channel.id
            ? this.brandColor : $r('app.color.profile_card_bg'))
          .backgroundBlurStyle(this.channelId === channel.id || !this.immersiveEnabled
            ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THICK)
          .borderRadius(22)
          .border({
            width: 0.5,
            color: this.channelId === channel.id ? this.brandColor : '#33FFFFFF'
          })
          .onClick(() => this.selectChannel(channel))
      }, (channel: PortalNewsChannel) => channel.id)
    }
    .width('100%')
  }

  @Builder
  errorCard() {
    Column({ space: 10 }) {
      Text(this.error.length > 0 ? this.error : '登录统一认证后查看校园新闻')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .lineHeight(18)
      Text(this.loggedIn ? '重新加载' : '去登录')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(this.brandTextColor)
        .onClick(() => {
          if (this.loggedIn) {
            this.loadChannel(true);
          } else {
            this.onOpenSync();
          }
        })
    }
    .width('100%')
    .padding(AppTheme.SPACE_XL)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: AppTheme.SPACE_MD }) {
          this.channelBar()

          Row() {
            Text(`共 ${this.total} 条`)
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_TERTIARY)
            Blank()
            if (this.loading && this.items.length > 0) {
              LoadingProgress()
                .width(14)
                .height(14)
                .color(this.brandTextColor)
            }
          }
          .width('100%')

          if (this.items.length === 0) {
            if (this.loading) {
              Column({ space: 8 }) {
                LoadingProgress()
                  .width(28)
                  .height(28)
                  .color(this.brandTextColor)
                Text('正在加载校园新闻…')
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(AppTheme.TEXT_TERTIARY)
              }
              .width('100%')
              .height(180)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .backgroundColor(AppTheme.CARD_BG)
              .borderRadius(AppTheme.CARD_RADIUS)
            } else {
              this.errorCard()
            }
          } else {
            NewsHeroCard({
              item: this.heroItem(),
              cardHeight: 200,
              onOpen: (item: PortalNewsItem) => {
                if (item.url.length > 0) {
                  this.onOpenNewsArticle(item.url);
                }
              }
            })

            ForEach(this.restItems(), (item: PortalNewsItem) => {
              NewsFeedCard({
                item: item,
                onOpen: (news: PortalNewsItem) => {
                  if (news.url.length > 0) {
                    this.onOpenNewsArticle(news.url);
                  }
                }
              })
            }, (item: PortalNewsItem) => item.wid)

            if (this.error.length > 0) {
              Text(this.error)
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_TERTIARY)
                .width('100%')
                .textAlign(TextAlign.Center)
            }

            if (this.items.length < this.total) {
              Button(this.loading ? '加载中…' : '加载更多')
                .width('100%')
                .height(42)
                .enabled(!this.loading)
                .backgroundColor(AppTheme.CARD_BG)
                .fontColor(AppTheme.TEXT_PRIMARY)
                .onClick(() => this.loadChannel(false))
            }
          }
        }
        .width('100%')
        .padding({
          left: AppTheme.PAGE_PADDING,
          right: AppTheme.PAGE_PADDING,
          top: AppTheme.TALL_PAGE_TOP_INSET + 12,
          bottom: AppTheme.CONTENT_BOTTOM_INSET
        })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .titleBar(immersiveTitleBar('校园新闻'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
