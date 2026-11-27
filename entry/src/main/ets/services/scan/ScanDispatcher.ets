import { common, Want } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { UIContext } from '@kit.ArkUI';
import { Identifiers } from '../../common/Identifiers';
import { ScanPayload, ScanPayloadKind } from './ScanRoute';

/**
 * 把扫码结果落到具体动作上。
 *
 * - `http(s)` / `www.` 链接：交给系统默认浏览器；
 * - 校验位通过的 ISBN：回给调用方（当前是馆藏检索），不在这里硬编码导航；
 * - 其余文本：弹窗让用户自己决定复制 / 浏览器搜索 / 取消。
 *
 * 页面只负责调起扫码器和提供 UIContext，分派逻辑不绑定具体页面。
 */
export class ScanDispatcher {
  static async dispatch(
    ui: UIContext,
    payload: ScanPayload,
    onIsbn: (isbn: string) => void
  ): Promise<void> {
    if (payload.kind === ScanPayloadKind.URL) {
      await ScanDispatcher.openInBrowser(ui, payload.value);
      return;
    }
    if (payload.kind === ScanPayloadKind.ISBN) {
      onIsbn(payload.value);
      return;
    }
    ScanDispatcher.askForText(ui, payload.raw);
  }

  private static askForText(ui: UIContext, raw: string): void {
    const text: string = raw.trim();
    const shown: string = text.length > 120 ? `${text.substring(0, 120)}…` : text;
    ui.showAlertDialog({
      title: $r('app.string.scan_dialog_title'),
      message: shown,
      autoCancel: true,
      buttons: [
        {
          value: $r('app.string.scan_copy'),
          action: () => {
            ScanDispatcher.copy(ui, text);
          }
        },
        {
          value: $r('app.string.scan_search_web'),
          action: () => {
            ScanDispatcher.openInBrowser(ui, Identifiers.webSearchUrl(text));
          }
        },
        {
          value: $r('app.string.scan_cancel'),
          action: () => {
          }
        }
      ]
    });
  }

  private static async openInBrowser(ui: UIContext, url: string): Promise<void> {
    if (url.length === 0) {
      return;
    }
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url
      };
      const context: common.UIAbilityContext = ui.getHostContext() as common.UIAbilityContext;
      await context.startAbility(want);
    } catch (error) {
      ScanDispatcher.toast(ui, '无法打开链接');
    }
  }

  private static async copy(ui: UIContext, text: string): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      ScanDispatcher.toast(ui, '已复制');
    } catch (error) {
      ScanDispatcher.toast(ui, '复制失败');
    }
  }

  private static toast(ui: UIContext, message: string): void {
    try {
      ui.getPromptAction().showToast({ message: message });
    } catch (error) {
      // Toast is optional.
    }
  }
}
