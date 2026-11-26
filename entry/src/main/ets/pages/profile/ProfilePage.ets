import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { AppTheme } from '../../common/Theme';
import { AppNavActions } from '../../common/AppNavActions';
import { Course, Event, Semester } from '../../domain/model/TimetableModels';
import { TimetableRepository } from '../../data/TimetableRepository';
import { weekOf } from '../../domain/timetable/TimetableEngine';
import { ReminderService } from '../../services/reminder/ReminderService';
import { SystemCalendarSyncService } from '../../services/calendar/SystemCalendarSyncService';
import { TzcsCacheService } from '../../services/tzcs/TzcsCache';
import { TzcsCache } from '../../services/tzcs/TzcsModels';
import { JxfwProfileService } from '../../services/jxfw/JxfwProfileService';
import { JxfwSession } from '../../services/jxfw/JxfwSession';
import { CredentialsStore } from '../../services/jxfw/CredentialsStore';

@Component
struct ProfileRow {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  @Prop label: ResourceStr = '';
  @Prop value: string = '';
  @Prop showChevron: boolean = false;
  onTap: () => void = () => {};

  build() {
    Row({ space: 12 }) {
      Text(this.label)
        .fontSize(AppTheme.FONT_BODY)
        .fontColor(AppTheme.TEXT_PRIMARY)
      Blank()
      if (this.value.length > 0) {
        Text(this.value)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .maxLines(1)
          .textAlign(TextAlign.End)
      }
      if (this.showChevron) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([AppTheme.TEXT_TERTIARY])
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 18, right: 18 })
    .onClick(() => this.onTap())
  }
}

@Component
struct ProfileToggleRow {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  @Prop label: ResourceStr = '';
  @Prop isOn: boolean = false;
  onToggle: (value: boolean) => void = () => {};

  build() {
    Row({ space: 12 }) {
      Text(this.label)
        .fontSize(AppTheme.FONT_BODY)
        .fontColor(AppTheme.TEXT_PRIMARY)
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(this.brandTextColor)
        .onChange((value: boolean) => this.onToggle(value))
    }
    .width('100%')
    .height(56)
    .padding({ left: 18, right: 18 })
  }
}

@Component
struct SettingsRow {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  @Prop icon: Resource;
  @Prop label: ResourceStr = '';
  @Prop value: string = '';
  @Prop detail: string = '';
  @Prop showChevron: boolean = true;
  onTap: () => void = () => {};

  build() {
    Row({ space: 12 }) {
      SymbolGlyph(this.icon)
        .fontSize(19)
        .fontColor([AppTheme.TEXT_SECONDARY])
      Column({ space: 2 }) {
        Text(this.label)
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_PRIMARY)
        if (this.detail.length > 0) {
          Text(this.detail)
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .maxLines(1)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.value.length > 0) {
        Text(this.value)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .maxLines(1)
      }
      if (this.showChevron) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(13)
          .fontColor([AppTheme.TEXT_TERTIARY])
      }
    }
    .width('100%')
    .height(this.detail.length > 0 ? 64 : 54)
    .padding({ left: 16, right: 16 })
    .onClick(() => this.onTap())
  }
}

@Component
struct SettingsToggleRow {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  @Prop icon: Resource;
  @Prop label: ResourceStr = '';
  @Prop detail: string = '';
  @Prop isOn: boolean = false;
  onToggle: (value: boolean) => void = () => {};

  build() {
    Row({ space: 12 }) {
      SymbolGlyph(this.icon)
        .fontSize(19)
        .fontColor([AppTheme.TEXT_SECONDARY])
      Column({ space: 2 }) {
        Text(this.label)
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
        .onChange((value: boolean) => this.onToggle(value))
    }
    .width('100%')
    .height(this.detail.length > 0 ? 66 : 54)
    .padding({ left: 16, right: 16 })
  }
}

@Component
export struct ProfilePage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  nav: AppNavActions = new AppNavActions();
  onOpenSync: () => void = () => {};
  onOpenFeatures: () => void = () => {};
  onOpenAppearance: () => void = () => {};
  onOpenDataBackup: () => void = () => {};
  onOpenAbout: () => void = () => {};
  @StorageLink('timetableRevision') @Watch('onRevisionChange') revision: number = 0;
  @StorageLink('profileNameRevision') @Watch('onNameRevision') nameRevision: number = 0;
  @StorageLink('jxfwSessionRevision') @Watch('onLoginRevision') loginRevision: number = 0;
  @State semester: Semester | null = null;
  @State semesterName: string = '';
  @State courseCount: number = 0;
  @State examCount: number = 0;
  @State currentWeek: number = 0;
  @State avatarUri: string = '';
  @State displayName: string = '工大助手';
  @State hasManualName: boolean = false;
  @State showNameSheet: boolean = false;
  @State nameDraft: string = '';
  @State hasLoginInfo: boolean = false;

  @StorageLink('remindersEnabled') remindersEnabled: boolean = false;
  @StorageLink('calendarSyncEnabled') calendarSyncEnabled: boolean = false;

  aboutToAppear(): void {
    ReminderService.loadSetting(this.getUIContext().getHostContext() as common.UIAbilityContext);
    SystemCalendarSyncService.loadSetting(this.getUIContext().getHostContext() as common.UIAbilityContext);
    this.load();
    this.loadIdentity();
    this.loadLoginInfo();
  }

  onRevisionChange(): void {
    this.load();
  }

  onNameRevision(): void {
    this.loadIdentity();
  }

  onLoginRevision(): void {
    this.loadLoginInfo();
  }

  private async load(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.semester = await TimetableRepository.getCurrentSemester(context);
      this.semesterName = this.semester === null ? '' : this.semester.name;
      if (this.semester !== null) {
        const courses: Course[] = await TimetableRepository.listCourses(context, this.semester.id);
        const events: Event[] = await TimetableRepository.listEvents(context, this.semester.id);
        this.courseCount = courses.length;
        let exams: number = 0;
        for (const event of events) {
          if (event.category === 'EXAM') {
            exams++;
          }
        }
        this.examCount = exams;
        this.currentWeek = weekOf(this.semester.startDate, new Date());
      }
    } catch (error) {
      this.semester = null;
      this.semesterName = '';
      this.courseCount = 0;
      this.examCount = 0;
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (error) {
      // Toast failure must not break settings.
    }
  }

  private async loadLoginInfo(): Promise<void> {
    try {
      const saved = await CredentialsStore.load();
      this.hasLoginInfo = saved !== null || JxfwSession.isLoggedIn();
    } catch (error) {
      this.hasLoginInfo = JxfwSession.isLoggedIn();
    }
  }

  private async loadIdentity(): Promise<void> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, 'profile_settings');
      const saved = await store.get('avatar_uri', '');
      if (typeof saved === 'string' && saved.length > 0) {
        this.avatarUri = saved;
      }
      const manualName: string = await JxfwProfileService.manualName(context);
      let jxfwName: string = await JxfwProfileService.cachedName(context);
      if (manualName.length === 0 && jxfwName.length === 0 && JxfwSession.isLoggedIn()) {
        jxfwName = await JxfwProfileService.refresh(context);
      }
      let tzcsName: string = '';
      const cache: TzcsCache | null = await TzcsCacheService.load(context);
      if (cache !== null) {
        for (const report of cache.reports) {
          if (report.studentName.length > 0) {
            tzcsName = report.studentName;
          }
        }
      }
      this.hasManualName = manualName.length > 0;
      if (manualName.length > 0) {
        this.displayName = manualName;
      } else if (jxfwName.length > 0) {
        this.displayName = jxfwName;
      } else if (tzcsName.length > 0) {
        this.displayName = tzcsName;
      } else {
        this.displayName = '工大助手';
      }
    } catch (error) {
      // Identity is optional; fall back to the app title.
    }
  }

  private openNameEditor(): void {
    this.nameDraft = this.displayName;
    this.showNameSheet = true;
  }

  private async saveName(): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const name: string = this.nameDraft.trim();
    try {
      if (name.length > 0) {
        await JxfwProfileService.setManualName(context, name);
      } else {
        await JxfwProfileService.clearManualName(context);
      }
      this.showNameSheet = false;
      await this.loadIdentity();
      this.toast(name.length > 0 ? '显示名称已更新' : '已恢复自动获取的姓名');
    } catch (error) {
      this.toast('保存失败，请重试');
    }
  }

  private async restoreFetchedName(): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      await JxfwProfileService.clearManualName(context);
      this.showNameSheet = false;
      await this.loadIdentity();
      this.toast('已恢复自动获取的姓名');
    } catch (error) {
      this.toast('恢复失败，请重试');
    }
  }

  private async refreshFetchedName(): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const name: string = await JxfwProfileService.refresh(context);
    if (name.length === 0) {
      this.toast('未能获取教务姓名，请手动填写');
      return;
    }
    try {
      await JxfwProfileService.clearManualName(context);
    } catch (error) {
      // The fetched name can still be displayed even if the preference write fails.
    }
    this.hasManualName = false;
    this.displayName = name;
    this.nameDraft = name;
    this.toast('已重新获取教务姓名');
  }

  private async chooseAvatar(): Promise<void> {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({
        maxSelectNumber: 1,
        MIMEType: picker.PhotoViewMIMETypes.IMAGE_TYPE
      });
      if (result.photoUris.length === 0) {
        return;
      }
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const destination: string = `${context.filesDir}/profile_avatar_${Date.now()}.jpg`;
      const sourceFile = fs.openSync(result.photoUris[0], fs.OpenMode.READ_ONLY);
      const destinationFile = fs.openSync(destination, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      try {
        fs.copyFileSync(sourceFile.fd, destinationFile.fd);
      } finally {
        fs.closeSync(sourceFile);
        fs.closeSync(destinationFile);
      }
      this.avatarUri = `file://${destination}`;
      const store = await preferences.getPreferences(context, 'profile_settings');
      await store.put('avatar_uri', this.avatarUri);
      await store.flush();
    } catch (error) {
      this.toast('设置头像失败，请重试');
    }
  }

  @Builder
  avatarView() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      if (this.avatarUri.length > 0) {
        Image(this.avatarUri)
          .width(56)
          .height(56)
          .borderRadius(28)
          .objectFit(ImageFit.Cover)
      } else {
        Stack() {
          SymbolGlyph($r('sys.symbol.person'))
            .fontSize(28)
            .fontColor([this.onBrandColor])
        }
        .width(56)
        .height(56)
        .borderRadius(28)
        .backgroundColor(this.brandColor)
        .align(Alignment.Center)
      }
      if (this.avatarUri.length === 0) {
        Stack() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(10)
            .fontColor(['#FFFFFF'])
        }
        .width(18)
        .height(18)
        .borderRadius(9)
        .backgroundColor(this.brandColor)
        .border({ width: 1.5, color: AppTheme.CARD_BG })
        .align(Alignment.Center)
      }
    }
    .width(58)
    .height(58)
    .onClick(() => this.chooseAvatar())
  }

  @Builder
  sectionLabel(text: ResourceStr) {
    Text(text)
      .fontSize(AppTheme.FONT_TINY)
      .fontColor(AppTheme.TEXT_TERTIARY)
      .width('100%')
      .padding({ left: 6, top: 2 })
  }

  private statsValue(): string {
    if (this.semester === null) {
      return '--';
    }
    if (this.currentWeek < 1 || this.currentWeek > this.semester.totalWeeks) {
      return '假期';
    }
    return `第 ${this.currentWeek} 周`;
  }

  @Builder
  nameSheetBuilder() {
    Column({ space: AppTheme.SPACE_MD }) {
      Row() {
        Column()
          .width(36)
          .height(4)
          .borderRadius(2)
          .backgroundColor('#26000000')
      }
      .width('100%')
      .height(10)
      .justifyContent(FlexAlign.Center)

      Text('显示名称')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .width('100%')
      Text('优先显示教务系统抓取到的姓名；抓不到时可以在这里手动填写。')
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .width('100%')
        .lineHeight(18)

      TextInput({ text: this.nameDraft, placeholder: '输入显示名称' })
        .height(44)
        .backgroundColor(AppTheme.BG)
        .borderRadius(12)
        .onChange((value: string) => {
          this.nameDraft = value;
        })

      Row({ space: AppTheme.SPACE_SM }) {
        Button('取消')
          .layoutWeight(1)
          .height(46)
          .borderRadius(23)
          .backgroundColor(AppTheme.SHEET_CARD_BG)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .onClick(() => {
            this.showNameSheet = false;
          })
        Button('保存')
          .layoutWeight(1)
          .height(46)
          .borderRadius(23)
          .backgroundColor(this.brandColor)
          .fontColor(this.onBrandColor)
          .onClick(() => this.saveName())
      }
      .width('100%')

      if (JxfwSession.isLoggedIn()) {
        Text('从教务重新获取姓名')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(this.brandTextColor)
          .width('100%')
          .textAlign(TextAlign.Center)
          .onClick(() => this.refreshFetchedName())
      }
      if (this.hasManualName) {
        Text('恢复自动获取的姓名')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .width('100%')
          .textAlign(TextAlign.Center)
          .onClick(() => this.restoreFetchedName())
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 4, bottom: AppTheme.SPACE_XXL })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        // Merged identity + stats card
        Column({ space: 12 }) {
          Row({ space: 14 }) {
            this.avatarView()

            Column({ space: 3 }) {
              Row() {
                Text(this.displayName)
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppTheme.TEXT_PRIMARY)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .onClick(() => this.openNameEditor())
              Text(this.semester !== null
                ? this.semester.name
                : '本地优先的校园助手')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
                .maxLines(1)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Row({ space: 3 }) {
              Text(this.hasLoginInfo ? '查看登录信息' : '登录教务系统')
                .fontSize(13)
                .fontColor(this.hasLoginInfo ? AppTheme.TEXT_SECONDARY : this.brandTextColor)
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(15)
                .fontColor([this.hasLoginInfo ? AppTheme.TEXT_SECONDARY : this.brandTextColor])
            }
            .onClick(() => this.onOpenSync())
          }
          .width('100%')

          Divider().color(AppTheme.DIVIDER).opacity(0.55)

          Row() {
            Column({ space: 3 }) {
              Text(this.statsValue())
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.brandTextColor)
              Text('当前周次')
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_SECONDARY)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
            Column({ space: 3 }) {
              Text(`${this.courseCount}`)
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.brandTextColor)
              Text('本学期课程')
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_SECONDARY)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
            Column({ space: 3 }) {
              Text(`${this.examCount}`)
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.brandTextColor)
              Text('考试')
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_SECONDARY)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
          }
          .width('100%')
          .padding({ top: 2, bottom: 2 })
          .translate({ x: 6 })
        }
        .width('100%')
        .padding(18)
        .backgroundColor($r('app.color.profile_card_bg'))
        .borderRadius(22)
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .border({ width: 0.5, color: '#66FFFFFF' })

        this.sectionLabel('校园与效率')
        Column() {
          SettingsRow({
            icon: $r('sys.symbol.square_fill_grid_2x2'),
            label: '桌面小组件',
            value: '3 款',
            onTap: () => this.toast('长按桌面空白处，添加工大助手卡片')
          })
          Divider().color(AppTheme.DIVIDER).opacity(0.5).margin({ left: 16, right: 16 })
          SettingsRow({
            icon: $r('sys.symbol.eye'),
            label: '外观',
            value: '主题、材质与动效',
            onTap: () => this.onOpenAppearance()
          })
          Divider().color(AppTheme.DIVIDER).opacity(0.5).margin({ left: 16, right: 16 })
          SettingsRow({
            icon: $r('sys.symbol.list_square'),
            label: '功能设置',
            value: '授课内容、校园新闻',
            onTap: () => this.onOpenFeatures()
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.profile_card_bg'))
        .borderRadius(18)
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .border({ width: 0.5, color: '#66FFFFFF' })
        .clip(true)

        this.sectionLabel('同步与数据')
        Column() {
          SettingsRow({
            icon: $r('sys.symbol.calendar'),
            label: '当前学期',
            value: this.semesterName.length > 0 ? this.semesterName : '未设置学期',
            onTap: () => {
              if (this.semester === null) {
                this.onOpenSync();
              } else {
                this.nav.onOpenSemester();
              }
            }
          })
          Divider().color(AppTheme.DIVIDER).opacity(0.5).margin({ left: 16, right: 16 })
          SettingsRow({
            icon: $r('sys.symbol.doc_plaintext'),
            label: '数据与备份',
            detail: 'JSON 备份 · ICS/XLSX 导入',
            onTap: () => this.onOpenDataBackup()
          })
          Divider().color(AppTheme.DIVIDER).opacity(0.5).margin({ left: 16, right: 16 })
          SettingsToggleRow({
            icon: $r('sys.symbol.arrow_clockwise'),
            label: '系统日历同步',
            detail: '未来 21 天课程写入系统日历',
            isOn: this.calendarSyncEnabled,
            onToggle: async (isOn: boolean) => {
              const ok: boolean = await SystemCalendarSyncService.setEnabled(
                this.getUIContext().getHostContext() as common.UIAbilityContext, isOn);
              this.calendarSyncEnabled = ok ? isOn : false;
              if (ok && isOn) {
                const count: number = SystemCalendarSyncService.lastSyncedCount();
                this.toast(count > 0 ? `已同步 ${count} 个日历事件` : '当前没有可同步的日程');
              } else if (!ok) {
                this.toast('请先允许日历权限');
              }
            }
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.profile_card_bg'))
        .borderRadius(18)
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .border({ width: 0.5, color: '#66FFFFFF' })
        .clip(true)

        this.sectionLabel('提醒')
        Column() {
          SettingsToggleRow({
            icon: $r('sys.symbol.clock'),
            label: '上课与考试提醒',
            detail: '课程提前 10 分钟、考试提前 30 分钟',
            isOn: this.remindersEnabled,
            onToggle: async (isOn: boolean) => {
              const ok: boolean = await ReminderService.setEnabled(
                this.getUIContext().getHostContext() as common.UIAbilityContext, isOn);
              this.remindersEnabled = ok ? isOn : false;
              if (!ok) {
                const reason: string = ReminderService.lastErrorText();
                if (reason.includes('1700002') || reason.includes('exceeds the limit') ||
                  reason.includes('notification not allowed')) {
                  this.toast('当前签名未开通代理提醒权益，请改用系统日历同步');
                } else {
                  this.toast('请先在系统设置中允许通知');
                }
              }
            }
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.profile_card_bg'))
        .borderRadius(18)
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .border({ width: 0.5, color: '#66FFFFFF' })
        .clip(true)

        this.sectionLabel('其他')
        Column() {
          SettingsRow({
            icon: $r('sys.symbol.info_circle'),
            label: '关于工大助手',
            value: '1.1.0',
            showChevron: true,
            onTap: () => this.onOpenAbout()
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.profile_card_bg'))
        .borderRadius(18)
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .border({ width: 0.5, color: '#66FFFFFF' })
        .clip(true)

        Text($r('app.string.settings_hint'))
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 4, bottom: 8 })
      }
      .width('100%')
      .padding({
        left: AppTheme.PAGE_PADDING,
        right: AppTheme.PAGE_PADDING,
        top: AppTheme.TALL_PAGE_TOP_INSET + 18,
        bottom: AppTheme.CONTENT_BOTTOM_INSET
      })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .backgroundColor(AppTheme.BG)
    .scrollBar(BarState.Off)
    .bindSheet(this.showNameSheet, this.nameSheetBuilder(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
      backgroundColor: AppTheme.SHEET_BG,
      radius: { topLeft: 32, topRight: 32, bottomLeft: 0, bottomRight: 0 },
      onDisappear: () => {
        this.showNameSheet = false;
      }
    })
  }
}
