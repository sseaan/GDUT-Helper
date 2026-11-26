import { webview } from '@kit.ArkWeb';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { LibrarySession } from '../../services/library/LibrarySession';

const SSO_URL: string =
  'https://opac.gdut.edu.cn/sso-cas/cas/gdut/init?refer=https%3A%2F%2Fopac.gdut.edu.cn%2Ffind%2Fsso%2Flogin%2Fgdut%2F0%3FpageType%3D0%26navigation%3D1';

@Component
export struct LibraryLoginPage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  onDone: () => void = () => {};

  private controller: webview.WebviewController = new webview.WebviewController();
  @State loading: boolean = true;
  @State message: string = '';

  private queryParam(url: string, name: string): string {
    const marker: string = `${name}=`;
    let index: number = url.indexOf(marker);
    if (index < 0) {
      return '';
    }
    index += marker.length;
    let end: number = url.indexOf('&', index);
    if (end < 0) {
      end = url.indexOf('#', index);
    }
    if (end < 0) {
      end = url.length;
    }
    try {
      return decodeURIComponent(url.substring(index, end));
    } catch (error) {
      return url.substring(index, end);
    }
  }

  private checkUrlSession(url: string): boolean {
    if (!url.includes('opac.gdut.edu.cn')) {
      return false;
    }
    const jwt: string = this.queryParam(url, 'jwt');
    if (jwt.length === 0) {
      return false;
    }
    const header: string = this.queryParam(url, 'jwtHeader');
    LibrarySession.setCookie(`jwt=${jwt}; jwtHeader=${header.length > 0 ? header : 'jwtOpacAuth'}`);
    this.onDone();
    return true;
  }

  private checkCookies(url: string): void {
    this.loading = false;
    if (!url.includes('opac.gdut.edu.cn') || url.includes('sso-cas')) {
      return;
    }
    if (this.checkUrlSession(url)) {
      return;
    }
    try {
      const cookie: string = webview.WebCookieManager.fetchCookieSync('https://opac.gdut.edu.cn');
      if (cookie.includes('jwt=')) {
        LibrarySession.setCookie(cookie);
        this.onDone();
      } else {
        this.message = '登录完成，但未读取到图书馆会话，请重试';
      }
    } catch (error) {
      this.message = '无法读取图书馆会话，请重试';
    }
  }

  build() {
    HdsNavDestination() {
      Column() {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.lock_shield'))
            .fontSize(14)
            .fontColor([AppTheme.TEXT_TERTIARY])
          Text('使用学校统一认证登录图书馆，登录成功后自动返回')
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
          Web({ src: SSO_URL, controller: this.controller })
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .fileAccess(false)
            .width('100%')
            .height('100%')
            .onPageEnd((event: OnPageEndEvent) => {
              this.checkCookies(event.url);
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
              Text('正在打开图书馆统一认证…')
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
    .titleBar(immersiveTitleBar('登录图书馆'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
