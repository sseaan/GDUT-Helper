import { AppTheme } from '../../common/Theme';

@Component
export struct CampusPage {
  onOpenClassroom: () => void = () => {};
  onOpenGrades: () => void = () => {};
  onOpenPhysical: () => void = () => {};
  onOpenPlaceholder: (title: string) => void = () => {};

  @Builder
  serviceCard(icon: Resource, title: ResourceStr, desc: ResourceStr, action: () => void) {
    Column({ space: AppTheme.SPACE_SM }) {
      SymbolGlyph(icon)
        .fontSize(26)
        .fontColor([AppTheme.BRAND])
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
    .height(126)
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .onClick(action)
  }

  @Builder
  moreRow(icon: Resource, title: ResourceStr, action: () => void) {
    Row({ space: AppTheme.SPACE_MD }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([AppTheme.TEXT_SECONDARY])
      Text(title)
        .fontSize(AppTheme.FONT_BODY)
        .fontColor(AppTheme.TEXT_PRIMARY)
      Blank()
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([AppTheme.TEXT_TERTIARY])
    }
    .width('100%')
    .height(52)
    .padding({ left: AppTheme.CARD_PADDING, right: AppTheme.CARD_PADDING })
    .onClick(action)
  }

  build() {
    Scroll() {
      Column({ space: AppTheme.SPACE_LG }) {
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
              () => this.onOpenPlaceholder('更多服务')
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
        top: AppTheme.PAGE_PADDING,
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
