import { common, Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { LibraryClient } from '../../services/library/LibraryClient';
import {
  LibraryBook,
  LibraryError,
  LibrarySearchField,
  LibrarySearchQuery,
  LibrarySearchResult,
  LibrarySort
} from '../../services/library/LibraryModels';

const OPAC_URL: string = 'https://opac.gdut.edu.cn';
const HISTORY_STORE: string = 'library_settings';
const HISTORY_KEY: string = 'search_history';
const HISTORY_MAX: number = 8;

interface FieldOption {
  field: LibrarySearchField;
  label: string;
}

const FIELD_OPTIONS: FieldOption[] = [
  { field: LibrarySearchField.ALL, label: '全部' },
  { field: LibrarySearchField.TITLE, label: '书名' },
  { field: LibrarySearchField.AUTHOR, label: '作者' },
  { field: LibrarySearchField.CALL_NO, label: '索书号' },
  { field: LibrarySearchField.ISBN, label: 'ISBN' }
];

/**
 * 馆藏检索：书架前的“这本书在不在、在哪个阅览室”。
 *
 * 走 OPAC 的公开目录接口，不需要统一认证登录，所以扫码进来的 ISBN 不会先撞上
 * 登录墙；失败时保留“在浏览器打开”这一条降级路径。
 */
@Component
export struct LibrarySearchPage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  /** 扫码传入的 ISBN 或其他预填关键字。 */
  initialQuery: string = '';
  onOpenBook: (book: LibraryBook) => void = () => {};

  @State keyword: string = '';
  @State field: LibrarySearchField = LibrarySearchField.ALL;
  @State sort: LibrarySort = LibrarySort.RELEVANCE;
  @State books: LibraryBook[] = [];
  @State total: number = 0;
  @State page: number = 0;
  @State loading: boolean = false;
  @State loadingMore: boolean = false;
  @State searched: boolean = false;
  @State error: string = '';
  @State history: string[] = [];
  private historyLoaded: boolean = false;

  aboutToAppear(): void {
    this.loadHistory();
    const query: string = this.initialQuery.trim();
    if (query.length > 0) {
      this.keyword = query;
      this.search(1);
    }
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      // Toast is optional.
    }
  }

  private async loadHistory(): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context(), HISTORY_STORE);
      const saved = await store.get(HISTORY_KEY, '[]');
      if (typeof saved === 'string' && saved.length > 0) {
        const parsed: string[] = JSON.parse(saved) as string[];
        if (Array.isArray(parsed)) {
          this.history = parsed;
        }
      }
    } catch (error) {
      // 历史记录不是必需项。
    } finally {
      this.historyLoaded = true;
    }
  }

  private async rememberKeyword(keyword: string): Promise<void> {
    if (!this.historyLoaded || keyword.length === 0) {
      return;
    }
    const next: string[] = [keyword];
    for (const item of this.history) {
      if (item !== keyword && next.length < HISTORY_MAX) {
        next.push(item);
      }
    }
    this.history = next;
    try {
      const store = await preferences.getPreferences(this.context(), HISTORY_STORE);
      await store.put(HISTORY_KEY, JSON.stringify(next));
      await store.flush();
    } catch (error) {
      // 写失败不影响检索。
    }
  }

  private async search(targetPage: number): Promise<void> {
    const keyword: string = this.keyword.trim();
    if (keyword.length === 0) {
      this.toast('请输入书名、作者、索书号或 ISBN');
      return;
    }
    if (this.loading || this.loadingMore) {
      return;
    }
    const first: boolean = targetPage <= 1;
    if (first) {
      this.loading = true;
      this.books = [];
      this.total = 0;
    } else {
      this.loadingMore = true;
    }
    this.error = '';
    try {
      const query: LibrarySearchQuery = { keyword: keyword, field: this.field, sort: this.sort };
      const result: LibrarySearchResult = await LibraryClient.searchBooks(query, targetPage);
      this.total = result.total;
      this.page = targetPage;
      this.books = first ? result.books : this.books.concat(result.books);
      this.searched = true;
      if (first && result.total > 0) {
        this.rememberKeyword(keyword);
      }
    } catch (failure) {
      const message: string = failure instanceof LibraryError ? failure.message : '馆藏检索失败';
      if (first) {
        this.error = message;
        this.searched = true;
      } else {
        this.toast(message);
      }
    } finally {
      this.loading = false;
      this.loadingMore = false;
    }
  }

  private loadMore(): void {
    if (this.loading || this.loadingMore) {
      return;
    }
    if (this.books.length === 0 || this.books.length >= this.total) {
      return;
    }
    this.search(this.page + 1);
  }

  private changeField(field: LibrarySearchField): void {
    if (this.field === field) {
      return;
    }
    this.field = field;
    if (this.searched && this.keyword.trim().length > 0) {
      this.search(1);
    }
  }

  private changeSort(sort: LibrarySort): void {
    if (this.sort === sort) {
      return;
    }
    this.sort = sort;
    if (this.searched && this.keyword.trim().length > 0) {
      this.search(1);
    }
  }

  private sortLabel(): string {
    if (this.sort === LibrarySort.TITLE) {
      return '题名';
    }
    if (this.sort === LibrarySort.NEWEST) {
      return '出版年';
    }
    return '相关度';
  }

  private async openOpac(): Promise<void> {
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: OPAC_URL
      };
      await this.context().startAbility(want);
    } catch (error) {
      this.toast('无法打开图书馆网站');
    }
  }

  private availability(book: LibraryBook): string {
    if (book.physicalCount === 0) {
      return '暂无馆藏';
    }
    return `在架 ${book.onShelfCount} / ${book.physicalCount}`;
  }

  private availabilityColor(book: LibraryBook): ResourceColor {
    return book.onShelfCount > 0 ? this.brandTextColor : AppTheme.TEXT_TERTIARY;
  }

  private static metaLine(book: LibraryBook): string {
    const parts: string[] = [];
    if (book.author.length > 0) {
      parts.push(book.author);
    }
    if (book.publisher.length > 0) {
      parts.push(book.publisher);
    }
    if (book.publishYear.length > 0) {
      parts.push(book.publishYear);
    }
    return parts.length > 0 ? parts.join(' · ') : '出版信息待补';
  }

  @Builder
  searchBar() {
    Row({ space: AppTheme.SPACE_SM }) {
      TextInput({ text: this.keyword, placeholder: '书名 / 作者 / 索书号 / ISBN' })
        .height(40)
        .layoutWeight(1)
        .fontSize(AppTheme.FONT_BODY)
        .backgroundColor(AppTheme.CARD_BG)
        .borderRadius(AppTheme.ROW_RADIUS)
        .enterKeyType(EnterKeyType.Search)
        .onChange((value: string) => {
          this.keyword = value;
        })
        .onSubmit(() => {
          this.search(1);
        })
      Button('检索')
        .height(40)
        .fontSize(AppTheme.FONT_BODY)
        .backgroundColor(this.brandColor)
        .fontColor(Color.White)
        .onClick(() => this.search(1))
    }
    .width('100%')
  }

  @Builder
  fieldChips() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(FIELD_OPTIONS, (option: FieldOption) => {
          Text(option.label)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(this.field === option.field ? Color.White : AppTheme.TEXT_SECONDARY)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(this.field === option.field ? this.brandColor : AppTheme.CARD_BG)
            .borderRadius(14)
            .onClick(() => this.changeField(option.field))
        }, (option: FieldOption) => option.field)
      }
      .padding({ right: 4 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .align(Alignment.Start)
  }

  @Builder
  resultHeader() {
    Row({ space: 8 }) {
      Text(this.keyword.trim())
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(`共 ${this.total} 条`)
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(AppTheme.TEXT_TERTIARY)
      Text(`排序 · ${this.sortLabel()} ▾`)
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(this.brandTextColor)
        .bindMenu([
          {
            value: '相关度',
            action: () => {
              this.changeSort(LibrarySort.RELEVANCE);
            }
          },
          {
            value: '题名',
            action: () => {
              this.changeSort(LibrarySort.TITLE);
            }
          },
          {
            value: '出版年',
            action: () => {
              this.changeSort(LibrarySort.NEWEST);
            }
          }
        ])
    }
    .width('100%')
  }

  @Builder
  bookCard(book: LibraryBook) {
    Column({ space: 6 }) {
      Text(book.title.length > 0 ? book.title : '未命名图书')
        .fontSize(AppTheme.FONT_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(LibrarySearchPage.metaLine(book))
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row({ space: AppTheme.SPACE_SM }) {
        if (book.callNo.length > 0) {
          Text(book.callNo)
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(this.brandTextColor)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
            .backgroundColor(AppTheme.BG)
        }
        Blank()
        Text(this.availability(book))
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(this.availabilityColor(book))
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => this.onOpenBook(book))
  }

  @Builder
  placeholderCard(text: string, hint: string) {
    Column({ space: AppTheme.SPACE_SM }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(30)
        .fontColor([AppTheme.TEXT_TERTIARY])
      Text(text)
        .fontSize(AppTheme.FONT_BODY)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
      if (hint.length > 0) {
        Text(hint)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .padding(AppTheme.SPACE_XL)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  historyBlock() {
    Column({ space: AppTheme.SPACE_SM }) {
      Text('最近检索')
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .width('100%')
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.history, (item: string) => {
            Text(item)
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(AppTheme.CARD_BG)
              .borderRadius(14)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => {
                this.keyword = item;
                this.search(1);
              })
          }, (item: string) => item)
        }
        .padding({ right: 4 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .align(Alignment.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavDestination() {
      Column({ space: AppTheme.SPACE_MD }) {
        this.searchBar()
        this.fieldChips()

        if (this.loading && this.books.length === 0) {
          Column({ space: 8 }) {
            LoadingProgress()
              .width(28)
              .height(28)
              .color(this.brandTextColor)
            Text('正在检索馆藏…')
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_TERTIARY)
          }
          .width('100%')
          .height(140)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.error.length > 0) {
          Column({ space: 10 }) {
            Text(this.error)
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
            Row({ space: 18 }) {
              Text('重新检索')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(this.brandTextColor)
                .onClick(() => this.search(1))
              Text('在浏览器打开')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
                .onClick(() => this.openOpac())
            }
            .justifyContent(FlexAlign.Center)
          }
          .width('100%')
          .padding(AppTheme.SPACE_XL)
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(AppTheme.CARD_RADIUS)
          .alignItems(HorizontalAlign.Center)
        } else if (this.searched && this.books.length === 0) {
          this.placeholderCard('没有找到匹配的书目', '试试完整书名、作者，或书背的 ISBN')
        } else if (!this.searched) {
          this.placeholderCard('检索馆藏', '支持书名、作者、索书号、ISBN；也可直接扫描书背条码')
          if (this.history.length > 0) {
            this.historyBlock()
          }
        } else {
          this.resultHeader()

          List({ space: AppTheme.SPACE_SM }) {
            ForEach(this.books, (book: LibraryBook) => {
              ListItem() {
                this.bookCard(book)
              }
            }, (book: LibraryBook) => book.recordId.length > 0
              ? `${book.recordId}-${book.publisher}`
              : `${book.title}-${book.isbn}`)

            if (this.books.length < this.total) {
              ListItem() {
                Row({ space: 8 }) {
                  if (this.loadingMore) {
                    LoadingProgress()
                      .width(16)
                      .height(16)
                      .color(this.brandTextColor)
                  }
                  Text(this.loadingMore ? '加载中…' : '加载更多')
                    .fontSize(AppTheme.FONT_CAPTION)
                    .fontColor(this.brandTextColor)
                }
                .width('100%')
                .height(44)
                .justifyContent(FlexAlign.Center)
                .onClick(() => this.loadMore())
              }
            }
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
          .onReachEnd(() => this.loadMore())
        }
      }
      .width('100%')
      .height('100%')
      .padding({
        left: AppTheme.PAGE_PADDING,
        right: AppTheme.PAGE_PADDING,
        top: AppTheme.TALL_PAGE_TOP_INSET + 12,
        bottom: AppTheme.PAGE_PADDING
      })
      .alignItems(HorizontalAlign.Start)
    }
    .titleBar(immersiveTitleBar('馆藏检索'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
