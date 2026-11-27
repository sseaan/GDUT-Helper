import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { SelectionClock } from '../../services/selection/SelectionClock';
import { SelectionEngine } from '../../services/selection/SelectionEngine';
import {
  SELECTION_QUEUE_REVISION_KEY,
  SELECTION_RUN_KEY,
  SELECTION_MIN_INTERVAL_MS,
  SELECTION_MAX_INTERVAL_MS,
  SelectionLogEntry,
  SelectionQueueItem,
  SelectionQueueState,
  SelectionRunPhase,
  SelectionRunSnapshot,
  SelectionTask,
  defaultSelectionTask,
  emptyRunSnapshot,
  remainingSeats
} from '../../services/selection/SelectionModels';
import { SelectionService } from '../../services/selection/SelectionService';

const MAX_LOG_ROWS: number = 40;

@Component
export struct SelectionTaskPage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Consume('brandColor') brandColor: string = '#0A59F7';
  @StorageLink(SELECTION_RUN_KEY) @Watch('onRunChange') runRaw: string = '';
  @StorageLink(SELECTION_QUEUE_REVISION_KEY) queueRevision: number = 0;
  @State task: SelectionTask = defaultSelectionTask();
  @State queue: SelectionQueueItem[] = [];
  @State startText: string = '';
  @State nowMs: number = Date.now();
  @State preparing: boolean = false;
  @State loading: boolean = true;
  @State error: string = '';
  @State showLogs: boolean = true;
  private ticker: number = -1;
  private lastAttempts: number = -1;
  private lastPhase: string = '';

  aboutToAppear(): void {
    this.ticker = setInterval(() => {
      this.nowMs = Date.now();
    }, 1000);
    this.load();
    SelectionService.recover(this.context()).catch(() => {});
  }

  aboutToDisappear(): void {
    if (this.ticker >= 0) {
      clearInterval(this.ticker);
      this.ticker = -1;
    }
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      // ignore
    }
  }

  private async load(): Promise<void> {
    try {
      this.task = await SelectionService.loadTask(this.context());
      this.queue = await SelectionService.queue(this.context());
      this.startText = SelectionTaskPage.formatTime(this.task.startAt);
    } catch (error) {
      this.error = '选课数据读取失败';
    } finally {
      this.loading = false;
    }
  }

  private async reloadQueue(): Promise<void> {
    this.queue = await SelectionService.queue(this.context());
    const value: number | undefined = AppStorage.get<number>(SELECTION_QUEUE_REVISION_KEY);
    AppStorage.setOrCreate(SELECTION_QUEUE_REVISION_KEY, (value === undefined ? 0 : value) + 1);
  }

  /** 只在提交次数或阶段变化时重读队列，避免每秒都打数据库。 */
  onRunChange(): void {
    const snapshot: SelectionRunSnapshot = this.snap();
    if (snapshot.attempts !== this.lastAttempts || snapshot.phase !== this.lastPhase) {
      this.lastAttempts = snapshot.attempts;
      this.lastPhase = snapshot.phase;
      this.reloadQueue().catch(() => {});
    }
  }

  private snap(): SelectionRunSnapshot {
    if (this.runRaw.length === 0) {
      return emptyRunSnapshot();
    }
    try {
      return JSON.parse(this.runRaw) as SelectionRunSnapshot;
    } catch (error) {
      return emptyRunSnapshot();
    }
  }

  private phaseLabel(phase: string): string {
    if (phase === SelectionRunPhase.ARMED) {
      return '等待开始';
    }
    if (phase === SelectionRunPhase.RUNNING) {
      return '进行中';
    }
    if (phase === SelectionRunPhase.DONE) {
      return '全部完成';
    }
    if (phase === SelectionRunPhase.PARTIAL) {
      return '部分完成';
    }
    if (phase === SelectionRunPhase.STOPPED) {
      return '已停止';
    }
    if (phase === SelectionRunPhase.FAILED) {
      return '已终止';
    }
    return '空闲';
  }

  private phaseColor(phase: string): ResourceColor {
    if (phase === SelectionRunPhase.DONE) {
      return '#2E7D4F';
    }
    if (phase === SelectionRunPhase.FAILED) {
      return '#C7362B';
    }
    if (phase === SelectionRunPhase.RUNNING || phase === SelectionRunPhase.ARMED) {
      return this.brandTextColor;
    }
    return AppTheme.TEXT_SECONDARY;
  }

  private running(): boolean {
    return SelectionEngine.isActive();
  }

  private countdown(): string {
    const remaining: number = this.task.startAt - Date.now();
    if (remaining <= 0) {
      return '已到开始时间';
    }
    const totalSeconds: number = Math.floor(remaining / 1000);
    const hours: number = Math.floor(totalSeconds / 3600);
    const minutes: number = Math.floor((totalSeconds % 3600) / 60);
    const seconds: number = totalSeconds % 60;
    const pad = (value: number): string => `${value}`.padStart(2, '0');
    return hours > 0
      ? `${hours}:${pad(minutes)}:${pad(seconds)}` : `${pad(minutes)}:${pad(seconds)}`;
  }

  private static formatTime(value: number): string {
    const date: Date = new Date(value);
    const pad = (input: number): string => `${input}`.padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
      `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
  }

  /** 支持 `YYYY-MM-DD HH:mm[:ss]` 与 `HH:mm[:ss]`（今天）。 */
  private parseStartText(): number {
    const text: string = this.startText.trim();
    const full: RegExp = /^(\d{4})-(\d{1,2})-(\d{1,2})[ T](\d{1,2}):(\d{2})(?::(\d{2}))?$/;
    const short: RegExp = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/;
    let match: RegExpExecArray | null = full.exec(text);
    if (match !== null) {
      const date: Date = new Date(Number.parseInt(match[1], 10), Number.parseInt(match[2], 10) - 1,
        Number.parseInt(match[3], 10), Number.parseInt(match[4], 10), Number.parseInt(match[5], 10),
        match[6] === undefined ? 0 : Number.parseInt(match[6], 10));
      return date.getTime();
    }
    match = short.exec(text);
    if (match !== null) {
      const now: Date = new Date();
      const date: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate(),
        Number.parseInt(match[1], 10), Number.parseInt(match[2], 10),
        match[3] === undefined ? 0 : Number.parseInt(match[3], 10));
      return date.getTime();
    }
    return 0;
  }

  private setStartOffset(offsetMs: number): void {
    this.task.startAt = Date.now() + offsetMs;
    this.startText = SelectionTaskPage.formatTime(this.task.startAt);
  }

  private async persist(): Promise<void> {
    this.task.intervalMs = Math.max(SELECTION_MIN_INTERVAL_MS,
      Math.min(SELECTION_MAX_INTERVAL_MS, this.task.intervalMs));
    await SelectionService.saveTask(this.context(), this.task);
  }

  private async toggle(field: string, value: boolean): Promise<void> {
    if (field === 'priority') {
      this.task.priorityMode = value;
    } else if (field === 'retry') {
      this.task.autoRetry = value;
    } else if (field === 'sync') {
      this.task.syncAfter = value;
    }
    await this.persist();
  }

  private async start(): Promise<void> {
    if (this.running() || this.preparing) {
      return;
    }
    if (this.queue.length === 0) {
      this.toast('抢课队列为空，请先添加课程');
      return;
    }
    const startAt: number = this.parseStartText();
    if (startAt <= 0) {
      this.toast('开始时间格式应为 2026-01-01 12:00:00');
      return;
    }
    this.task.startAt = startAt;
    this.error = '';
    this.preparing = true;
    try {
      await this.persist();
      const prep = await SelectionService.prepare(this.context());
      if (!prep.ok) {
        this.error = prep.message;
        this.preparing = false;
        return;
      }
      if (prep.message.length > 0) {
        this.toast(prep.message);
      }
      await SelectionService.start(this.context());
    } catch (error) {
      this.error = error instanceof Error ? error.message : '启动失败';
    } finally {
      this.preparing = false;
    }
  }

  private stop(): void {
    SelectionService.stop();
  }

  private async removeItem(item: SelectionQueueItem): Promise<void> {
    await SelectionService.removeFromQueue(this.context(), item.id);
    await this.reloadQueue();
  }

  private async moveItem(item: SelectionQueueItem, delta: number): Promise<void> {
    await SelectionService.moveQueueItem(this.context(), item.id, delta);
    await this.reloadQueue();
  }

  private async clearQueue(): Promise<void> {
    await SelectionService.clearQueue(this.context());
    await this.reloadQueue();
  }

  private queueStateLabel(state: string): string {
    if (state === SelectionQueueState.SUCCESS) {
      return '已选上';
    }
    if (state === SelectionQueueState.ALREADY) {
      return '已选过';
    }
    if (state === SelectionQueueState.FULL) {
      return '已满';
    }
    if (state === SelectionQueueState.CONFLICT) {
      return '冲突';
    }
    if (state === SelectionQueueState.LIMIT) {
      return '超限';
    }
    if (state === SelectionQueueState.ERROR) {
      return '失败';
    }
    return '待抢';
  }

  private queueStateColor(state: string): ResourceColor {
    if (state === SelectionQueueState.SUCCESS || state === SelectionQueueState.ALREADY) {
      return '#2E7D4F';
    }
    if (state === SelectionQueueState.PENDING) {
      return this.brandTextColor;
    }
    return '#C7362B';
  }

  private logColor(outcome: string): ResourceColor {
    if (outcome === 'SUCCESS' || outcome === 'ALREADY') {
      return '#2E7D4F';
    }
    if (outcome === 'FULL') {
      return '#C77700';
    }
    if (outcome === 'NETWORK' || outcome === 'SESSION' || outcome === 'UNKNOWN') {
      return '#C7362B';
    }
    return AppTheme.TEXT_SECONDARY;
  }

  private formatLogTime(at: number): string {
    const date: Date = new Date(at);
    const pad = (value: number): string => `${value}`.padStart(2, '0');
    return `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
  }

  private recentLogs(): SelectionLogEntry[] {
    const logs: SelectionLogEntry[] = this.snap().logs.slice();
    logs.reverse();
    return logs.slice(0, MAX_LOG_ROWS);
  }

  @Builder
  statusCard() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.phaseLabel(this.snap().phase))
          .fontSize(AppTheme.FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.phaseColor(this.snap().phase))
        Blank()
        Text(SelectionClock.formatOffset())
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_TERTIARY)
        Text('校准')
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(this.brandTextColor)
          .onClick(async () => {
            const ok: boolean = await SelectionEngine.calibrate();
            this.toast(ok ? '服务器时间已校准' : '校准失败，将按本机时间提交');
          })
      }
      .width('100%')

      Text(this.snap().message.length > 0 ? this.snap().message : '设定开始时间后点击“开始抢课”')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .width('100%')

      Row({ space: 16 }) {
        Column({ space: 2 }) {
          Text(this.snap().phase === SelectionRunPhase.ARMED ? this.countdown() : '—')
            .fontSize(AppTheme.FONT_HEADING)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.brandTextColor)
          Text('倒计时')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .alignItems(HorizontalAlign.Start)
        Column({ space: 2 }) {
          Text(`${this.snap().attempts}`)
            .fontSize(AppTheme.FONT_HEADING)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TEXT_PRIMARY)
          Text('提交次数')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .alignItems(HorizontalAlign.Start)
        Column({ space: 2 }) {
          Text(`${this.snap().success}`)
            .fontSize(AppTheme.FONT_HEADING)
            .fontWeight(FontWeight.Bold)
            .fontColor('#2E7D4F')
          Text('已选上')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Button(this.running() ? '停止' : (this.preparing ? '准备中…' : '开始抢课'))
          .height(40)
          .padding({ left: 18, right: 18 })
          .backgroundColor(this.running() ? '#C7362B' : this.brandColor)
          .fontColor(Color.White)
          .enabled(!this.preparing)
          .onClick(() => {
            if (this.running()) {
              this.stop();
            } else {
              this.start();
            }
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
  }

  @Builder
  settingsCard() {
    Column({ space: 10 }) {
      Text('任务参数')
        .fontSize(AppTheme.FONT_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .width('100%')

      Text('开始时间（服务器时间）')
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .width('100%')
      TextInput({ text: this.startText, placeholder: '2026-01-01 12:00:00' })
        .height(42)
        .backgroundColor(AppTheme.BG)
        .borderRadius(12)
        .fontSize(AppTheme.FONT_CAPTION)
        .enabled(!this.running())
        .onChange((value: string) => {
          this.startText = value;
          const parsed: number = this.parseStartText();
          if (parsed > 0) {
            this.task.startAt = parsed;
          }
        })
      Row({ space: 8 }) {
        Text('立即')
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(this.brandTextColor)
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .backgroundColor(AppTheme.BG)
          .borderRadius(11)
          .onClick(() => this.setStartOffset(3000))
        Text('+1 分钟')
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(this.brandTextColor)
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .backgroundColor(AppTheme.BG)
          .borderRadius(11)
          .onClick(() => this.setStartOffset(60000))
        Text('+5 分钟')
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(this.brandTextColor)
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .backgroundColor(AppTheme.BG)
          .borderRadius(11)
          .onClick(() => this.setStartOffset(300000))
      }
      .width('100%')

      Divider().color(AppTheme.DIVIDER).strokeWidth(0.5)

      Row() {
        Column({ space: 2 }) {
          Text('提交间隔')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_PRIMARY)
          Text('越短越快，但对教务压力更大')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Row({ space: 6 }) {
          Text('−')
            .fontSize(16)
            .fontColor(this.brandTextColor)
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .backgroundColor(AppTheme.BG)
            .borderRadius(14)
            .onClick(async () => {
              this.task.intervalMs = Math.max(SELECTION_MIN_INTERVAL_MS, this.task.intervalMs - 100);
              await this.persist();
            })
          Text(`${this.task.intervalMs}ms`)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_PRIMARY)
            .width(58)
            .textAlign(TextAlign.Center)
          Text('+')
            .fontSize(16)
            .fontColor(this.brandTextColor)
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .backgroundColor(AppTheme.BG)
            .borderRadius(14)
            .onClick(async () => {
              this.task.intervalMs = Math.min(SELECTION_MAX_INTERVAL_MS, this.task.intervalMs + 100);
              await this.persist();
            })
        }
      }
      .width('100%')

      this.switchRow('优先模式', '只死磕队首课程，选上后再看下一门', this.task.priorityMode, 'priority')
      this.switchRow('自动重试', '未知结果继续尝试；关闭后该门记为失败', this.task.autoRetry, 'retry')
      this.switchRow('成功后同步课表', '抢到后自动拉取最新课表', this.task.syncAfter, 'sync')

      Text('说明：HarmonyOS 不允许应用在后台长时间准时执行网络任务。请让本页保持前台、屏幕常亮，'
        + '退到后台时系统只会给约 3 分钟的宽限。')
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .width('100%')
        .lineHeight(17)
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  switchRow(title: string, desc: string, value: boolean, field: string) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_PRIMARY)
        Text(desc)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .maxLines(2)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(this.brandColor)
        .onChange((isOn: boolean) => this.toggle(field, isOn))
    }
    .width('100%')
    .padding({ top: 2, bottom: 2 })
  }

  @Builder
  queueCard() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('抢课队列')
          .fontSize(AppTheme.FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
        Text(`${this.queue.length}`)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_TERTIARY)
        Blank()
        if (this.queue.length > 0 && !this.running()) {
          Text('清空')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor('#C7362B')
            .onClick(() => this.clearQueue())
        }
      }
      .width('100%')

      if (this.queue.length === 0) {
        Text('队列为空，请回到选课列表添加课程')
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .width('100%')
          .padding({ top: 4, bottom: 4 })
      } else {
        ForEach(this.queue, (item: SelectionQueueItem, index: number) => {
          Row({ space: 8 }) {
            Text(`${index + 1}`)
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_TERTIARY)
              .width(16)
            Column({ space: 2 }) {
              Text(item.name)
                .fontSize(AppTheme.FONT_CAPTION)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.TEXT_PRIMARY)
                .maxLines(1)
              Text(`${item.teacher.length > 0 ? item.teacher + ' · ' : ''}${item.attempts > 0 ? item.attempts + ' 次' : '未开始'}${item.lastMessage.length > 0 ? ' · ' + item.lastMessage : ''}`)
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_TERTIARY)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text(this.queueStateLabel(item.state))
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(this.queueStateColor(item.state))
            if (!this.running()) {
              Text('↑')
                .fontSize(14)
                .fontColor(AppTheme.TEXT_SECONDARY)
                .width(22)
                .height(22)
                .textAlign(TextAlign.Center)
                .onClick(() => this.moveItem(item, -1))
              Text('↓')
                .fontSize(14)
                .fontColor(AppTheme.TEXT_SECONDARY)
                .width(22)
                .height(22)
                .textAlign(TextAlign.Center)
                .onClick(() => this.moveItem(item, 1))
              Text('✕')
                .fontSize(12)
                .fontColor('#C7362B')
                .width(22)
                .height(22)
                .textAlign(TextAlign.Center)
                .onClick(() => this.removeItem(item))
            }
          }
          .width('100%')
          .padding({ top: 6, bottom: 6 })
        }, (item: SelectionQueueItem) => `${item.id}-${item.state}-${item.position}-${item.attempts}`)
      }
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  logCard() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text('运行日志')
          .fontSize(AppTheme.FONT_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_PRIMARY)
        Blank()
        Text(this.showLogs ? '收起' : '展开')
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(this.brandTextColor)
          .onClick(() => {
            this.showLogs = !this.showLogs;
          })
      }
      .width('100%')

      if (this.showLogs) {
        if (this.recentLogs().length === 0) {
          Text('还没有提交记录')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .width('100%')
        } else {
          ForEach(this.recentLogs(), (entry: SelectionLogEntry) => {
            Row({ space: 8 }) {
              Text(this.formatLogTime(entry.at))
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_TERTIARY)
              Text(entry.name)
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_PRIMARY)
                .maxLines(1)
                .layoutWeight(1)
              Text(entry.message.length > 18 ? entry.message.substring(0, 18) : entry.message)
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(this.logColor(entry.outcome))
                .maxLines(1)
              Text(`${entry.rttMs}ms`)
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_TERTIARY)
                .width(48)
                .textAlign(TextAlign.End)
            }
            .width('100%')
          }, (entry: SelectionLogEntry) => `${entry.at}-${entry.kcrwdm}-${entry.outcome}`)
        }
      }
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          if (this.error.length > 0) {
            Text(this.error)
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor('#C7362B')
              .width('100%')
              .padding(12)
              .backgroundColor('#FFF0EE')
              .borderRadius(14)
          }

          this.statusCard()
          this.queueCard()
          this.settingsCard()
          this.logCard()
        }
        .width('100%')
        .padding({
          left: AppTheme.PAGE_PADDING,
          right: AppTheme.PAGE_PADDING,
          top: AppTheme.TALL_PAGE_TOP_INSET + 20,
          bottom: AppTheme.SPACE_XXL
        })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .titleBar(immersiveTitleBar('抢课任务'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
