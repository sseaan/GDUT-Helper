import { common, Want } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { LibraryClient } from '../../services/library/LibraryClient';
import { LibraryBook, LibraryError, LibraryHolding } from '../../services/library/LibraryModels';

const OPAC_URL: string = 'https://opac.gdut.edu.cn';
const ABSTRACT_COLLAPSED_LINES: number = 5;

interface HoldingGroup {
  location: string;
  total: number;
  onShelf: number;
  items: LibraryHolding[];
}

/**
 * 书目详情：题录 + 摘要 + 分馆藏地的册信息。
 *
 * 书目本身由检索页通过路由参数带进来（检索结果里已含题录字段），
 * 本页只额外拉一次 `/find/physical/groupitems` 的册信息。
 */
@Component
export struct LibraryBookPage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  book: LibraryBook = {
    recordId: '', title: '', author: '', publisher: '', isbn: '', publishYear: '',
    callNo: '', price: '', pageCount: '', subject: '',
    physicalCount: 0, onShelfCount: 0, abstractText: ''
  };

  @State holdings: LibraryHolding[] = [];
  @State loading: boolean = false;
  @State error: string = '';
  @State abstractOpen: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    if (this.book.recordId.length === 0) {
      this.error = '缺少书目编号';
      return;
    }
    this.loading = true;
    this.error = '';
    try {
      this.holdings = await LibraryClient.fetchHoldings(this.book.recordId);
    } catch (failure) {
      this.error = failure instanceof LibraryError ? failure.message : '馆藏信息加载失败';
    } finally {
      this.loading = false;
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      // Toast is optional.
    }
  }

  private async openOpac(): Promise<void> {
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: OPAC_URL
      };
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await context.startAbility(want);
    } catch (error) {
      this.toast('无法打开图书馆网站');
    }
  }

  private isOnShelf(holding: LibraryHolding): boolean {
    return holding.status.indexOf('借出') < 0 && holding.status.indexOf('在架') >= 0;
  }

  private holdingsOnShelf(): number {
    let count: number = 0;
    for (const holding of this.holdings) {
      if (this.isOnShelf(holding)) {
        count++;
      }
    }
    return count;
  }

  /** 按馆藏地归并，在架多的排前面。 */
  private groups(): HoldingGroup[] {
    const result: HoldingGroup[] = [];
    for (const holding of this.holdings) {
      const location: string = holding.location.length > 0 ? holding.location : '馆藏地待定';
      let group: HoldingGroup | null = null;
      for (const existing of result) {
        if (existing.location === location) {
          group = existing;
          break;
        }
      }
      if (group === null) {
        group = { location: location, total: 0, onShelf: 0, items: [] };
        result.push(group);
      }
      group.total += 1;
      if (this.isOnShelf(holding)) {
        group.onShelf += 1;
      }
      group.items.push(holding);
    }
    result.sort((left: HoldingGroup, right: HoldingGroup) => {
      if (left.onShelf !== right.onShelf) {
        return right.onShelf - left.onShelf;
      }
      return left.location.localeCompare(right.location);
    });
    return result;
  }

  private metaLine(): string {
    const parts: string[] = [];
    if (this.book.author.length > 0) {
      parts.push(this.book.author);
    }
    if (this.book.publisher.length > 0) {
      parts.push(this.book.publisher);
    }
    if (this.book.publishYear.length > 0) {
      parts.push(this.book.publishYear);
    }
    return parts.length > 0 ? parts.join(' · ') : '出版信息待补';
  }

  @Builder
  metaRow(label: string, value: string) {
    if (value.length > 0) {
      Row({ space: AppTheme.SPACE_SM }) {
        Text(label)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .width(52)
        Text(value)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
  }

  @Builder
  headerCard() {
    Column({ space: 8 }) {
      Text(this.book.title.length > 0 ? this.book.title : '未命名图书')
        .fontSize(AppTheme.FONT_HEADING)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .width('100%')
      Text(this.metaLine())
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .width('100%')

      Row({ space: 6 }) {
        Text(`在架 ${this.book.onShelfCount}`)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.book.onShelfCount > 0 ? this.brandTextColor : AppTheme.TEXT_TERTIARY)
        Text(`/ 馆藏 ${this.book.physicalCount}`)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_TERTIARY)
        Blank()
        if (this.book.callNo.length > 0) {
          Text(this.book.callNo)
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(this.brandTextColor)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
            .backgroundColor(AppTheme.BG)
        }
      }
      .width('100%')

      Divider().color(AppTheme.DIVIDER).opacity(0.5)

      this.metaRow('ISBN', this.book.isbn)
      this.metaRow('页数', this.book.pageCount)
      this.metaRow('定价', this.book.price.length > 0 ? `¥ ${this.book.price}` : '')
      this.metaRow('主题', this.book.subject)
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  abstractCard() {
    Column({ space: 6 }) {
      Text('内容简介')
        .fontSize(AppTheme.FONT_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .width('100%')
      Text(this.book.abstractText)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .lineHeight(19)
        .maxLines(this.abstractOpen ? 200 : ABSTRACT_COLLAPSED_LINES)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (this.book.abstractText.length > 80) {
        Text(this.abstractOpen ? '收起' : '展开全部')
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(this.brandTextColor)
          .onClick(() => {
            this.abstractOpen = !this.abstractOpen;
          })
      }
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  holdingRow(holding: LibraryHolding) {
    Row({ space: AppTheme.SPACE_SM }) {
      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(holding.barcode.length > 0 ? `条码 ${holding.barcode}` : '条码待定')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_SECONDARY)
          if (holding.vol.length > 0) {
            Text(`第 ${holding.vol} 卷`)
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_TERTIARY)
          }
        }
        if (holding.callNo.length > 0) {
          Text(`索书号 ${holding.callNo}`)
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.isOnShelf(holding)
        ? '在架'
        : (holding.status.length > 0 ? holding.status : '状态未知'))
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(this.isOnShelf(holding) ? this.brandTextColor : AppTheme.TEXT_TERTIARY)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(120)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  groupCard(group: HoldingGroup) {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Text(group.location)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`在架 ${group.onShelf} / ${group.total}`)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(group.onShelf > 0 ? this.brandTextColor : AppTheme.TEXT_TERTIARY)
      }
      .width('100%')

      ForEach(group.items, (holding: LibraryHolding) => {
        this.holdingRow(holding)
      }, (holding: LibraryHolding) => holding.itemId.length > 0
        ? holding.itemId : `${holding.barcode}-${holding.location}`)
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  stateCard(text: string, hint: string) {
    Column({ space: AppTheme.SPACE_SM }) {
      SymbolGlyph($r('sys.symbol.list_square'))
        .fontSize(30)
        .fontColor([AppTheme.TEXT_TERTIARY])
      Text(text)
        .fontSize(AppTheme.FONT_BODY)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
      if (hint.length > 0) {
        Text(hint)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(this.brandTextColor)
          .textAlign(TextAlign.Center)
          .onClick(() => this.load())
      }
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
          this.headerCard()

          if (this.book.abstractText.length > 0) {
            this.abstractCard()
          }

          Row() {
            Text('馆藏')
              .fontSize(AppTheme.FONT_TITLE)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.TEXT_PRIMARY)
            Blank()
            if (this.holdings.length > 0) {
              Text(`${this.holdingsOnShelf()} / ${this.holdings.length} 册在架`)
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_TERTIARY)
            }
          }
          .width('100%')

          if (this.loading) {
            Column({ space: 8 }) {
              LoadingProgress()
                .width(28)
                .height(28)
                .color(this.brandTextColor)
              Text('正在读取馆藏…')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_TERTIARY)
            }
            .width('100%')
            .height(140)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.error.length > 0) {
            this.stateCard(this.error, '重新加载')
          } else if (this.holdings.length === 0) {
            Column({ space: 8 }) {
              Image($r('app.media.ic_library_book'))
                .width(30)
                .height(30)
                .fillColor(AppTheme.TEXT_TERTIARY)
              Text('该图书暂无纸质馆藏记录')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
            }
            .width('100%')
            .height(130)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(AppTheme.CARD_BG)
            .borderRadius(AppTheme.CARD_RADIUS)
          } else {
            ForEach(this.groups(), (group: HoldingGroup) => {
              this.groupCard(group)
            }, (group: HoldingGroup) => `${group.location}-${group.total}`)
          }

          Row({ space: 6 }) {
            Text('数据来自学校图书馆 OPAC')
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_TERTIARY)
            Text('· 在浏览器打开')
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(this.brandTextColor)
              .onClick(() => this.openOpac())
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 4, bottom: 8 })
        }
        .width('100%')
        .padding({
          left: AppTheme.PAGE_PADDING,
          right: AppTheme.PAGE_PADDING,
          top: AppTheme.TALL_PAGE_TOP_INSET + 20,
          bottom: AppTheme.PAGE_PADDING
        })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .titleBar(immersiveTitleBar('书目详情'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
