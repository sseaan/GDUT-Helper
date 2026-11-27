import { common, Want } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';

@Component
export struct AboutPage {
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

  private async copyGroup(): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, '1103357499');
      await pasteboard.getSystemPasteboard().setData(data);
      this.toast('群号已复制');
    } catch (error) {
      this.toast('复制失败，请手动记录群号');
    }
  }

  private async openProject(): Promise<void> {
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: 'https://github.com/sseaan/GDUT-Helper'
      };
      await this.context().startAbility(want);
    } catch (error) {
      this.toast('无法打开项目主页');
    }
  }

  @Builder
  sectionLabel(text: string) {
    Text(text)
      .fontSize(AppTheme.FONT_TINY)
      .fontColor(AppTheme.TEXT_TERTIARY)
      .width('100%')
      .padding({ left: 6, top: 4 })
  }

  @Builder
  infoRow(title: string, value: string, detail: string, chevron: boolean, onTap: () => void) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(title)
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_PRIMARY)
        if (detail.length > 0) {
          Text(detail)
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .maxLines(2)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (value.length > 0) {
        Text(value)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .maxLines(1)
      }
      if (chevron) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(13)
          .fontColor([AppTheme.TEXT_TERTIARY])
      }
    }
    .width('100%')
    .height(detail.length > 0 ? 64 : 54)
    .padding({ left: 16, right: 16 })
    .onClick(onTap)
  }

  @Builder
  simpleRow(title: string, detail: string) {
    Column({ space: 3 }) {
      Text(title)
        .fontSize(AppTheme.FONT_BODY)
        .fontColor(AppTheme.TEXT_PRIMARY)
      if (detail.length > 0) {
        Text(detail)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_TERTIARY)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: 14 }) {
          Row({ space: 12 }) {
            Image($r('app.media.icon'))
              .width(64)
              .height(64)
              .borderRadius(16)
              .objectFit(ImageFit.Cover)
            Column({ space: 4 }) {
              Row({ space: 8 }) {
                Text('工大助手')
                  .fontSize(24)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppTheme.TEXT_PRIMARY)
                Text('v1.2.0')
                  .fontSize(AppTheme.FONT_TINY)
                  .fontColor(AppTheme.TEXT_SECONDARY)
                  .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                  .backgroundColor(AppTheme.CARD_BG)
                  .borderRadius(8)
              }
              Text('广工课表与校园服务')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.profile_card_bg'))
          .borderRadius(18)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 0.5, color: '#66FFFFFF' })

          this.sectionLabel('版本与更新')
          Column() {
            this.infoRow('检查更新', '1.2.0', '当前已是最新版本', true, () => this.toast('当前已是最新版本'))
            Divider().color(AppTheme.DIVIDER).opacity(0.5).margin({ left: 16, right: 16 })
            this.infoRow('项目主页', '', 'GitHub · sseaan/GDUT-Helper', true, () => this.openProject())
          }
          .width('100%')
          .backgroundColor($r('app.color.profile_card_bg'))
          .borderRadius(18)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 0.5, color: '#66FFFFFF' })
          .clip(true)

          this.sectionLabel('交流群')
          Column() {
            this.infoRow('工大助手交流群', '1103357499', 'QQ 1103357499 · 点击复制群号', true, () => this.copyGroup())
          }
          .width('100%')
          .backgroundColor($r('app.color.profile_card_bg'))
          .borderRadius(18)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 0.5, color: '#66FFFFFF' })
          .clip(true)

          this.sectionLabel('开源协议')
          Column() {
            this.infoRow('开源许可', 'AGPL-3.0', '本项目采用 GNU Affero General Public License v3.0', false, () => {})
          }
          .width('100%')
          .backgroundColor($r('app.color.profile_card_bg'))
          .borderRadius(18)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 0.5, color: '#66FFFFFF' })
          .clip(true)

          this.sectionLabel('致谢')
          Column() {
            this.simpleRow('HarmonyOS & ArkUI', '鸿蒙系统能力、HDS 与 ArkUI 组件')
            Divider().color(AppTheme.DIVIDER).opacity(0.5).margin({ left: 16, right: 16 })
            this.simpleRow('Goke', '教务、空教室接口调研与交互参考')
            Divider().color(AppTheme.DIVIDER).opacity(0.5).margin({ left: 16, right: 16 })
            this.simpleRow('开源社区与反馈同学', '感谢提供建议、反馈和课表样本的每一位同学')
          }
          .width('100%')
          .backgroundColor($r('app.color.profile_card_bg'))
          .borderRadius(18)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 0.5, color: '#66FFFFFF' })
          .clip(true)

          Text('数据保存在本机 · 不含账号密码与登录凭据')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 8, bottom: 16 })
        }
        .width('100%')
        .padding({
          left: AppTheme.PAGE_PADDING,
          right: AppTheme.PAGE_PADDING,
          top: AppTheme.TALL_PAGE_TOP_INSET + 24,
          bottom: AppTheme.CONTENT_BOTTOM_INSET
        })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .titleBar(immersiveTitleBar('关于'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
