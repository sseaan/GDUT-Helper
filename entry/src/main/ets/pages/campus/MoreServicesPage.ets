import { common, Want } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { CampusDataCard } from '../../components/CampusDataCard';
import {
  PortalDashboard,
  PortalError,
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

/** 更多服务：校园数据概览 + 次级校园服务入口。 */
@Component
export struct MoreServicesPage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  onOpenSync: () => void = () => {};
  onOpenLibrary: () => void = () => {};
  onOpenSelection: () => void = () => {};
  onOpenElectricity: () => void = () => {};

  @StorageLink('clockTick') @Watch('onClockTick') clockTick: number = 0;
  @StorageLink('campusDataEnabled') @Watch('onCampusDataToggle') campusDataEnabled: boolean = true;
  @StorageLink('selectionEnabled') selectionEnabled: boolean = true;
  @StorageLink('electricityEnabled') electricityEnabled: boolean = false;
  @StorageLink('jxfwSessionRevision') @Watch('onSessionRevision') sessionRevision: number = 0;
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
  @State loggedIn: boolean = false;
  @State error: string = '';
  @State nowMs: number = Date.now();

  aboutToAppear(): void {
    this.loadDashboard(false);
  }

  private onClockTick(): void {
    this.nowMs = Date.now();
  }

  private onSessionRevision(): void {
    this.loadDashboard(true);
  }

  private onCampusDataToggle(): void {
    if (this.campusDataEnabled) {
      this.loadDashboard(true);
    }
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
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
    this.campusLink = MoreServicesPage.linkOf(dashboard.campusCard);
    this.libraryLink = MoreServicesPage.linkOf(dashboard.library);
    this.networkLink = MoreServicesPage.linkOf(dashboard.network);
    this.dashboardAt = dashboard.fetchedAt;
  }

  private static linkOf(card: PortalPersonalCard | null): string {
    return card === null ? '' : card.linkUrl;
  }

  private async loadDashboard(force: boolean): Promise<void> {
    if (!this.campusDataEnabled) {
      this.loading = false;
      this.loggedIn = PortalSession.isLoggedIn();
      return;
    }
    if (this.loading) {
      return;
    }
    // 先把上一次的数据铺上，进页面不会先空一屏再跳变。
    const stale: PortalDashboard | null = PortalService.cachedDashboard();
    if (stale !== null) {
      this.applyDashboard(stale);
    }
    this.loading = true;
    this.error = '';
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
      this.loggedIn = PortalSession.isLoggedIn();
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
      try {
        this.getUIContext().getPromptAction().showToast({ message: '无法打开链接' });
      } catch (toastError) {
        // Toast is optional.
      }
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

  /** 电费查询：Beta 阶段，带 Beta 角标，默认不在卡片区展示。 */
  @Builder
  electricityServiceCard() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.bolt'))
          .fontSize(24)
          .fontColor([this.brandTextColor])
        Text('Beta')
          .fontSize(9)
          .fontColor(this.brandTextColor)
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .borderRadius(6)
          .border({ width: 0.5, color: this.brandTextColor })
      }
      .width('100%')

      Text('电费查询')
        .fontSize(AppTheme.FONT_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .maxLines(1)
      Text('宿舍电表余额与用电量')
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
    .onClick(() => this.onOpenElectricity())
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: AppTheme.SPACE_LG }) {
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
              onRefresh: () => this.loadDashboard(true),
              onOpenLink: (url: string) => {
                if (url.includes('opac.gdut.edu.cn')) {
                  this.onOpenLibrary();
                } else {
                  this.openUrl(url);
                }
              }
            })
          }

          Text('更多服务')
            .fontSize(AppTheme.FONT_HEADING)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_PRIMARY)
            .width('100%')

          Row({ space: AppTheme.SPACE_MD }) {
            if (this.selectionEnabled) {
              Column() {
                this.serviceCard(
                  $r('sys.symbol.list_bullet_square_fill'),
                  '选课助手',
                  '查课 · 冲突预检 · 定时抢课',
                  () => this.onOpenSelection()
                )
              }
              .layoutWeight(1)
            }
            Column() {
              this.libraryServiceCard()
            }
            .layoutWeight(1)
          }
          .width('100%')

          if (this.electricityEnabled) {
            Row({ space: AppTheme.SPACE_MD }) {
              Column() {
                this.electricityServiceCard()
              }
              .layoutWeight(1)
              Column()
                .layoutWeight(1)
            }
            .width('100%')

            Text('电费查询为 Beta 功能，仍在适配中，结果仅供参考；可在「功能设置」中关闭。')
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_TERTIARY)
              .width('100%')
              .lineHeight(17)
          }

          if (this.selectionEnabled) {
            Text('选课按教务的开放时段与名额规则执行；请遵守学校选课规定。')
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_TERTIARY)
              .width('100%')
              .lineHeight(17)
          }
        }
        .width('100%')
        .padding({
          left: AppTheme.PAGE_PADDING,
          right: AppTheme.PAGE_PADDING,
          top: AppTheme.TALL_PAGE_TOP_INSET + 20,
          bottom: AppTheme.SPACE_XXL
        })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .titleBar(immersiveTitleBar('更多服务'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
