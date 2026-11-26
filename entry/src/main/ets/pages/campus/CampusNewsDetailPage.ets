import { common, Want } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';

/** In-app reader for news details; external browser stays one native click away. */
@Component
export struct CampusNewsDetailPage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  url: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();
  @State loading: boolean = true;

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

  private async openExternal(): Promise<void> {
    if (this.url.length === 0) {
      this.toast('链接不可用');
      return;
    }
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: this.url
      };
      await this.context().startAbility(want);
    } catch (error) {
      this.toast('无法打开浏览器');
    }
  }

  build() {
    HdsNavDestination() {
      Column() {
        Row({ space: 10 }) {
          Text('内容由网页提供')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .maxLines(1)
            .layoutWeight(1)
          Button('在浏览器打开')
            .height(32)
            .fontSize(AppTheme.FONT_CAPTION)
            .backgroundColor(AppTheme.CARD_BG)
            .fontColor(this.brandTextColor)
            .onClick(() => this.openExternal())
        }
        .width('100%')
        .height(48)
        .padding({ left: AppTheme.PAGE_PADDING, right: AppTheme.PAGE_PADDING })

        Stack() {
          if (this.url.length > 0) {
            Web({ src: this.url, controller: this.controller })
              .javaScriptAccess(true)
              .domStorageAccess(true)
              .fileAccess(false)
              .width('100%')
              .height('100%')
              .onPageBegin(() => {
                this.loading = true;
              })
              .onPageEnd(() => {
                this.loading = false;
              })
          } else {
            Column({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.doc_plaintext'))
                .fontSize(36)
                .fontColor([AppTheme.TEXT_TERTIARY])
              Text('新闻链接不可用')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }

          if (this.loading && this.url.length > 0) {
            Column({ space: 10 }) {
              LoadingProgress()
                .width(30)
                .height(30)
                .color(this.brandTextColor)
              Text('正在打开新闻…')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(AppTheme.BG)
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({ top: 96 })
      .backgroundColor(AppTheme.BG)
    }
    .titleBar(immersiveTitleBar('新闻详情'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
