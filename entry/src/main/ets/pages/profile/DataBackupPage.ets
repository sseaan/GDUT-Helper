import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { TimetableState } from '../../state/TimetableState';
import { BackupBundle, BackupPreview, previewOf } from '../../services/backup/BackupModels';
import { BackupService } from '../../services/backup/BackupService';
import { IcsImportService, IcsPreview } from '../../services/importexport/IcsImportService';
import { XlsxImportService, XlsxPreview } from '../../services/importexport/XlsxImportService';
import { Event } from '../../domain/model/TimetableModels';
import { XlsxRow } from '../../services/importexport/XlsxParser';

interface PreviewLine {
  title: string;
  detail: string;
}

@Component
export struct DataBackupPage {
  @State busy: boolean = false;
  @State error: string = '';
  @State status: string = '';
  @State showPreview: boolean = false;
  @State previewTitle: string = '';
  @State previewLines: PreviewLine[] = [];
  @State previewWarnings: string[] = [];
  @State pendingKind: string = '';
  @State pendingRestore: BackupBundle | null = null;
  @State pendingIcs: IcsPreview | null = null;
  @State pendingXlsx: XlsxPreview | null = null;

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

  private formatDate(value: number): string {
    const date: Date = new Date(value);
    return `${date.getMonth() + 1}/${date.getDate()} ${`${date.getHours()}`.padStart(2, '0')}:${`${date.getMinutes()}`.padStart(2, '0')}`;
  }

  private async exportBackup(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.error = '';
    this.status = '';
    try {
      await BackupService.exportToFile(this.context());
      this.status = '备份已导出';
      this.toast('备份已导出');
    } catch (error) {
      this.error = error instanceof Error ? error.message : '导出失败';
    } finally {
      this.busy = false;
    }
  }

  private async pickRestore(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.error = '';
    this.status = '';
    try {
      const bundle: BackupBundle = await BackupService.readBundle(this.context());
      const preview: BackupPreview = previewOf(bundle);
      this.pendingRestore = bundle;
      this.pendingIcs = null;
      this.pendingXlsx = null;
      this.pendingKind = 'json';
      this.previewTitle = '恢复 JSON 备份';
      this.previewLines = [
        { title: `${preview.semesters} 个学期`, detail: `${preview.courses} 门课程` },
        { title: `${preview.events} 个日程/考试`, detail: `${preview.exceptions} 条单周调整` },
        { title: `导出时间 ${this.formatDate(preview.exportedAt)}`, detail: `${preview.tombstones} 条删除记录` }
      ];
      this.previewWarnings = ['恢复会覆盖当前本地数据；教务密码和 Cookie 不会恢复。'];
      this.showPreview = true;
    } catch (error) {
      this.error = error instanceof Error ? error.message : '读取备份失败';
    } finally {
      this.busy = false;
    }
  }

  private async pickIcs(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.error = '';
    this.status = '';
    try {
      const uri: string = await BackupService.pickFile(this.context(), 'ics');
      const preview: IcsPreview = await IcsImportService.preview(this.context(),
        BackupService.readTextUri(uri));
      this.pendingIcs = preview;
      this.pendingRestore = null;
      this.pendingXlsx = null;
      this.pendingKind = 'ics';
      this.previewTitle = '导入 ICS';
      this.previewLines = preview.events.slice(0, 8).map((event): PreviewLine => ({
        title: event.title,
        detail: `${this.formatDate(event.startTime)}${event.location.length > 0 ? ' · ' + event.location : ''}`
      }));
      this.previewWarnings = [`新增 ${preview.events.length} 个事件 · 跳过重复 ${preview.duplicates} 个`];
      if (preview.warnings.length > 0) {
        this.previewWarnings.push(...preview.warnings.slice(0, 5));
      }
      this.showPreview = true;
    } catch (error) {
      this.error = error instanceof Error ? error.message : '读取 ICS 失败';
    } finally {
      this.busy = false;
    }
  }

  private async pickXlsx(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.error = '';
    this.status = '';
    try {
      const uri: string = await BackupService.pickFile(this.context(), 'xlsx');
      const preview: XlsxPreview = await XlsxImportService.preview(this.context(), uri);
      this.pendingXlsx = preview;
      this.pendingRestore = null;
      this.pendingIcs = null;
      this.pendingKind = 'xlsx';
      this.previewTitle = '导入 XLSX 课表';
      this.previewLines = preview.courses.slice(0, 8).map((course): PreviewLine => ({
        title: course.name,
        detail: `${this.weekdayName(course.weekday)} ${course.startPeriod}-${course.endPeriod} 节 · ${course.room.length > 0 ? course.room : '未填写教室'}`
      }));
      this.previewWarnings = [`新增 ${preview.courses.length} 门课程 · 跳过重复 ${preview.duplicates} 门`];
      if (preview.warnings.length > 0) {
        this.previewWarnings.push(...preview.warnings.slice(0, 5));
      }
      this.showPreview = true;
    } catch (error) {
      this.error = error instanceof Error ? error.message : '读取 XLSX 失败';
    } finally {
      this.busy = false;
    }
  }

  private weekdayName(day: number): string {
    const labels: string[] = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return labels[day] ?? '';
  }

  private async applyPending(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (this.pendingKind === 'json' && this.pendingRestore !== null) {
      const bundle: BackupBundle = this.pendingRestore;
      AlertDialog.show({
        title: '恢复备份',
        message: '恢复将覆盖当前学期、课程、日程和缓存，确定继续吗？',
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: {
          value: '恢复',
          fontColor: Color.Red,
          action: () => {
            this.doRestore(bundle);
          }
        }
      });
      return;
    }
    this.busy = true;
    try {
      if (this.pendingKind === 'ics' && this.pendingIcs !== null) {
        const count: number = await IcsImportService.apply(this.context(), this.pendingIcs);
        this.status = `已导入 ${count} 个日程`;
      } else if (this.pendingKind === 'xlsx' && this.pendingXlsx !== null) {
        const count: number = await XlsxImportService.apply(this.context(), this.pendingXlsx);
        this.status = `已导入 ${count} 门课程`;
      }
      this.showPreview = false;
      TimetableState.bump();
      this.toast(this.status);
    } catch (error) {
      this.error = error instanceof Error ? error.message : '导入失败';
      this.showPreview = false;
    } finally {
      this.busy = false;
    }
  }

  private confirmClear(): void {
    AlertDialog.show({
      title: '清空本地数据',
      message: '将删除学期、课程、日程/考试、成绩与体测缓存、桌面卡片快照，并清理已写入的系统日历和提醒。登录账号和外观设置会保留。确定继续吗？',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '清空',
        fontColor: Color.Red,
        action: () => {
          this.doClear();
        }
      }
    });
  }

  private async doClear(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.error = '';
    this.status = '';
    try {
      await BackupService.clearLocalData(this.context());
      this.status = '本地数据已清空';
      TimetableState.bump();
      this.toast('本地数据已清空');
    } catch (error) {
      this.error = error instanceof Error ? error.message : '清空失败';
    } finally {
      this.busy = false;
    }
  }

  private async doRestore(bundle: BackupBundle): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      await BackupService.restore(this.context(), bundle);
      this.status = '备份已恢复';
      this.showPreview = false;
      TimetableState.bump();
      this.toast('备份已恢复');
    } catch (error) {
      this.error = error instanceof Error ? error.message : '恢复失败';
    } finally {
      this.busy = false;
    }
  }

  @Builder
  actionRow(icon: Resource, title: string, detail: string, onClick: () => void) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(19)
        .fontColor([AppTheme.TEXT_SECONDARY])
      Column({ space: 2 }) {
        Text(title)
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_PRIMARY)
        Text(detail)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .maxLines(2)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13)
        .fontColor([AppTheme.TEXT_TERTIARY])
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
    .onClick(onClick)
  }

  @Builder
  previewSheet() {
    Column({ space: 10 }) {
      Row() {
        Text(this.previewTitle)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT_PRIMARY)
        Blank()
        Text('关闭')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.BRAND)
          .onClick(() => { this.showPreview = false; })
      }
      .width('100%')

      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.previewLines, (line: PreviewLine, index: number) => {
            Row({ space: 10 }) {
              Text(`${index + 1}`)
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(AppTheme.TEXT_TERTIARY)
                .width(18)
              Column({ space: 2 }) {
                Text(line.title)
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(AppTheme.TEXT_PRIMARY)
                  .maxLines(1)
                Text(line.detail)
                  .fontSize(AppTheme.FONT_TINY)
                  .fontColor(AppTheme.TEXT_SECONDARY)
                  .maxLines(1)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor(AppTheme.CARD_BG)
            .borderRadius(12)
          }, (line: PreviewLine, index: number) => `preview-${index}`)

          ForEach(this.previewWarnings, (warning: string) => {
            Text(warning)
              .fontSize(AppTheme.FONT_TINY)
              .fontColor('#B26A00')
              .width('100%')
              .padding(10)
              .backgroundColor('#FFF7E6')
              .borderRadius(10)
          }, (warning: string) => warning)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Button(this.pendingKind === 'json' ? '覆盖并恢复' : '确认导入')
        .width('100%')
        .height(46)
        .borderRadius(23)
        .enabled(!this.busy)
        .onClick(() => this.applyPending())
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppTheme.PAGE_PADDING, right: AppTheme.PAGE_PADDING, top: 18, bottom: 20 })
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: 14 }) {
          Text('备份、恢复和课表导入')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_SECONDARY)
            .width('100%')

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

          Text('备份与恢复')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .width('100%')
            .padding({ left: 6, top: 2 })
          Column() {
            this.actionRow($r('sys.symbol.doc_plaintext'), '导出 JSON 备份', '学期、课程、日程、缓存和偏好设置', () => this.exportBackup())
            Divider().color(AppTheme.DIVIDER).opacity(0.5).margin({ left: 16, right: 16 })
            this.actionRow($r('sys.symbol.arrow_clockwise'), '从 JSON 恢复', '先预览数据数量和覆盖范围，再确认恢复', () => this.pickRestore())
            Divider().color(AppTheme.DIVIDER).opacity(0.5).margin({ left: 16, right: 16 })
            this.actionRow($r('sys.symbol.exclamationmark_triangle_fill'), '清空本地数据', '删除学期、课程、日程和缓存；保留登录账号与偏好', () => this.confirmClear())
          }
          .width('100%')
          .backgroundColor($r('app.color.profile_card_bg'))
          .borderRadius(18)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 0.5, color: '#66FFFFFF' })
          .clip(true)

          Text('导入')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .width('100%')
            .padding({ left: 6, top: 2 })
          Column() {
            this.actionRow($r('sys.symbol.calendar'), '导入 ICS', '课程、日程和考试事件；同一 UID 自动去重', () => this.pickIcs())
            Divider().color(AppTheme.DIVIDER).opacity(0.5).margin({ left: 16, right: 16 })
            this.actionRow($r('sys.symbol.list_square'), '导入 XLSX 课表', '识别课程名称、星期、节次、周次、教师和教室', () => this.pickXlsx())
          }
          .width('100%')
          .backgroundColor($r('app.color.profile_card_bg'))
          .borderRadius(18)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 0.5, color: '#66FFFFFF' })
          .clip(true)

          Text('备份不包含教务密码、Cookie、Token、验证码或系统日历映射。导入失败不会写入数据；恢复前请确认覆盖范围。')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .width('100%')
            .lineHeight(16)
            .padding({ top: 4 })
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
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .titleBar(immersiveTitleBar('数据与备份'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
    .bindSheet(this.showPreview, this.previewSheet(), {
      height: 560,
      dragBar: true,
      showClose: false,
      backgroundColor: AppTheme.BG,
      onDisappear: () => { this.showPreview = false; }
    })
  }
}
