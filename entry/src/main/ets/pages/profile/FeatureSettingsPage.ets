import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { DisplaySettings } from '../../state/DisplaySettings';
import { LocalNotificationService } from '../../services/notification/LocalNotificationService';

@Component
struct FeatureToggleRow {
  @Prop icon: Resource;
  @Prop title: string = '';
  @Prop detail: string = '';
  @Prop isOn: boolean = false;
  onToggle: (value: boolean) => void = () => {};

  build() {
    Row({ space: 12 }) {
      SymbolGlyph(this.icon)
        .fontSize(19)
        .fontColor([AppTheme.TEXT_SECONDARY])
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_PRIMARY)
        if (this.detail.length > 0) {
          Text(this.detail)
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .maxLines(2)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .onChange((value: boolean) => this.onToggle(value))
    }
    .width('100%')
    .height(this.detail.length > 0 ? 66 : 54)
    .padding({ left: 16, right: 16 })
  }
}

@Component
export struct FeatureSettingsPage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @StorageLink('showCourseContent') showCourseContent: boolean = false;
  @StorageLink('campusNewsEnabled') campusNewsEnabled: boolean = true;
  @StorageLink('campusDataEnabled') campusDataEnabled: boolean = true;
  @StorageLink('localNotificationsEnabled') localNotificationsEnabled: boolean = false;
  @StorageLink('selectionEnabled') selectionEnabled: boolean = true;
  @StorageLink('electricityEnabled') electricityEnabled: boolean = false;

  aboutToAppear(): void {
    LocalNotificationService.load(this.context());
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /**
   * 电费查询还在 Beta 阶段，开启前先弹免责声明；取消则把开关回滚。
   * 这里先把状态置 true 让 Toggle 跟着手指走，确认后才落盘。
   */
  private confirmElectricity(): void {
    this.electricityEnabled = true;
    this.getUIContext().showAlertDialog({
      title: '电费查询 · Beta',
      message: '接口由电表服务商（电精灵）提供，目前仍是 Beta 功能。\n\n' +
        '· 接口可能随时调整或中断，数值仅供参考；\n' +
        '· 请求以明文 HTTP 发出，内容为校区与电表表号；\n' +
        '· 表号保存在本机，余额只留在内存、不写入备份；\n' +
        '· 查询结果仅供参考，请以电表读数和缴费记录为准。\n\n' +
        '是否开启电费查询？',
      autoCancel: false,
      buttons: [
        {
          value: '取消',
          action: () => {
            this.electricityEnabled = false;
          }
        },
        {
          value: '同意并开启',
          action: () => {
            this.electricityEnabled = true;
            DisplaySettings.setElectricityEnabled(this.context(), true);
          }
        }
      ]
    });
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      // Toast is optional.
    }
  }

  @Builder
  sectionLabel(text: string) {
    Text(text)
      .fontSize(AppTheme.FONT_TINY)
      .fontColor(AppTheme.TEXT_TERTIARY)
      .width('100%')
      .padding({ left: 6, top: 2 })
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: 14 }) {
          this.sectionLabel('课表')
          Column() {
            FeatureToggleRow({
              icon: $r('sys.symbol.doc_plaintext'),
              title: '课表显示授课内容',
              detail: '在课表课程块中显示教务同步的 sknrjj 授课内容',
              isOn: this.showCourseContent,
              onToggle: (value: boolean) => {
                this.showCourseContent = value;
                DisplaySettings.set(this.context(), value);
              }
            })
          }
          .width('100%')
          .backgroundColor($r('app.color.profile_card_bg'))
          .borderRadius(18)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 0.5, color: '#66FFFFFF' })
          .clip(true)

          this.sectionLabel('通知')
          Column() {
            FeatureToggleRow({
              icon: $r('sys.symbol.clock'),
              title: '本地通知',
              detail: '同步完成、课程变化时发送系统通知；不依赖代理提醒',
              isOn: this.localNotificationsEnabled,
              onToggle: async (value: boolean) => {
                const ok: boolean = await LocalNotificationService.setEnabled(this.context(), value);
                this.localNotificationsEnabled = ok ? value : false;
                if (!ok) {
                  this.toast('请先允许系统通知权限');
                }
              }
            })
            Divider().color(AppTheme.DIVIDER).opacity(0.5).margin({ left: 16, right: 16 })
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.bell'))
                .fontSize(19)
                .fontColor([AppTheme.TEXT_SECONDARY])
              Column({ space: 2 }) {
                Text('发送测试通知')
                  .fontSize(AppTheme.FONT_BODY)
                  .fontColor(AppTheme.TEXT_PRIMARY)
                Text('验证通知权限与通知槽是否正常')
                  .fontSize(AppTheme.FONT_TINY)
                  .fontColor(AppTheme.TEXT_TERTIARY)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('测试')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(this.brandTextColor)
            }
            .width('100%')
            .height(56)
            .padding({ left: 16, right: 16 })
            .onClick(async () => {
              const ok: boolean = await LocalNotificationService.notify(this.context(),
                '工大助手通知测试', '本地通知已就绪', 'test');
              this.toast(ok ? '测试通知已发送' : '请先开启本地通知并允许通知权限');
            })
          }
          .width('100%')
          .backgroundColor($r('app.color.profile_card_bg'))
          .borderRadius(18)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 0.5, color: '#66FFFFFF' })
          .clip(true)

          this.sectionLabel('校园')
          Column() {
            FeatureToggleRow({
              icon: $r('sys.symbol.square_fill_grid_2x2'),
              title: '校园数据',
              detail: '显示校园卡余额、图书借阅和校园网余额',
              isOn: this.campusDataEnabled,
              onToggle: (value: boolean) => {
                this.campusDataEnabled = value;
                DisplaySettings.setCampusDataEnabled(this.context(), value);
              }
            })
            Divider().color(AppTheme.DIVIDER).opacity(0.5).margin({ left: 16, right: 16 })
            FeatureToggleRow({
              icon: $r('sys.symbol.doc_plaintext'),
              title: '校园新闻',
              detail: '控制校园新闻功能的启用状态',
              isOn: this.campusNewsEnabled,
              onToggle: (value: boolean) => {
                this.campusNewsEnabled = value;
                DisplaySettings.setCampusNewsEnabled(this.context(), value);
              }
            })
            Divider().color(AppTheme.DIVIDER).opacity(0.5).margin({ left: 16, right: 16 })
            FeatureToggleRow({
              icon: $r('sys.symbol.list_bullet_square_fill'),
              title: '选课助手',
              detail: '在「更多服务」中显示选课入口：查课、冲突预检与定时抢课',
              isOn: this.selectionEnabled,
              onToggle: (value: boolean) => {
                this.selectionEnabled = value;
                DisplaySettings.setSelectionEnabled(this.context(), value);
              }
            })
            Divider().color(AppTheme.DIVIDER).opacity(0.5).margin({ left: 16, right: 16 })
            FeatureToggleRow({
              icon: $r('sys.symbol.bolt'),
              title: '电费查询（Beta）',
              detail: '在「更多服务」中显示宿舍电费卡片；Beta 阶段仍在适配中，可能不稳定',
              isOn: this.electricityEnabled,
              onToggle: (value: boolean) => {
                if (value) {
                  this.confirmElectricity();
                  return;
                }
                this.electricityEnabled = false;
                DisplaySettings.setElectricityEnabled(this.context(), false);
              }
            })
          }
          .width('100%')
          .backgroundColor($r('app.color.profile_card_bg'))
          .borderRadius(18)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 0.5, color: '#66FFFFFF' })
          .clip(true)

          Text('功能开关会立即保存，并随备份一起导出/恢复。')
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
          top: AppTheme.TALL_PAGE_TOP_INSET + 24,
          bottom: AppTheme.CONTENT_BOTTOM_INSET
        })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
    }
    .titleBar(immersiveTitleBar('功能设置'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
