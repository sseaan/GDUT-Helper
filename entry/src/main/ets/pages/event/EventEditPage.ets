import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { Event } from '../../domain/model/TimetableModels';
import { EventEditParam } from '../../domain/model/NavParams';
import { TimetableRepository } from '../../data/TimetableRepository';
import { TimetableState } from '../../state/TimetableState';

@Component
export struct EventEditPage {
  param: EventEditParam = { semesterId: '', date: '', eventId: '' };
  onDone: () => void = () => {};

  @State title: string = '';
  @State location: string = '';
  @State note: string = '';
  @State startTime: string = '09:00';
  @State endTime: string = '10:00';
  @State allDay: boolean = false;
  @State existing: Event | null = null;
  @State loading: boolean = true;
  @State saving: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (error) {
      // ignore
    }
  }

  private async load(): Promise<void> {
    try {
      if (this.param.eventId.length > 0) {
        const event: Event | null = await TimetableRepository.getEvent(this.context(), this.param.eventId);
        if (event !== null) {
          this.existing = event;
          this.title = event.title;
          this.location = event.location;
          this.note = event.note;
          this.allDay = event.allDay;
          this.startTime = this.timeText(event.startTime);
          this.endTime = this.timeText(event.endTime);
        }
      }
    } catch (error) {
      this.toast('读取日程失败');
    } finally {
      this.loading = false;
    }
  }

  private timeText(ms: number): string {
    const date: Date = new Date(ms);
    return `${`${date.getUTCHours()}`.padStart(2, '0')}:${`${date.getUTCMinutes()}`.padStart(2, '0')}`;
  }

  private dateLabel(): string {
    const parts: string[] = this.param.date.split('-');
    if (parts.length !== 3) {
      return this.param.date;
    }
    return `${Number.parseInt(parts[1], 10)}月${Number.parseInt(parts[2], 10)}日`;
  }

  private eventTime(date: string, text: string, endOfDay: boolean = false): number {
    const dateParts: string[] = date.split('-');
    const timeParts: string[] = text.split(':');
    if (dateParts.length !== 3 || timeParts.length !== 2) {
      return 0;
    }
    const year: number = Number.parseInt(dateParts[0], 10);
    const month: number = Number.parseInt(dateParts[1], 10) - 1;
    const day: number = Number.parseInt(dateParts[2], 10);
    const hour: number = endOfDay ? 23 : Number.parseInt(timeParts[0], 10);
    const minute: number = endOfDay ? 59 : Number.parseInt(timeParts[1], 10);
    if (Number.isNaN(hour) || Number.isNaN(minute) || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return 0;
    }
    return Date.UTC(year, month, day, hour, minute);
  }

  private validTime(text: string): boolean {
    return this.eventTime(this.param.date, text) !== 0;
  }

  private async save(): Promise<void> {
    if (this.saving) {
      return;
    }
    if (this.title.trim().length === 0) {
      this.toast('请填写日程标题');
      return;
    }
    const start: number = this.allDay ? this.eventTime(this.param.date, '00:00') : this.eventTime(this.param.date, this.startTime);
    const end: number = this.allDay ? this.eventTime(this.param.date, '00:00', true) : this.eventTime(this.param.date, this.endTime);
    if (start === 0 || end === 0) {
      this.toast('时间格式应为 HH:mm');
      return;
    }
    if (end <= start) {
      this.toast('结束时间需晚于开始时间');
      return;
    }
    this.saving = true;
    try {
      const event: Event = {
        id: this.param.eventId,
        semesterId: this.param.semesterId,
        title: this.title.trim(),
        startTime: start,
        endTime: end,
        allDay: this.allDay,
        location: this.location.trim(),
        note: this.note.trim(),
        category: 'GENERAL',
        source: 'MANUAL',
        externalId: this.existing !== null ? this.existing.externalId : '',
        createdAt: this.existing !== null ? this.existing.createdAt : 0,
        updatedAt: 0
      };
      await TimetableRepository.upsertEvent(this.context(), event);
      TimetableState.bump();
      this.onDone();
    } catch (error) {
      this.toast('保存日程失败');
    } finally {
      this.saving = false;
    }
  }

  private async remove(): Promise<void> {
    if (this.param.eventId.length === 0) {
      return;
    }
    try {
      await TimetableRepository.deleteEvent(this.context(), this.param.eventId);
      TimetableState.bump();
      this.onDone();
    } catch (error) {
      this.toast('删除日程失败');
    }
  }

  @Builder
  fieldLabel(label: ResourceStr) {
    Text(label)
      .fontSize(AppTheme.FONT_CAPTION)
      .fontColor(AppTheme.TEXT_SECONDARY)
      .width('100%')
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: AppTheme.SPACE_MD }) {
          Text(this.dateLabel())
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TEXT_PRIMARY)
            .width('100%')
            .margin({ bottom: 4 })

          Column({ space: AppTheme.SPACE_SM }) {
            this.fieldLabel('标题')
            TextInput({ text: this.title, placeholder: '例如：考试、会议、体检' })
              .height(44)
              .backgroundColor(AppTheme.BG)
              .borderRadius(12)
              .onChange((value: string) => { this.title = value; })
            this.fieldLabel('地点')
            TextInput({ text: this.location, placeholder: '可选' })
              .height(44)
              .backgroundColor(AppTheme.BG)
              .borderRadius(12)
              .onChange((value: string) => { this.location = value; })
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(AppTheme.CARD_RADIUS)

          Column({ space: AppTheme.SPACE_SM }) {
            Row() {
              Text('全天')
                .fontSize(AppTheme.FONT_BODY)
                .fontColor(AppTheme.TEXT_PRIMARY)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.allDay })
                .onChange((isOn: boolean) => { this.allDay = isOn; })
            }
            .width('100%')
            .height(36)

            if (!this.allDay) {
              Row({ space: AppTheme.SPACE_SM }) {
                TextInput({ text: this.startTime, placeholder: '09:00' })
                  .layoutWeight(1)
                  .height(44)
                  .backgroundColor(AppTheme.BG)
                  .borderRadius(12)
                  .onChange((value: string) => { this.startTime = value; })
                Text('至')
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(AppTheme.TEXT_SECONDARY)
                TextInput({ text: this.endTime, placeholder: '10:00' })
                  .layoutWeight(1)
                  .height(44)
                  .backgroundColor(AppTheme.BG)
                  .borderRadius(12)
                  .onChange((value: string) => { this.endTime = value; })
              }
              .width('100%')
            }
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(AppTheme.CARD_RADIUS)

          Column({ space: AppTheme.SPACE_SM }) {
            this.fieldLabel('备注')
            TextArea({ text: this.note, placeholder: '可选' })
              .height(96)
              .backgroundColor(AppTheme.BG)
              .borderRadius(12)
              .onChange((value: string) => { this.note = value; })
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(AppTheme.CARD_RADIUS)

          Button(this.saving ? '保存中…' : '保存日程')
            .width('100%')
            .height(48)
            .borderRadius(24)
            .enabled(!this.saving)
            .onClick(() => this.save())

          if (this.param.eventId.length > 0) {
            Button('删除日程')
              .width('100%')
              .height(48)
              .borderRadius(24)
              .backgroundColor(AppTheme.BG)
              .fontColor('#C7362B')
              .onClick(() => this.remove())
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
    .titleBar(immersiveTitleBar(this.param.eventId.length > 0 ? $r('app.string.event_edit_title') : $r('app.string.event_add_title')))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
