import { AppTheme } from '../common/Theme';
import { ThemeColor } from '../common/ThemeColor';
import { PortalNewsItem } from '../services/portal/PortalModels';
import { cleanNewsTitle, relativeNewsTime } from '../services/portal/PortalFormat';

@Component
export struct NewsHeroCard {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  @Prop item: PortalNewsItem | null = null;
  @Prop cardHeight: number = 180;
  onOpen: (item: PortalNewsItem) => void = () => {};

  build() {
    if (this.item !== null) {
      Stack({ alignContent: Alignment.BottomStart }) {
        Column()
          .width('100%')
          .height(this.cardHeight)
          .backgroundColor(this.brandColor)
        if (this.item.picUrl.length > 0) {
          Image(this.item.picUrl)
            .width('100%')
            .height(this.cardHeight)
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.doc_plaintext'))
              .fontSize(48)
              .fontColor([this.onBrandColor])
              .opacity(0.55)
          }
          .width('100%')
          .height(this.cardHeight)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
        Column()
          .width('100%')
          .height(this.cardHeight)
          .backgroundColor(this.item.picUrl.length > 0 ? '#4D000000' : '#1A000000')
        Column() {
          Row() {
            Text(this.item.channelName.length > 0 ? this.item.channelName : '校园新闻')
              .fontSize(9)
              .fontColor('#FFFFFF')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(ThemeColor.alpha(this.brandColor, 0.2))
              .borderRadius(8)
          }
          .width('100%')

          Column({ space: 6 }) {
            Text(cleanNewsTitle(this.item.title))
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Row() {
              Text(relativeNewsTime(this.item.pubTime))
                .fontSize(10)
                .fontColor('#E6FFFFFF')
              Blank()
              Text('阅读 ›')
                .fontSize(10)
                .fontColor('#FFFFFF')
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor('#4DFFFFFF')
                .borderRadius(9)
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height(this.cardHeight)
        .padding({ left: 14, right: 14, top: 14, bottom: 14 })
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height(this.cardHeight)
      .borderRadius(18)
      .clip(true)
      .onClick(() => {
        const item: PortalNewsItem | null = this.item;
        if (item !== null) {
          this.onOpen(item);
        }
      })
    }
  }
}

@Component
export struct NewsFeedCard {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  @Prop item: PortalNewsItem | null = null;
  onOpen: (item: PortalNewsItem) => void = () => {};

  build() {
    if (this.item !== null) {
      Row({ space: 12 }) {
        Column({ space: 5 }) {
          Text(cleanNewsTitle(this.item.title))
            .fontSize(AppTheme.FONT_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_PRIMARY)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Blank()
          Text(relativeNewsTime(this.item.pubTime))
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Stack() {
          Column() {
            SymbolGlyph($r('sys.symbol.doc_plaintext'))
              .fontSize(28)
              .fontColor([this.brandTextColor])
          }
          .width(84)
          .height(84)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(AppTheme.BG)

          if (this.item.picUrl.length > 0) {
            Image(this.item.picUrl)
              .width(84)
              .height(84)
              .objectFit(ImageFit.Cover)
          }
        }
        .width(84)
        .height(84)
        .borderRadius(14)
        .border({ width: 0.5, color: AppTheme.DIVIDER })
        .clip(true)
      }
      .width('100%')
      .height(104)
      .padding(12)
      .backgroundColor(AppTheme.CARD_BG)
      .borderRadius(16)
      .onClick(() => {
        const item: PortalNewsItem | null = this.item;
        if (item !== null) {
          this.onOpen(item);
        }
      })
    }
  }
}
