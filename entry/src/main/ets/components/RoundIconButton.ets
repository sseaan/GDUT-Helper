import { AppTheme } from '../common/Theme';

/**
 * Native-looking circular icon button for page-level navigation (previous/next month,
 * previous/next week, add). Uses a system SymbolGlyph rather than a text glyph so it
 * matches the HDS controls and keeps a 36vp touch target.
 */
@Component
export struct RoundIconButton {
  @Prop icon: Resource = $r('sys.symbol.chevron_left');
  @Prop isEnabled: boolean = true;
  onTap: () => void = () => {};

  build() {
    Button() {
      SymbolGlyph(this.icon)
        .fontSize(18)
        .fontColor([this.isEnabled ? AppTheme.TEXT_PRIMARY : AppTheme.TEXT_TERTIARY])
    }
    .type(ButtonType.Circle)
    .width(36)
    .height(36)
    .backgroundColor(AppTheme.CARD_BG)
    .enabled(this.isEnabled)
    .onClick(() => {
      this.onTap();
    })
  }
}
