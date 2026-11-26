import { webview } from '@kit.ArkWeb';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { TzcsSession } from '../../services/tzcs/TzcsSession';

const LOGIN_URL: string = 'http://tzcs.gdut.edu.cn/Src/PlatForm/user/Login_m.aspx?Mode=2&SchoolCode=84223B2F7B9F3A91A2F9913135761855';

@Component
export struct TzcsLoginPage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  onDone: () => void = () => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  @State loading: boolean = true;
  @State message: string = '';

  private checkPage(url: string): void {
    this.loading = false;
    if (!url.includes('Personal')) {
      return;
    }
    try {
      const cookie: string = webview.WebCookieManager.fetchCookieSync('http://tzcs.gdut.edu.cn');
      if (cookie.includes('KeKaoStudentCookies') || cookie.includes('St_NO=')) {
        TzcsSession.setCookie(cookie);
        this.onDone();
      } else {
        this.message = '已登录，但未读取到体测会话 Cookie';
      }
    } catch (error) {
      this.message = '无法读取登录 Cookie，请重试';
    }
  }

  build() {
    HdsNavDestination() {
      Column() {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.lock_shield'))
            .fontSize(14)
            .fontColor([AppTheme.TEXT_TERTIARY])
          Text('在校园网/VPN 下完成体测平台登录，成功后将自动返回')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .layoutWeight(1)
          if (this.message.length > 0) {
            Text(this.message)
              .fontSize(AppTheme.FONT_TINY)
              .fontColor('#C7362B')
          }
        }
        .width('100%')
        .height(38)
        .padding({ left: AppTheme.PAGE_PADDING, right: AppTheme.PAGE_PADDING })

        Stack() {
          Web({ src: LOGIN_URL, controller: this.controller })
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .fileAccess(false)
            .width('100%')
            .height('100%')
            .onPageEnd((event: OnPageEndEvent) => {
              this.loading = false;
              this.checkPage(event.url);
            })
            .onPageBegin(() => {
              this.loading = true;
            })
          if (this.loading) {
            Column({ space: 10 }) {
              LoadingProgress()
                .width(30)
                .height(30)
                .color(this.brandTextColor)
              Text('正在打开体测平台…')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
            }
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
    .titleBar(immersiveTitleBar('体测登录'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
