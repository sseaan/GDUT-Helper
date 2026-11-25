import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';

@Component
export struct PlaceholderPage {
  @Prop title: string = '功能建设中';

  build() {
    HdsNavDestination() {
      Column({ space: AppTheme.SPACE_MD }) {
        SymbolGlyph($r('sys.symbol.doc_plaintext'))
          .fontSize(40)
          .fontColor([AppTheme.TEXT_TERTIARY])
        Text($r('app.string.placeholder_title'))
          .fontSize(AppTheme.FONT_HEADING)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
        Text($r('app.string.placeholder_desc'))
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .textAlign(TextAlign.Center)
          .lineHeight(20)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .padding(AppTheme.PAGE_PADDING)
    }
    .titleBar(immersiveTitleBar(this.title))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
