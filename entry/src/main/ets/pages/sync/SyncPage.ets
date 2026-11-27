import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { ThemeColor } from '../../common/ThemeColor';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { Semester } from '../../domain/model/TimetableModels';
import { SyncPlan } from '../../domain/model/SyncPlan';
import { TimetableRepository } from '../../data/TimetableRepository';
import { TimetableSyncService } from '../../services/sync/TimetableSyncService';
import { CalDavSyncService } from '../../services/caldav/CalDavSyncService';
import { SyncSettings } from '../../services/sync/SyncSettings';
import { AutoSyncService } from '../../services/sync/AutoSyncService';
import { JxfwSession } from '../../services/jxfw/JxfwSession';
import { CasLoginService } from '../../services/jxfw/CasLoginService';
import { CredentialsStore, SavedCredentials } from '../../services/jxfw/CredentialsStore';
import { JxfwError, JxfwErrorKind, SyncSummary } from '../../services/jxfw/JxfwModels';
import { JxfwProfileService } from '../../services/jxfw/JxfwProfileService';
import { PortalService } from '../../services/portal/PortalService';
import { isValidTermCode, surroundingTermCodes, termLabel } from '../../services/jxfw/JxfwTerms';
import { TimetableState } from '../../state/TimetableState';
import { todayIso, weekOf } from '../../domain/timetable/TimetableEngine';

@Component
struct SyncInfoRow {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
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
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  @StorageLink('jxfwSessionRevision') @Watch('onSessionChange') sessionRevision: number = 0;
  @StorageLink('autoSyncEnabled') autoSync: boolean = false;
  @State semester: Semester | null = null;
  @State semesters: Semester[] = [];
  @State termOptions: string[] = [];
  @State selectedTerm: string = '';
  @State selectedExisting: Semester | null = null;
  @State previewSemester: Semester | null = null;
  @State studentName: string = '';
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
      this.semesters = await TimetableRepository.listSemesters(this.context());
      this.semester = await TimetableRepository.getCurrentSemester(this.context());
      const candidates: string[] = surroundingTermCodes(new Date());
      if (this.semester !== null && isValidTermCode(this.semester.termCode) &&
        candidates.indexOf(this.semester.termCode.trim()) < 0) {
        candidates.push(this.semester.termCode.trim());
      }
      for (const item of this.semesters) {
        const code: string = item.termCode.trim();
        if (isValidTermCode(code) && candidates.indexOf(code) < 0) {
          candidates.push(code);
        }
      }
      this.termOptions = candidates;
      const preferred: string = this.semester !== null && isValidTermCode(this.semester.termCode)
        ? this.semester.termCode.trim() : surroundingTermCodes(new Date())[1];
      if (this.selectedTerm.length === 0 || this.termOptions.indexOf(this.selectedTerm) < 0) {
        this.selectedTerm = this.termOptions.indexOf(preferred) >= 0 ? preferred : this.termOptions[0];
      }
      this.refreshSelectedExisting();
      const saved: SavedCredentials | null = await CredentialsStore.load();
      if (saved !== null) {
        this.username = saved.username;
        this.savedAccount = true;
      }
      this.studentName = await JxfwProfileService.cachedName(this.context());
      if (this.studentName.length === 0 && JxfwSession.isLoggedIn()) {
        const fetched: string = await JxfwProfileService.refresh(this.context());
        if (fetched.length > 0) {
          this.studentName = fetched;
        }
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

  private refreshSelectedExisting(): void {
    const existing: Semester | undefined =
      this.semesters.find((item: Semester) => item.termCode.trim() === this.selectedTerm);
    this.selectedExisting = existing === undefined ? null : existing;
  }

  private selectTerm(term: string): void {
    this.selectedTerm = term;
    this.plan = null;
    this.previewSemester = null;
    this.refreshSelectedExisting();
  }

  private semesterForTerm(term: string): Semester {
    const existing: Semester | undefined =
      this.semesters.find((item: Semester) => item.termCode.trim() === term);
    if (existing !== undefined) {
      return existing;
    }
    return {
      id: `jxfw-term-${term}`,
      name: termLabel(term),
      startDate: '',
      totalWeeks: 0,
      termCode: term,
      isCurrent: false,
      createdAt: 0,
      updatedAt: 0
    };
  }

  private termHint(term: string): string {
    const existing: Semester | undefined =
      this.semesters.find((item: Semester) => item.termCode.trim() === term);
    if (this.semester !== null && this.semester.termCode.trim() === term) {
      return '当前使用';
    }
    if (existing !== undefined) {
      return '已导入，可重新抓取';
    }
    return '抓取后自动创建学期';
  }

  private isDateCurrentTerm(term: string): boolean {
    return surroundingTermCodes(new Date())[1] === term;
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
      PortalService.clearSession();
      const name: string = await JxfwProfileService.refresh(this.context());
      if (name.length > 0) {
        this.studentName = name;
        this.toast('登录成功，已获取教务姓名');
      } else {
        this.toast('登录成功，账号已安全保存');
      }
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
    if (!isValidTermCode(this.selectedTerm)) {
      this.error = '请选择要抓取的学期';
      return;
    }
    this.syncing = true;
    this.error = '';
    try {
      const target: Semester = this.semesterForTerm(this.selectedTerm);
      this.plan = await TimetableSyncService.previewFullSync(this.context(), target);
      this.previewSemester = target;
      this.showPreview = true;
    } catch (error) {
      this.handleError(error);
    } finally {
      this.syncing = false;
    }
  }

  private async applyPlan(): Promise<void> {
    if (this.plan === null || this.previewSemester === null || this.applying) {
      return;
    }
    this.applying = true;
    this.error = '';
    try {
      const target: Semester = this.previewSemester;
      const startDate: string = this.plan.startDate.length > 0
        ? this.plan.startDate
        : (target.startDate.length > 0 ? target.startDate : todayIso());
      let totalWeeks: number = target.totalWeeks;
      if (this.plan.totalWeeks > totalWeeks) {
        totalWeeks = this.plan.totalWeeks;
      }
      if (totalWeeks < 1) {
        totalWeeks = 20;
      }
      const saved: Semester = await TimetableRepository.ensureSemesterForTerm(
        this.context(), target.id, termLabel(target.termCode), startDate, totalWeeks, target.termCode);
      if (saved.id !== target.id) {
        for (const course of this.plan.add) {
          course.semesterId = saved.id;
        }
        for (const course of this.plan.update) {
          course.semesterId = saved.id;
        }
        for (const event of this.plan.exams) {
          event.semesterId = saved.id;
        }
      }
      const summary: SyncSummary =
        await TimetableSyncService.applyFullSync(this.context(), saved, this.plan);
      this.result = this.summaryText(summary, false);
      // 课表变了就顺手刷新 CalDAV 镜像；失败不影响同步结果。
      CalDavSyncService.pushIfEnabled(this.context());
      this.lastFull = this.formatNow();
      await SyncSettings.set(this.context(), 'last_full', this.lastFull);
      await SyncSettings.set(this.context(), 'last_result', this.result);
      this.semester = await TimetableRepository.getCurrentSemester(this.context());
      this.semesters = await TimetableRepository.listSemesters(this.context());
      this.selectedTerm = saved.termCode;
      this.refreshSelectedExisting();
      this.deletedImports = (await TimetableRepository.listTombstones(this.context(), saved.id)).length;
      this.showPreview = false;
      this.plan = null;
      this.previewSemester = null;
      TimetableState.bump();
      this.toast(`已导入 ${saved.name}`);
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
    if (this.semester === null) {
      this.error = '请先抓取当前学期，再更新下周课表';
      return;
    }
    if (!isValidTermCode(this.semester.termCode)) {
      this.error = '当前学期缺少教务学期代码，请重新抓取学期';
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
    PortalService.clearSession();
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
        .fontColor([this.brandTextColor])
      Text(title)
        .fontSize(AppTheme.FONT_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_PRIMARY)
    }
    .width('100%')
  }

  @Builder
  loginOnlyCard() {
    Column({ space: 10 }) {
      Column({ space: 4 }) {
        Text('登录教务系统')
          .fontSize(AppTheme.FONT_HEADING)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
        Text('填写学号与密码，登录后可同步课表、考试与学期')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_SECONDARY)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ bottom: 4 })

      Text('学号')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .width('100%')
      TextInput({ text: this.username, placeholder: '请输入学号' })
        .height(46)
        .backgroundColor(AppTheme.BG)
        .borderRadius(12)
        .onChange((value: string) => {
          this.username = value;
        })

      Text('密码')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .width('100%')
      TextInput({ text: this.password, placeholder: '请输入密码' })
        .type(InputType.Password)
        .height(46)
        .backgroundColor(AppTheme.BG)
        .borderRadius(12)
        .onChange((value: string) => {
          this.password = value;
        })

      Button(this.loggingIn ? '登录中…' : '登录')
        .width('100%')
        .height(46)
        .backgroundColor(this.brandColor)
        .fontColor(this.onBrandColor)
        .enabled(!this.loggingIn)
        .margin({ top: 4 })
        .onClick(() => this.login())

      if (this.error.length > 0) {
        Text(this.error)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor('#C7362B')
          .width('100%')
      }

      Text('账号保存在系统安全存储，仅用于学校统一认证；不会写入日志或普通 Preferences。')
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .width('100%')
        .lineHeight(17)
        .padding({ top: 2 })
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .margin({ top: 40 })
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
        .backgroundColor(this.brandColor)
        .fontColor(this.onBrandColor)
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
          Text(this.previewSemester === null ? '同步预览'
            : `${termLabel(this.previewSemester.termCode)} 预览`)
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TEXT_PRIMARY)
          Text('确认后自动创建或切换到该学期，并写入课表和考试')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_SECONDARY)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Row() {
          this.previewMetric('新增课程', this.plan.add.length, '#1D7A46')
          this.previewMetric('更新课程', this.plan.update.length, this.brandTextColor)
          this.previewMetric('移除课程', this.plan.remove.length, '#C7362B')
          this.previewMetric('考试', this.plan.exams.length, '#B26A00')
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
        .backgroundColor(AppTheme.SHEET_CARD_BG)
        .borderRadius(20)

        Text(`${this.plan.startDate.length > 0 ? '开学 ' + this.plan.startDate : '开学日待校准'} · 共 ${this.plan.totalWeeks > 0 ? this.plan.totalWeeks : 20} 周`)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .width('100%')

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
          Button(this.applying ? '正在导入…' : '导入并切换学期')
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

  @Builder
  termOption(term: string) {
    Row({ space: 12 }) {
      Stack() {
        if (this.selectedTerm === term) {
          Column()
            .width(10)
            .height(10)
            .borderRadius(5)
            .backgroundColor(this.brandColor)
        }
      }
      .width(20)
      .height(20)
      .borderRadius(10)
      .border({
        width: this.selectedTerm === term ? 1.5 : 1,
        color: this.selectedTerm === term ? this.brandColor : AppTheme.TEXT_TERTIARY
      })
      .align(Alignment.Center)

      Column({ space: 3 }) {
        Text(termLabel(term))
          .fontSize(AppTheme.FONT_BODY)
          .fontWeight(this.selectedTerm === term ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .maxLines(1)
        Text(`${term} · ${this.termHint(term)}`)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.isDateCurrentTerm(term)) {
        Text('本学期')
          .fontSize(9)
          .fontColor(this.brandTextColor)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(ThemeColor.alpha(this.brandColor, 0.1))
          .borderRadius(8)
      }
    }
    .width('100%')
    .height(66)
    .padding({ left: 14, right: 14 })
    .backgroundColor(this.selectedTerm === term ? ThemeColor.alpha(this.brandColor, 0.07) : AppTheme.BG)
    .borderRadius(16)
    .border({
      width: this.selectedTerm === term ? 1.2 : 0.5,
      color: this.selectedTerm === term ? this.brandColor : '#14000000'
    })
    .onClick(() => this.selectTerm(term))
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: AppTheme.SPACE_LG }) {
          if (this.loading) {
            Column({ space: 8 }) {
              LoadingProgress()
                .width(28)
                .height(28)
                .color(this.brandTextColor)
              Text('正在读取登录信息…')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_TERTIARY)
            }
            .width('100%')
            .height(220)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (!this.loggedIn && !this.savedAccount) {
            this.loginOnlyCard()
          } else {
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
            SyncInfoRow({
              label: '姓名',
              value: this.studentName.length > 0 ? this.studentName : '未获取，可在“我的”中编辑'
            })
            SyncInfoRow({
              label: '当前学期',
              value: this.semester === null ? '未设置' : this.semester.name
            })
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
                  .fontColor(this.brandTextColor)
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

            Button($r('app.string.sync_next_week'))
              .width('100%')
              .height(42)
              .backgroundColor(AppTheme.BG)
              .fontColor(AppTheme.TEXT_PRIMARY)
              .enabled(!this.syncing && (this.loggedIn || this.savedAccount) && this.semester !== null)
              .onClick(() => this.runWeekSync())
              .margin({ top: AppTheme.SPACE_SM })
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(AppTheme.CARD_RADIUS)
          .alignItems(HorizontalAlign.Start)

          Column({ space: AppTheme.SPACE_SM }) {
            this.sectionTitle($r('sys.symbol.calendar'), $r('app.string.sync_select_term'))
            Text('登录后选择当前学期或前后一学期，直接抓取课表和考试，无需先手动创建学期。')
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_TERTIARY)
              .width('100%')
              .lineHeight(17)
            ForEach(this.termOptions, (term: string) => {
              this.termOption(term)
            }, (term: string) => `${term}-${this.selectedTerm === term}`)

            if (this.selectedExisting !== null) {
              Text(`本地已有：${this.selectedExisting.name} · ${this.selectedExisting.startDate} · ${this.selectedExisting.totalWeeks} 周`)
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_SECONDARY)
                .width('100%')
            } else {
              Text('该学期尚未导入，确认预览后会自动创建并切换。')
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_TERTIARY)
                .width('100%')
            }

            Button(this.syncing ? '正在抓取…' : '抓取所选学期')
              .width('100%')
              .height(44)
              .enabled(!this.syncing && (this.loggedIn || this.savedAccount) && this.selectedTerm.length > 0)
              .onClick(() => this.runFullSync())
              .margin({ top: AppTheme.SPACE_XS })
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
              .selectedColor(this.brandTextColor)
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
          }
        }
        .width('100%')
        .padding({
          left: AppTheme.PAGE_PADDING,
          right: AppTheme.PAGE_PADDING,
          top: AppTheme.TALL_PAGE_TOP_INSET + 24,
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
