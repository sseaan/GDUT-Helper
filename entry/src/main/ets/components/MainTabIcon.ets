import { AppTheme } from '../common/Theme';

/**
 * Bottom tab item: filled system symbol + label, brand color when active.
 * The 3vp leading spacer compensates for SymbolGlyph's centering offset on device,
 * following the same visual grammar as NextE's MainTabIcon.
 */
@Component
export struct MainTabIcon {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  @Prop title: ResourceStr = '';
  @Prop icon: Resource = $r('sys.symbol.clock');
  @Prop active: boolean = false;

  build() {
    Column() {
      Row() {
        Blank().width(AppTheme.TAB_ICON_OFFSET)
        SymbolGlyph(this.icon)
          .fontSize(AppTheme.TAB_SYMBOL_SIZE)
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .fontColor([
            this.active ? this.brandTextColor : $r('sys.color.font_secondary')
          ])
      }
      .width(AppTheme.TAB_ICON_BOX)
      .height(AppTheme.TAB_ICON_BOX - 2)
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Center)

      Text(this.title)
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(this.active ? this.brandTextColor : $r('sys.color.font_secondary'))
        .maxLines(1)
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
    .padding({ top: AppTheme.SPACE_SM - 2, bottom: AppTheme.SPACE_XS })
  }
}
