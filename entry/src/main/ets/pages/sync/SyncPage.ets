import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { Semester } from '../../domain/model/TimetableModels';
import { SyncPlan } from '../../domain/model/SyncPlan';
import { TimetableRepository } from '../../data/TimetableRepository';
import { TimetableSyncService } from '../../services/sync/TimetableSyncService';
import { SyncSettings } from '../../services/sync/SyncSettings';
import { AutoSyncService } from '../../services/sync/AutoSyncService';
import { JxfwSession } from '../../services/jxfw/JxfwSession';
import { CasLoginService } from '../../services/jxfw/CasLoginService';
import { CredentialsStore, SavedCredentials } from '../../services/jxfw/CredentialsStore';
import { JxfwError, JxfwErrorKind, SyncSummary } from '../../services/jxfw/JxfwModels';
import { TimetableState } from '../../state/TimetableState';
import { weekOf } from '../../domain/timetable/TimetableEngine';

@Component
struct SyncInfoRow {
  @Prop label: ResourceStr = '';
  @Prop value: string = '';

  build() {
    Row() {
      Text(this.label)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_SECONDARY)
      Blank()
      Text(this.value)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(32)
  }
}

@Component
export struct SyncPage {
  @StorageLink('jxfwSessionRevision') @Watch('onSessionChange') sessionRevision: number = 0;
  @StorageLink('autoSyncEnabled') autoSync: boolean = false;
  @State semester: Semester | null = null;
  @State termCode: string = '';
  @State username: string = '';
  @State password: string = '';
  @State savedAccount: boolean = false;
  @State loggedIn: boolean = false;
  @State loggingIn: boolean = false;
  @State syncing: boolean = false;
  @State loading: boolean = true;
  @State lastFull: string = '—';
  @State lastWeek: string = '—';
  @State result: string = '尚未同步';
  @State error: string = '';
  @State semesterLabel: string = '未创建学期';
  @State plan: SyncPlan | null = null;
  @State showPreview: boolean = false;
  @State applying: boolean = false;
  @State deletedImports: number = 0;

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (error) {
      // Toast failure must not break the page.
    }
  }

  aboutToAppear(): void {
    AutoSyncService.loadSetting(this.context());
    this.loggedIn = JxfwSession.isLoggedIn();
    this.load();
  }

  onSessionChange(): void {
    this.loggedIn = JxfwSession.isLoggedIn();
  }

  private async load(): Promise<void> {
    try {
      this.semester = await TimetableRepository.getCurrentSemester(this.context());
      this.semesterLabel = this.semester === null ? '未创建学期' : this.semester.name;
      if (this.semester !== null) {
        this.termCode = this.semester.termCode.length > 0 ? this.semester.termCode : '202601';
      }
      const saved: SavedCredentials | null = await CredentialsStore.load();
      if (saved !== null) {
        this.username = saved.username;
        this.savedAccount = true;
      }
      this.lastFull = await SyncSettings.get(this.context(), 'last_full');
      this.lastWeek = await SyncSettings.get(this.context(), 'last_week');
      if (this.semester !== null) {
        const tombstones: string[] = await TimetableRepository.listTombstones(this.context(), this.semester.id);
        this.deletedImports = tombstones.length;
      }
      this.result = await SyncSettings.get(this.context(), 'last_result');
      if (this.lastFull.length === 0) {
        this.lastFull = '—';
      }
      if (this.lastWeek.length === 0) {
        this.lastWeek = '—';
      }
      if (this.result.length === 0) {
        this.result = '尚未同步';
      }
    } catch (error) {
      this.error = '读取学期失败: ' + (error as Error).message;
    } finally {
      this.loading = false;
    }
  }

  private async saveTermCode(): Promise<boolean> {
    if (this.semester === null) {
      this.error = '请先在“我的”中创建学期';
      return false;
    }
    const code: string = this.termCode.trim();
    if (code.length === 0) {
      this.error = '请填写教务学期代码';
      return false;
    }
    if (code !== this.semester.termCode) {
      await TimetableRepository.updateSemesterTermCode(this.context(), this.semester.id, code);
      const updated: Semester | null = await TimetableRepository.getCurrentSemester(this.context());
      this.semester = updated;
    }
    return true;
  }

  private formatNow(): string {
    const now: Date = new Date();
    const month: string = `${now.getMonth() + 1}`.padStart(2, '0');
    const day: string = `${now.getDate()}`.padStart(2, '0');
    const hour: string = `${now.getHours()}`.padStart(2, '0');
    const minute: string = `${now.getMinutes()}`.padStart(2, '0');
    return `${month}-${day} ${hour}:${minute}`;
  }

  private summaryText(summary: SyncSummary, weekly: boolean): string {
    if (weekly) {
      return `第 ${this.currentWeek() + 1} 周调整 ${summary.updated} 条，停课 ${summary.added} 条`;
    }
    let text: string =
      `课程 +${summary.added} / 更新 ${summary.updated} / 移除 ${summary.deleted}，考试 ${summary.exams} 场`;
    if (summary.warnings.length > 0) {
      text += `；${summary.warnings[0]}`;
    }
    return text;
  }

  private currentWeek(): number {
    if (this.semester === null) {
      return 1;
    }
    return weekOf(this.semester.startDate, new Date());
  }

  private async restoreDeletedImports(): Promise<void> {
    if (this.semester === null) {
      return;
    }
    await TimetableRepository.clearTombstones(this.context(), this.semester.id);
    this.deletedImports = 0;
    this.toast('已恢复删除记录，下次全量同步会重新导入');
  }

  private async login(): Promise<boolean> {
    const account: string = this.username.trim();
    if (account.length === 0 || this.password.length === 0) {
      this.error = '请输入学号和密码';
      return false;
    }
    this.loggingIn = true;
    this.error = '';
    try {
      await CasLoginService.login(account, this.password);
      await CredentialsStore.save(account, this.password);
      this.username = account;
      this.password = '';
      this.savedAccount = true;
      this.loggedIn = true;
      this.toast('登录成功，账号已安全保存');
      return true;
    } catch (error) {
      this.handleError(error);
      return false;
    } finally {
      this.loggingIn = false;
    }
  }

  private async ensureLoggedIn(): Promise<boolean> {
    if (JxfwSession.isLoggedIn()) {
      return true;
    }
    const ok: boolean = await CasLoginService.autoLogin();
    this.loggedIn = ok;
    if (!ok) {
      this.error = this.savedAccount ? '自动登录失败，请重新输入密码' : '请先登录教务系统';
    }
    return ok;
  }

  private async runFullSync(): Promise<void> {
    if (!(await this.ensureLoggedIn())) {
      return;
    }
    if (!(await this.saveTermCode()) || this.semester === null) {
      return;
    }
    this.syncing = true;
    this.error = '';
    try {
      this.plan = await TimetableSyncService.previewFullSync(this.context(), this.semester);
      this.showPreview = true;
    } catch (error) {
      this.handleError(error);
    } finally {
      this.syncing = false;
    }
  }

  private async applyPlan(): Promise<void> {
    if (this.plan === null || this.semester === null || this.applying) {
      return;
    }
    this.applying = true;
    this.error = '';
    try {
      const summary: SyncSummary =
        await TimetableSyncService.applyFullSync(this.context(), this.semester, this.plan);
      this.result = this.summaryText(summary, false);
      this.lastFull = this.formatNow();
      await SyncSettings.set(this.context(), 'last_full', this.lastFull);
      await SyncSettings.set(this.context(), 'last_result', this.result);
      const updated: Semester | null = await TimetableRepository.getCurrentSemester(this.context());
      this.semester = updated;
      this.showPreview = false;
      this.plan = null;
      TimetableState.bump();
      this.toast('同步完成');
    } catch (error) {
      this.handleError(error);
    } finally {
      this.applying = false;
    }
  }

  private async runWeekSync(): Promise<void> {
    if (!(await this.ensureLoggedIn())) {
      return;
    }
    if (!(await this.saveTermCode()) || this.semester === null) {
      return;
    }
    this.syncing = true;
    this.error = '';
    try {
      const week: number = this.currentWeek() + 1;
      const summary: SyncSummary =
        await TimetableSyncService.syncWeek(this.context(), this.semester, week);
      this.result = this.summaryText(summary, true);
      this.lastWeek = this.formatNow();
      await SyncSettings.set(this.context(), 'last_week', this.lastWeek);
      await SyncSettings.set(this.context(), 'last_result', this.result);
      TimetableState.bump();
      this.toast('下周课表已更新');
    } catch (error) {
      this.handleError(error);
    } finally {
      this.syncing = false;
    }
  }

  private handleError(error: Object): void {
    if (error instanceof JxfwError) {
      this.error = error.message;
      if (error.kind === JxfwErrorKind.SESSION) {
        JxfwSession.clear();
      }
      if (error.kind === JxfwErrorKind.CREDENTIALS) {
        this.savedAccount = false;
      }
    } else {
      this.error = '同步失败，请稍后重试';
    }
  }

  private async logout(): Promise<void> {
    JxfwSession.clear();
    await CredentialsStore.clear();
    this.loggedIn = false;
    this.savedAccount = false;
    this.username = '';
    this.password = '';
    this.error = '';
    this.toast('已退出教务登录');
  }

  @Builder
  sectionTitle(icon: Resource, title: ResourceStr) {
    Row({ space: AppTheme.SPACE_SM }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([AppTheme.BRAND])
      Text(title)
        .fontSize(AppTheme.FONT_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_PRIMARY)
    }
    .width('100%')
  }

  @Builder
  loginForm() {
    Column({ space: AppTheme.SPACE_SM }) {
      TextInput({ text: this.username, placeholder: '学号' })
        .height(42)
        .backgroundColor(AppTheme.BG)
        .borderRadius(10)
        .onChange((value: string) => {
          this.username = value;
        })
      TextInput({ text: this.password, placeholder: '密码' })
        .type(InputType.Password)
        .height(42)
        .backgroundColor(AppTheme.BG)
        .borderRadius(10)
        .onChange((value: string) => {
          this.password = value;
        })
      Button(this.loggingIn ? '登录中…' : (this.savedAccount ? '重新登录并保存' : '登录并保存'))
        .width('100%')
        .height(42)
        .enabled(!this.loggingIn && !this.syncing)
        .onClick(() => this.login())
      Text('账号保存在系统安全存储；会话失效时自动登录并重新抓取。')
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .width('100%')
    }
    .width('100%')
  }

  @Builder
  previewMetric(label: string, value: number, color: ResourceColor) {
    Column({ space: 2 }) {
      Text(`${value}`)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
      Text(label)
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(AppTheme.TEXT_SECONDARY)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  previewSheet() {
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
      if (this.plan !== null) {
        Column({ space: 4 }) {
          Text('同步预览')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TEXT_PRIMARY)
          Text('确认后才会写入本地课表和考试')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_SECONDARY)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Row() {
          this.previewMetric('新增课程', this.plan.add.length, '#1D7A46')
          this.previewMetric('更新课程', this.plan.update.length, AppTheme.BRAND)
          this.previewMetric('移除课程', this.plan.remove.length, '#C7362B')
          this.previewMetric('考试', this.plan.exams.length, '#B26A00')
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
        .backgroundColor(AppTheme.SHEET_CARD_BG)
        .borderRadius(20)

        if (this.plan.warnings.length > 0) {
          Text(this.plan.warnings[0])
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor('#B26A00')
            .width('100%')
        }
        if (this.plan.add.length + this.plan.update.length + this.plan.remove.length === 0) {
          Text('课表没有变化，确认后仍会刷新考试和开学日。')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .width('100%')
        }

        Row({ space: AppTheme.SPACE_SM }) {
          Button('取消')
            .layoutWeight(1)
            .height(46)
            .borderRadius(23)
            .backgroundColor(AppTheme.SHEET_CARD_BG)
            .fontColor(AppTheme.TEXT_PRIMARY)
            .onClick(() => {
              this.showPreview = false;
            })
          Button(this.applying ? '正在应用…' : '应用变更')
            .layoutWeight(1)
            .height(46)
            .borderRadius(23)
            .enabled(!this.applying)
            .onClick(() => this.applyPlan())
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 4, bottom: AppTheme.SPACE_XXL })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: AppTheme.SPACE_LG }) {
          Column({ space: AppTheme.SPACE_SM }) {
            this.sectionTitle($r('sys.symbol.arrow_clockwise'), $r('app.string.sync_account'))
            SyncInfoRow({
              label: $r('app.string.sync_student_no'),
              value: this.username.length > 0 ? this.username : '未登录'
            })
            SyncInfoRow({
              label: '登录状态',
              value: this.loggedIn ? '已登录' : (this.savedAccount ? '已保存，待自动登录' : '未登录')
            })
            SyncInfoRow({ label: $r('app.string.sync_term'), value: this.semesterLabel })
            SyncInfoRow({ label: $r('app.string.sync_last_full'), value: this.lastFull })
            SyncInfoRow({ label: $r('app.string.sync_last_week'), value: this.lastWeek })
            SyncInfoRow({ label: $r('app.string.sync_result'), value: this.result })

            if (this.deletedImports > 0) {
              Row() {
                Text(`已删除 ${this.deletedImports} 门教务课程`)
                  .fontSize(AppTheme.FONT_TINY)
                  .fontColor(AppTheme.TEXT_TERTIARY)
                Blank()
                Text('恢复')
                  .fontSize(AppTheme.FONT_TINY)
                  .fontColor(AppTheme.BRAND)
                  .onClick(() => this.restoreDeletedImports())
              }
              .width('100%')
              .height(28)
            }

            if (!this.loggedIn) {
              this.loginForm()
            }

            if (this.error.length > 0) {
              Text(this.error)
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor('#C7362B')
                .width('100%')
                .padding({ top: 4 })
            }

            Row({ space: AppTheme.SPACE_MD }) {
              Button($r('app.string.sync_full'))
                .layoutWeight(1)
                .height(42)
                .enabled(!this.syncing && (this.loggedIn || this.savedAccount))
                .onClick(() => this.runFullSync())
              Button($r('app.string.sync_next_week'))
                .layoutWeight(1)
                .height(42)
                .backgroundColor(AppTheme.BG)
                .fontColor(AppTheme.TEXT_PRIMARY)
                .enabled(!this.syncing && (this.loggedIn || this.savedAccount))
                .onClick(() => this.runWeekSync())
            }
            .width('100%')
            .margin({ top: AppTheme.SPACE_SM })
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(AppTheme.CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)

          Column({ space: AppTheme.SPACE_SM }) {
            this.sectionTitle($r('sys.symbol.calendar'), $r('app.string.sync_select_term'))
            Row() {
              Text($r('app.string.sync_term_code'))
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
              Blank()
              Text('保存')
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.BRAND)
                .onClick(async () => {
                  if (await this.saveTermCode()) {
                    this.toast('学期代码已保存');
                  }
                })
            }
            .width('100%')
            TextInput({ text: this.termCode, placeholder: '202601' })
              .height(42)
              .backgroundColor(AppTheme.BG)
              .borderRadius(10)
              .onChange((value: string) => {
                this.termCode = value;
              })
            Text($r('app.string.sync_term_code_tip'))
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_TERTIARY)
              .width('100%')
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(AppTheme.CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)

          Row() {
            Text('每周日晚自动同步')
              .fontSize(AppTheme.FONT_BODY)
              .fontColor(AppTheme.TEXT_PRIMARY)
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.autoSync })
              .onChange(async (isOn: boolean) => {
                const ok: boolean = await AutoSyncService.setEnabled(this.context(), isOn);
                this.autoSync = ok ? isOn : false;
                if (!ok) {
                  this.toast('无法启动后台同步任务');
                }
              })
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(AppTheme.CARD_RADIUS)

          Text('学号与密码保存在系统安全存储，仅用于登录学校统一认证；不会写入日志或普通 Preferences。')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .lineHeight(18)
            .width('100%')

          if (this.loggedIn || this.savedAccount) {
            Text($r('app.string.sync_logout'))
              .fontSize(AppTheme.FONT_BODY)
              .fontColor('#C7362B')
              .width('100%')
              .padding({ top: AppTheme.SPACE_MD, bottom: AppTheme.SPACE_MD })
              .onClick(() => this.logout())
          }
        }
        .width('100%')
        .padding({
          left: AppTheme.PAGE_PADDING,
          right: AppTheme.PAGE_PADDING,
          top: AppTheme.TALL_PAGE_TOP_INSET + 8,
          bottom: AppTheme.SPACE_XXL
        })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
    }
    .titleBar(immersiveTitleBar($r('app.string.sync_title')))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
    .bindSheet(this.showPreview, this.previewSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
      backgroundColor: AppTheme.SHEET_BG,
      radius: { topLeft: 32, topRight: 32, bottomLeft: 0, bottomRight: 0 },
      onDisappear: () => {
        this.showPreview = false;
      }
    })
  }
}
