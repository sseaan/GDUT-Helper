import { AppTheme } from '../common/Theme';
import { updateTimeLabel } from '../services/portal/PortalFormat';

const ACCENT_BLUE: string = '#2D7FF9';
const ACCENT_ORANGE: string = '#F07B43';
const ACCENT_GREEN: string = '#4CAF50';

@Component
struct CampusMetricTile {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  @Prop label: string = '';
  @Prop value: string = '--';
  @Prop sub: string = '';
  @Prop accent: string = '#59A8FF';
  onTap: () => void = () => {};

  build() {
    Column({ space: 5 }) {
      Text(this.label)
        .fontSize(9)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .maxLines(1)
      Column()
        .width('100%')
        .height(3)
        .borderRadius(2)
        .backgroundColor(this.accent)
      Text(this.value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.sub)
        .fontSize(8)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(88)
    .padding({ left: 10, right: 10, top: 10, bottom: 8 })
    .backgroundColor(AppTheme.BG)
    .borderRadius(12)
    .border({ width: 0.5, color: AppTheme.DIVIDER })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => this.onTap())
  }
}

@Component
export struct CampusDataCard {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
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

  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.square_fill_grid_2x2'))
          .fontSize(18)
          .fontColor([this.onBrandColor])
        Text('校园数据')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.onBrandColor)
        Blank()
        if (this.loading) {
          LoadingProgress()
            .width(14)
            .height(14)
            .color(this.onBrandColor)
        } else {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(12)
            .fontColor([this.onBrandColor])
        }
        Text(this.updateLabel())
          .fontSize(10)
          .fontColor(this.onBrandColor)
          .opacity(0.82)
          .maxLines(1)
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 14 })
      .backgroundColor(this.brandColor)
      .onClick(() => this.tapHeader())

      Column({ space: 8 }) {
        Row({ space: 8 }) {
          CampusMetricTile({
            label: '校园卡',
            value: this.campusValue,
            sub: this.campusSub,
            accent: ACCENT_BLUE,
            onTap: () => {
              if (this.campusLink.length > 0) {
                this.onOpenLink(this.campusLink);
              }
            }
          })
          CampusMetricTile({
            label: '图书借阅',
            value: this.libraryValue,
            sub: this.librarySub,
            accent: ACCENT_ORANGE,
            onTap: () => {
              if (this.libraryLink.length > 0) {
                this.onOpenLink(this.libraryLink);
              }
            }
          })
          CampusMetricTile({
            label: '校园网',
            value: this.networkValue,
            sub: this.networkSub,
            accent: ACCENT_GREEN,
            onTap: () => {
              if (this.networkLink.length > 0) {
                this.onOpenLink(this.networkLink);
              }
            }
          })
        }
        .width('100%')

        if (!this.loggedIn || this.error.length > 0) {
          Row({ space: 8 }) {
            Text(this.error.length > 0 && !this.loggedIn ? this.error
              : (!this.loggedIn ? '登录统一认证后查看校园卡、借阅和校园网余额' : '数据更新失败，点击重试'))
              .fontSize(9)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .maxLines(1)
              .layoutWeight(1)
            Text(this.loggedIn ? '重试' : '去登录')
              .fontSize(9)
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
          .padding({ top: 1 })
        }
      }
      .width('100%')
      .padding(10)
      .backgroundColor(AppTheme.CARD_BG)
      .borderRadius({ bottomLeft: 18, bottomRight: 18 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .borderRadius(20)
    .border({ width: 0.5, color: AppTheme.DIVIDER })
    .clip(true)
  }
}
