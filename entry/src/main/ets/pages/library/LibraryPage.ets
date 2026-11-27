import { common, Want } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { LibraryClient } from '../../services/library/LibraryClient';
import {
  LibraryError,
  LibraryErrorKind,
  LibraryLoan,
  LibraryOverview
} from '../../services/library/LibraryModels';

const OPAC_URL: string = 'https://opac.gdut.edu.cn';

@Component
export struct LibraryPage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  onOpenLogin: () => void = () => {};
  onOpenSearch: (keyword: string) => void = () => {};

  @StorageLink('jxfwSessionRevision') @Watch('onSessionRevision') sessionRevision: number = 0;
  @StorageLink('librarySessionRevision') @Watch('onLibrarySession') libraryRevision: number = 0;
  @State overview: LibraryOverview | null = null;
  @State loading: boolean = false;
  @State error: string = '';
  @State needLogin: boolean = false;
  @State searchKeyword: string = '';

  aboutToAppear(): void {
    this.load(false);
  }

  private onSessionRevision(): void {
    this.load(true);
  }

  private onLibrarySession(): void {
    this.load(true);
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

  private async load(force: boolean): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.error = '';
    this.needLogin = false;
    try {
      this.overview = await LibraryClient.fetchOverview();
    } catch (error) {
      if (error instanceof LibraryError) {
        this.error = error.message;
        this.needLogin = error.kind === LibraryErrorKind.CREDENTIALS ||
          error.kind === LibraryErrorKind.SESSION;
      } else {
        this.error = '图书馆数据加载失败';
      }
    } finally {
      this.loading = false;
    }
  }

  private async openExternal(): Promise<void> {
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

  private loanDueLabel(loan: LibraryLoan): string {
    return loan.dueDate.length > 0 ? `应还 ${loan.dueDate}` : '应还日期待定';
  }

  private submitSearch(): void {
    const keyword: string = this.searchKeyword.trim();
    if (keyword.length === 0) {
      this.toast('请输入书名、作者或 ISBN');
      return;
    }
    this.onOpenSearch(keyword);
  }

  @Builder
  searchBar() {
    Row() {
      Row({ space: AppTheme.SPACE_SM }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(17)
          .fontColor([AppTheme.TEXT_TERTIARY])
        TextInput({ text: this.searchKeyword, placeholder: '搜书名、作者或 ISBN' })
          .layoutWeight(1)
          .height(40)
          .padding(0)
          .fontSize(AppTheme.FONT_BODY)
          .backgroundColor(Color.Transparent)
          .enterKeyType(EnterKeyType.Search)
          .onChange((value: string) => {
            this.searchKeyword = value;
          })
          .onSubmit(() => {
            this.submitSearch();
          })
        if (this.searchKeyword.length > 0) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(14)
            .fontColor([AppTheme.TEXT_TERTIARY])
            .padding(4)
            .onClick(() => {
              this.searchKeyword = '';
            })
        }
        Button('检索')
          .height(32)
          .fontSize(AppTheme.FONT_CAPTION)
          .backgroundColor(this.brandColor)
          .fontColor(Color.White)
          .onClick(() => this.submitSearch())
      }
      .width('100%')
      .height(48)
      .padding({ left: 14, right: 6 })
      .backgroundColor(AppTheme.CARD_BG)
      .borderRadius(24)
    }
    .width('100%')
    .padding({
      left: AppTheme.PAGE_PADDING,
      right: AppTheme.PAGE_PADDING,
      top: AppTheme.TALL_PAGE_TOP_INSET + 12,
      bottom: AppTheme.SPACE_SM
    })
  }

  @Builder
  sectionHeader(title: string, trailing: string) {
    Row() {
      Text(title)
        .fontSize(AppTheme.FONT_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_PRIMARY)
      Blank()
      if (trailing.length > 0) {
        Text(trailing)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_TERTIARY)
      }
    }
    .width('100%')
  }

  @Builder
  headerCard() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Image($r('app.media.ic_library_book'))
          .width(23)
          .height(23)
          .fillColor(this.brandTextColor)
        Text(this.overview === null || this.overview.user.name.length === 0
          ? '图书馆' : this.overview.user.name)
          .fontSize(AppTheme.FONT_HEADING)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
        Blank()
        Button('在浏览器打开')
          .height(32)
          .fontSize(AppTheme.FONT_CAPTION)
          .backgroundColor(AppTheme.BG)
          .fontColor(this.brandTextColor)
          .onClick(() => this.openExternal())
      }
      .width('100%')

      if (this.overview !== null) {
        Text(this.overview.user.unit.length > 0 ? this.overview.user.unit : '广东工业大学')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .width('100%')
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text(`${this.overview.loanQuota}`)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.brandTextColor)
            Text('当前可借')
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_SECONDARY)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          Column({ space: 2 }) {
            Text(`${this.overview.loans.length}`)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.brandTextColor)
            Text('当前借阅')
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_SECONDARY)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .padding({ top: 4, bottom: 2 })
      }
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  loanCard(loan: LibraryLoan) {
    Column({ space: 5 }) {
      Text(loan.title.length > 0 ? loan.title : '未命名图书')
        .fontSize(AppTheme.FONT_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (loan.author.length > 0) {
        Text(loan.author)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .maxLines(1)
      }
      Row({ space: 8 }) {
        Text(this.loanDueLabel(loan))
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .maxLines(1)
        if (loan.location.length > 0) {
          Text(`· ${loan.location}`)
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .maxLines(1)
            .layoutWeight(1)
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  errorCard() {
    Column({ space: 10 }) {
      Text(this.error.length > 0 ? this.error : '图书馆数据加载失败')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .lineHeight(18)
      Row({ space: 18 }) {
        Text('登录图书馆')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(this.brandTextColor)
          .onClick(() => this.onOpenLogin())
        Text('重新加载')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .onClick(() => this.load(true))
      }
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding(AppTheme.SPACE_XL)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    HdsNavDestination() {
      Column() {
        // 馆藏检索走 OPAC 公开目录，不依赖登录态，所以搜索栏固定在顶部常驻。
        this.searchBar()

        Scroll() {
          Column({ space: AppTheme.SPACE_MD }) {
            this.headerCard()

            this.sectionHeader('当前借阅',
              this.overview !== null ? `共 ${this.overview.total} 条` : '')

            if (this.loading && this.overview === null) {
              Column({ space: 8 }) {
                LoadingProgress()
                  .width(28)
                  .height(28)
                  .color(this.brandTextColor)
                Text('正在同步图书馆…')
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(AppTheme.TEXT_TERTIARY)
              }
              .width('100%')
              .height(150)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .backgroundColor(AppTheme.CARD_BG)
              .borderRadius(AppTheme.CARD_RADIUS)
            } else if (this.error.length > 0) {
              this.errorCard()
            } else if (this.overview === null || this.overview.loans.length === 0) {
              Column({ space: 8 }) {
                Image($r('app.media.ic_library_book'))
                  .width(32)
                  .height(32)
                  .fillColor(AppTheme.TEXT_TERTIARY)
                Text('当前没有借阅')
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
              ForEach(this.overview.loans, (loan: LibraryLoan) => {
                this.loanCard(loan)
              }, (loan: LibraryLoan) => loan.id.length > 0 ? loan.id : `${loan.title}-${loan.dueDate}`)
            }

            Text('借阅数据来自学校图书馆 OPAC；到期提醒功能后续接入。')
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_TERTIARY)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 4 })
          }
          .width('100%')
          .padding({
            left: AppTheme.PAGE_PADDING,
            right: AppTheme.PAGE_PADDING,
            top: AppTheme.SPACE_SM,
            bottom: AppTheme.CONTENT_BOTTOM_INSET
          })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.TopStart)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
    }
    .titleBar(immersiveTitleBar('图书馆'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
