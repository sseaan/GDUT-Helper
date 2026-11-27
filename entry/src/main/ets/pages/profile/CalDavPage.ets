import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { CalDavClient } from '../../services/caldav/CalDavClient';
import { CalDavConfig, CalDavError, CalDavPushResult } from '../../services/caldav/CalDavModels';
import { CalDavSettings } from '../../services/caldav/CalDavSettings';
import { CalDavSyncService } from '../../services/caldav/CalDavSyncService';

/**
 * 日历同步（CalDAV）。
 *
 * 单向：把当前学期课表整份覆盖到用户自己的日历集合。HarmonyOS 的 http 没有
 * PROPFIND / MKCALENDAR，所以这里不发现、不建日历，地址由用户从日历客户端里复制。
 */
@Component
export struct CalDavPage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('brandColor') brandColor: string = '#0A59F7';

  @State url: string = '';
  @State username: string = '';
  @State password: string = '';
  @State autoPush: boolean = false;
  @State busy: boolean = false;
  @State status: string = '';
  @State error: string = '';
  @State lastPushedAt: number = 0;
  @State lastEventCount: number = 0;
  @State progress: string = '';

  aboutToAppear(): void {
    this.load();
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

  private async load(): Promise<void> {
    const config: CalDavConfig = await CalDavSettings.load(this.context());
    this.url = config.url;
    this.username = config.username;
    this.autoPush = config.enabled;
    this.lastPushedAt = config.lastPushedAt;
    this.lastEventCount = config.lastEventCount;
    this.password = await CalDavSettings.password();
  }

  private async persist(): Promise<boolean> {
    const normalized: string = CalDavClient.normalize(this.url);
    if (normalized.length === 0) {
      this.error = '请填写日历集合地址';
      return false;
    }
    this.url = normalized;
    const config: CalDavConfig = await CalDavSettings.load(this.context());
    config.url = normalized;
    config.username = this.username.trim();
    config.enabled = this.autoPush;
    try {
      await CalDavSettings.save(this.context(), config);
      await CalDavSettings.savePassword(this.password);
      return true;
    } catch (error) {
      this.error = '保存设置失败';
      return false;
    }
  }

  private async saveAndTest(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.error = '';
    this.status = '';
    if (!await this.persist()) {
      return;
    }
    this.busy = true;
    try {
      const config: CalDavConfig = await CalDavSettings.load(this.context());
      await CalDavClient.probe(config, this.password);
      this.status = '连接成功，可以推送课表了';
      this.toast('日历服务器连接成功');
    } catch (failure) {
      this.error = failure instanceof CalDavError ? failure.message : '连接失败';
    } finally {
      this.busy = false;
    }
  }

  private async pushNow(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.error = '';
    this.status = '';
    this.progress = '';
    if (!await this.persist()) {
      return;
    }
    this.busy = true;
    try {
      const result: CalDavPushResult = await CalDavSyncService.push(this.context(),
        (done: number, total: number) => {
          this.progress = `正在推送 ${done}/${total}`;
        });
      const config: CalDavConfig = await CalDavSettings.load(this.context());
      this.lastPushedAt = config.lastPushedAt;
      this.lastEventCount = result.events;
      this.status = result.failed > 0
        ? `推送完成，但有 ${result.failed} 个事件失败；新增 ${result.uploaded}，删除 ${result.deleted}`
        : `已同步 ${result.events} 个事件：写入 ${result.uploaded}，删除 ${result.deleted}，` +
          `未变化 ${result.unchanged}`;
      this.toast(result.failed > 0 ? '部分事件推送失败' : '课表已同步到日历');
    } catch (failure) {
      this.error = failure instanceof CalDavError ? failure.message
        : (failure instanceof Error ? failure.message : '推送失败');
    } finally {
      this.busy = false;
      this.progress = '';
    }
  }

  private confirmWipe(): void {
    this.getUIContext().showAlertDialog({
      title: '清空远端课表',
      message: '会删除这个日历里由工大助手推送过的事件，其它客户端写的事件不受影响。确定继续？',
      autoCancel: true,
      buttons: [
        { value: '取消', action: () => {} },
        {
          value: '清空',
          action: () => {
            this.wipe();
          }
        }
      ]
    });
  }

  private async wipe(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.error = '';
    this.status = '';
    try {
      const removed: number = await CalDavSyncService.wipeRemote(this.context());
      this.lastPushedAt = 0;
      this.lastEventCount = 0;
      this.status = `已从远端删除 ${removed} 个事件`;
    } catch (failure) {
      this.error = failure instanceof CalDavError ? failure.message : '清空失败';
    } finally {
      this.busy = false;
    }
  }

  private timeLabel(): string {
    if (this.lastPushedAt === 0) {
      return '尚未推送过';
    }
    const date: Date = new Date(this.lastPushedAt);
    const pad = (value: number): string => `${value}`.padStart(2, '0');
    return `上次推送 ${date.getMonth() + 1}/${date.getDate()} ${pad(date.getHours())}:${pad(date.getMinutes())}` +
      ` · ${this.lastEventCount} 个事件`;
  }

  @Builder
  fieldLabel(text: string) {
    Text(text)
      .fontSize(AppTheme.FONT_TINY)
      .fontColor(AppTheme.TEXT_TERTIARY)
      .width('100%')
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: 14 }) {
          Text('把当前学期课表镜像到你自己的 CalDAV 日历（Radicale、Nextcloud 等）。' +
            '每次推送整份覆盖一个 ICS 文件，不会影响同一日历里其它客户端写的事件。')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_SECONDARY)
            .width('100%')
            .lineHeight(19)

          if (this.error.length > 0) {
            Text(this.error)
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor('#C7362B')
              .width('100%')
              .padding(12)
              .backgroundColor('#FFF0EE')
              .borderRadius(14)
          }
          if (this.status.length > 0) {
            Text(this.status)
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor('#2F6B4F')
              .width('100%')
              .padding(12)
              .backgroundColor('#DFF0E4')
              .borderRadius(14)
          }

          Column({ space: 10 }) {
            this.fieldLabel('日历集合地址')
            TextInput({ text: this.url, placeholder: 'https://cal.example.com/user/calendar-id/' })
              .height(44)
              .fontSize(AppTheme.FONT_BODY)
              .backgroundColor(AppTheme.BG)
              .borderRadius(12)
              .onChange((value: string) => {
                this.url = value;
              })
            Text('在日历客户端里对目标日历选择「共享 / 订阅地址」复制过来，末尾带 /。')
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_TERTIARY)
              .width('100%')
              .lineHeight(16)

            Divider().color(AppTheme.DIVIDER).opacity(0.5)

            this.fieldLabel('用户名（可选）')
            TextInput({ text: this.username, placeholder: '服务器开启认证时填写' })
              .height(44)
              .fontSize(AppTheme.FONT_BODY)
              .backgroundColor(AppTheme.BG)
              .borderRadius(12)
              .onChange((value: string) => {
                this.username = value;
              })

            this.fieldLabel('密码 / 应用密码（可选）')
            TextInput({ text: this.password, placeholder: '服务器开启认证时填写' })
              .type(InputType.Password)
              .height(44)
              .fontSize(AppTheme.FONT_BODY)
              .backgroundColor(AppTheme.BG)
              .borderRadius(12)
              .onChange((value: string) => {
                this.password = value;
              })
            Text('密码只保存在系统安全存储，不写入备份、日志和普通配置。')
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_TERTIARY)
              .width('100%')
              .lineHeight(16)
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor($r('app.color.profile_card_bg'))
          .borderRadius(18)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 0.5, color: '#66FFFFFF' })
          .alignItems(HorizontalAlign.Start)

          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(19)
              .fontColor([AppTheme.TEXT_SECONDARY])
            Column({ space: 2 }) {
              Text('课表同步后自动推送')
                .fontSize(AppTheme.FONT_BODY)
                .fontColor(AppTheme.TEXT_PRIMARY)
              Text('教务同步成功后自动覆盖远端课表；关闭则只在手动推送时更新')
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_TERTIARY)
                .maxLines(2)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.autoPush })
              .selectedColor(this.brandTextColor)
              .onChange((value: boolean) => {
                this.autoPush = value;
                this.persist();
              })
          }
          .width('100%')
          .height(66)
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.profile_card_bg'))
          .borderRadius(18)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 0.5, color: '#66FFFFFF' })

          Row({ space: AppTheme.SPACE_SM }) {
            Button(this.busy ? '处理中…' : '保存并测试')
              .layoutWeight(1)
              .height(44)
              .fontSize(AppTheme.FONT_BODY)
              .backgroundColor(AppTheme.BG)
              .fontColor(this.brandTextColor)
              .enabled(!this.busy)
              .onClick(() => this.saveAndTest())
            Button(this.busy ? '处理中…' : '立即推送')
              .layoutWeight(1)
              .height(44)
              .fontSize(AppTheme.FONT_BODY)
              .backgroundColor(this.brandColor)
              .fontColor(Color.White)
              .enabled(!this.busy)
              .onClick(() => this.pushNow())
          }
          .width('100%')

          Column({ space: 4 }) {
            if (this.progress.length > 0) {
              Text(this.progress)
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(this.brandTextColor)
                .width('100%')
            }
            Row() {
              Text(this.timeLabel())
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
                .layoutWeight(1)
              Text('清空远端')
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_TERTIARY)
                .onClick(() => this.confirmWipe())
            }
            .width('100%')
            Text('推送是单向覆盖：在手机日历里直接修改这些事件，下次推送会被覆盖回课表内容。')
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_TERTIARY)
              .width('100%')
              .lineHeight(16)
              .padding({ top: 2 })
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor($r('app.color.profile_card_bg'))
          .borderRadius(18)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 0.5, color: '#66FFFFFF' })
          .alignItems(HorizontalAlign.Start)
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
      .scrollBar(BarState.Off)
    }
    .titleBar(immersiveTitleBar('日历同步'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
