import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { ImmersiveMaterial } from '../../common/ImmersiveMaterial';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { AppearanceSettings, ThemeMode } from '../../state/AppearanceSettings';
import { ThemeColor, ThemeColorId, ThemeColorOption } from '../../common/ThemeColor';

@Component
struct AppearanceToggleRow {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
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
        .selectedColor(this.brandTextColor)
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
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  @State mode: ThemeMode = ThemeMode.SYSTEM;
  @StorageLink('themeColorId') themeColorId: string = ThemeColor.DEFAULT;
  @State immersiveEnabled: boolean = true;
  @State materialLevel: number = 10;
  @State handednessEnabled: boolean = true;

  aboutToAppear(): void {
    this.load();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async load(): Promise<void> {
    this.mode = await AppearanceSettings.load(this.context());
    this.themeColorId = AppearanceSettings.themeColorId();
    this.immersiveEnabled = AppearanceSettings.immersiveEnabled();
    this.materialLevel = AppearanceSettings.materialLevel();
    this.handednessEnabled = AppearanceSettings.handednessEnabled();
  }

  private async selectMode(mode: ThemeMode): Promise<void> {
    this.mode = mode;
    await AppearanceSettings.set(this.context(), mode);
  }

  private async selectThemeColor(id: string): Promise<void> {
    this.themeColorId = id;
    this.brandColor = ThemeColor.of(id);
    this.onBrandColor = ThemeColor.onBrand(id);
    await AppearanceSettings.setThemeColor(this.context(), id);
  }

  private async selectMaterialLevel(level: number): Promise<void> {
    this.materialLevel = level;
    await AppearanceSettings.setMaterialLevel(this.context(), level);
  }

  private materialLevelLabel(level: number): string {
    if (level === 0) {
      return '精致';
    }
    if (level === 1) {
      return '柔和';
    }
    if (level === 2) {
      return '流畅';
    }
    return '跟随系统';
  }

  @Builder
  materialLevelOption(level: number, label: string) {
    Text(label)
      .fontSize(AppTheme.FONT_CAPTION)
      .fontWeight(this.materialLevel === level ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.materialLevel === level ? this.onBrandColor : AppTheme.TEXT_PRIMARY)
      .height(42)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.materialLevel === level ? this.brandColor : AppTheme.BG)
      .borderRadius(12)
      .onClick(() => this.selectMaterialLevel(level))
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
        .fontColor(this.mode === mode ? this.onBrandColor : AppTheme.TEXT_PRIMARY)
      if (this.mode === mode) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(12)
          .fontColor([this.onBrandColor])
      } else {
        Column().height(12)
      }
    }
    .layoutWeight(1)
    .height(92)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.mode === mode ? this.brandColor : AppTheme.CARD_BG)
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
          Column({ space: 12 }) {
            Row({ space: 8 }) {
              ForEach(ThemeColor.OPTIONS, (option: ThemeColorOption) => {
                Column({ space: 6 }) {
                  Stack() {
                    Circle()
                      .width(38)
                      .height(38)
                      .fill(option.value)
                    if (this.themeColorId === option.id) {
                      SymbolGlyph($r('sys.symbol.checkmark'))
                        .fontSize(17)
                        .fontColor([this.onBrandColor])
                    }
                  }
                  .width(44)
                  .height(44)
                  .borderRadius(22)
                  .border({
                    width: this.themeColorId === option.id ? 2 : 0,
                    color: this.brandColor
                  })
                  .align(Alignment.Center)
                  Text(option.name)
                    .fontSize(AppTheme.FONT_CAPTION)
                    .fontWeight(this.themeColorId === option.id ? FontWeight.Medium : FontWeight.Normal)
                    .fontColor(this.themeColorId === option.id ? this.brandTextColor : AppTheme.TEXT_PRIMARY)
                  Text(option.detail)
                    .fontSize(AppTheme.FONT_TINY)
                    .fontColor(AppTheme.TEXT_TERTIARY)
                }
                .layoutWeight(1)
                .padding({ top: 12, bottom: 12 })
                .backgroundColor(this.themeColorId === option.id
                  ? ThemeColor.alpha(this.brandColor, 0.08) : Color.Transparent)
                .borderRadius(14)
                .onClick(() => this.selectThemeColor(option.id))
              }, (option: ThemeColorOption) => option.id)
            }
            .width('100%')
            Text('主题色会应用到按钮、选中态、课程高亮和悬浮栏光效。')
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_TERTIARY)
              .width('100%')
              .lineHeight(17)
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.profile_card_bg'))
          .borderRadius(18)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 0.5, color: '#66FFFFFF' })

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
            if (this.immersiveEnabled && ImmersiveMaterial.supported()) {
              Divider().color(AppTheme.DIVIDER).opacity(0.5).margin({ left: 16, right: 16 })
              Column({ space: 8 }) {
                Row() {
                  Text('光感强度')
                    .fontSize(AppTheme.FONT_BODY)
                    .fontColor(AppTheme.TEXT_PRIMARY)
                  Blank()
                  Text(this.materialLevelLabel(this.materialLevel))
                    .fontSize(AppTheme.FONT_TINY)
                    .fontColor(AppTheme.TEXT_SECONDARY)
                }
                .width('100%')
                Row({ space: 6 }) {
                  this.materialLevelOption(10, '跟随系统')
                  this.materialLevelOption(0, '精致')
                  this.materialLevelOption(1, '柔和')
                  this.materialLevelOption(2, '流畅')
                }
                .width('100%')
                Text('跟随系统会按设备能力自动选择材质精细度。')
                  .fontSize(AppTheme.FONT_TINY)
                  .fontColor(AppTheme.TEXT_TERTIARY)
                  .width('100%')
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 14 })
            }
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

          Text('主题模式与主题色会立即应用并保存，下次启动时自动恢复。')
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
