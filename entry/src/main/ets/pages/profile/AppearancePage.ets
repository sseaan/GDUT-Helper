import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { ImmersiveMaterial } from '../../common/ImmersiveMaterial';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { AppearanceSettings, ThemeMode } from '../../state/AppearanceSettings';

@Component
struct AppearanceToggleRow {
  @Prop icon: Resource;
  @Prop title: string = '';
  @Prop detail: string = '';
  @Prop isOn: boolean = false;
  @Prop isAvailable: boolean = true;
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
        .enabled(this.isAvailable)
        .opacity(this.isAvailable ? 1 : 0.45)
        .onChange((value: boolean) => this.onToggle(value))
    }
    .width('100%')
    .height(this.detail.length > 0 ? 66 : 54)
    .padding({ left: 16, right: 16 })
  }
}

@Component
export struct AppearancePage {
  @State mode: ThemeMode = ThemeMode.SYSTEM;
  @State immersiveEnabled: boolean = true;
  @State handednessEnabled: boolean = true;

  aboutToAppear(): void {
    this.load();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async load(): Promise<void> {
    this.mode = await AppearanceSettings.load(this.context());
    this.immersiveEnabled = AppearanceSettings.immersiveEnabled();
    this.handednessEnabled = AppearanceSettings.handednessEnabled();
  }

  private async selectMode(mode: ThemeMode): Promise<void> {
    this.mode = mode;
    await AppearanceSettings.set(this.context(), mode);
  }

  private modeLabel(mode: ThemeMode): string {
    if (mode === ThemeMode.LIGHT) {
      return '浅色';
    }
    if (mode === ThemeMode.DARK) {
      return '深色';
    }
    return '跟随系统';
  }

  @Builder
  sectionLabel(text: string) {
    Text(text)
      .fontSize(AppTheme.FONT_TINY)
      .fontColor(AppTheme.TEXT_TERTIARY)
      .width('100%')
      .padding({ left: 6, top: 2 })
  }

  @Builder
  modeCard(mode: ThemeMode) {
    Column({ space: 6 }) {
      Text(this.modeLabel(mode))
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(this.mode === mode ? AppTheme.ON_BRAND : AppTheme.TEXT_PRIMARY)
      if (this.mode === mode) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(12)
          .fontColor([AppTheme.ON_BRAND])
      } else {
        Column().height(12)
      }
    }
    .layoutWeight(1)
    .height(92)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.mode === mode ? AppTheme.BRAND : AppTheme.CARD_BG)
    .borderRadius(14)
    .onClick(() => this.selectMode(mode))
  }

  @Builder
  infoRow(icon: Resource, title: string, value: string, detail: string) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(19)
        .fontColor([AppTheme.TEXT_SECONDARY])
      Column({ space: 2 }) {
        Text(title)
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_PRIMARY)
        if (detail.length > 0) {
          Text(detail)
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(value)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .textAlign(TextAlign.End)
        .maxLines(2)
    }
    .width('100%')
    .height(detail.length > 0 ? 64 : 54)
    .padding({ left: 16, right: 16 })
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: 14 }) {
          this.sectionLabel('主题模式')
          Row({ space: 8 }) {
            this.modeCard(ThemeMode.SYSTEM)
            this.modeCard(ThemeMode.LIGHT)
            this.modeCard(ThemeMode.DARK)
          }
          .width('100%')

          this.sectionLabel('主题色')
          Column() {
            this.infoRow($r('sys.symbol.eye'), '主题色', '跟随系统', '主题色由系统设置中的强调色决定')
          }
          .width('100%')
          .backgroundColor($r('app.color.profile_card_bg'))
          .borderRadius(18)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 0.5, color: '#66FFFFFF' })
          .clip(true)

          this.sectionLabel('材质与动效')
          Column() {
            AppearanceToggleRow({
              icon: $r('sys.symbol.lock_shield'),
              title: '沉浸光感',
              detail: ImmersiveMaterial.supported() ? ImmersiveMaterial.summary() : '当前设备不支持沉浸光感',
              isOn: this.immersiveEnabled,
              isAvailable: ImmersiveMaterial.supported(),
              onToggle: async (value: boolean) => {
                this.immersiveEnabled = value;
                await AppearanceSettings.setImmersive(this.context(), value);
              }
            })
            Divider().color(AppTheme.DIVIDER).opacity(0.5).margin({ left: 16, right: 16 })
            AppearanceToggleRow({
              icon: $r('sys.symbol.checkmark'),
              title: '智感握姿',
              detail: '底部悬浮栏和日历新增按钮跟随左右手',
              isOn: this.handednessEnabled,
              onToggle: async (value: boolean) => {
                this.handednessEnabled = value;
                await AppearanceSettings.setHandedness(this.context(), value);
              }
            })
          }
          .width('100%')
          .backgroundColor($r('app.color.profile_card_bg'))
          .borderRadius(18)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 0.5, color: '#66FFFFFF' })
          .clip(true)

          Text('主题模式会立即应用并保存，下次启动时自动恢复。')
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
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .titleBar(immersiveTitleBar('外观'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
