/**
 * App-level design tokens.
 *
 * Colors follow HarmonyOS semantic system tokens so light/dark mode and the user's
 * accent color are handled by the platform. Spacing stays on a 4vp grid.
 */
export class AppTheme {
  static readonly SPACE_XS: number = 4;
  static readonly SPACE_SM: number = 8;
  static readonly SPACE_MD: number = 12;
  static readonly SPACE_LG: number = 16;
  static readonly SPACE_XL: number = 24;
  static readonly SPACE_XXL: number = 32;

  static readonly PAGE_PADDING: number = 16;
  static readonly CARD_RADIUS: number = 20;
  static readonly CARD_PADDING: number = 16;
  static readonly ROW_RADIUS: number = 16;
  static readonly TITLE_BAR_HEIGHT: number = 56;

  static readonly TAB_BAR_BOTTOM_MARGIN: number = 20;
  static readonly CONTENT_BOTTOM_INSET: number = 104;
  // HDS gives full-height scrollable tab content the full window; tall pages compensate
  // for the overlay title bar explicitly. Non-tall pages are inset by HdsNavigation.
  static readonly TALL_PAGE_TOP_INSET: number = 80;
  static readonly TAB_ICON_BOX: number = 28;
  static readonly TAB_ICON_OFFSET: number = 3;
  static readonly TAB_SYMBOL_SIZE: number = 22;

  static readonly FONT_TINY: number = 10;
  static readonly FONT_CAPTION: number = 12;
  static readonly FONT_CHIP: number = 13;
  static readonly FONT_BODY: number = 14;
  static readonly FONT_TITLE: number = 16;
  static readonly FONT_HEADING: number = 20;
  static readonly FONT_DISPLAY: number = 28;

  static readonly BRAND: ResourceColor = $r('sys.color.brand');
  static readonly TEXT_PRIMARY: ResourceColor = $r('sys.color.font_primary');
  static readonly TEXT_SECONDARY: ResourceColor = $r('sys.color.font_secondary');
  static readonly TEXT_TERTIARY: ResourceColor = $r('sys.color.font_tertiary');
  static readonly BG: ResourceColor = $r('sys.color.ohos_id_color_sub_background');
  static readonly CARD_BG: ResourceColor = $r('sys.color.ohos_id_color_card_bg');
  static readonly SHEET_BG: ResourceColor = $r('app.color.sheet_bg');
  static readonly SHEET_CARD_BG: ResourceColor = $r('app.color.sheet_card_bg');
  static readonly FAB_BG: ResourceColor = $r('app.color.fab_bg');
  static readonly DIVIDER: ResourceColor = $r('sys.color.ohos_id_color_list_separator');
  static readonly ON_BRAND: ResourceColor = Color.White;
}
