import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { ElectricClient } from '../../services/electric/ElectricClient';
import {
  ELECTRIC_CAMPUSES,
  ElectricCampus,
  ElectricError,
  ElectricErrorKind,
  MeterReading
} from '../../services/electric/ElectricModels';

const STORE_NAME: string = 'electric_settings';
const METER_KEY: string = 'last_meter';
const CAMPUS_KEY: string = 'last_campus';

/** 余额下面那排小指标；用 @Prop 保证换表查询时也会重绘。 */
@Component
struct PowerStatCell {
  @Prop label: string = '';
  @Prop value: string = '--';

  build() {
    Column({ space: 2 }) {
      Text(this.value)
        .fontSize(AppTheme.FONT_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .maxLines(1)
      Text(this.label)
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .maxLines(1)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }
}

/**
 * 电费查询（Beta）。
 *
 * 接口由电表服务商（电精灵 bd.bdfairy.cn）提供；开关默认关闭，开启前有免责声明。
 * 页面只在本机保存上次的校区与表号，余额不落盘。
 */
@Component
export struct PowerPage {
  @Consume('brandTextColor') brandTextColor: string = '#0A59F7';
  @Consume('brandColor') brandColor: string = '#0A59F7';

  @State campusIndex: number = 0;
  @State meter: string = '';
  @State reading: MeterReading | null = null;
  @State loading: boolean = false;
  @State error: string = '';
  /** 多校区回退时的实时提示。 */
  @State progress: string = '';

  aboutToAppear(): void {
    this.loadLastQuery();
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

  private async loadLastQuery(): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context(), STORE_NAME);
      const savedMeter = await store.get(METER_KEY, '');
      if (typeof savedMeter === 'string') {
        this.meter = savedMeter;
      }
      const savedCampus = await store.get(CAMPUS_KEY, '');
      if (typeof savedCampus === 'string' && savedCampus.length > 0) {
        for (let index = 0; index < ELECTRIC_CAMPUSES.length; index++) {
          if (ELECTRIC_CAMPUSES[index].areaId === savedCampus) {
            this.campusIndex = index;
          }
        }
      }
    } catch (error) {
      // 上次查询条件丢了也不影响使用。
    }
  }

  private async rememberQuery(campus: ElectricCampus, meter: string): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context(), STORE_NAME);
      await store.put(METER_KEY, meter);
      await store.put(CAMPUS_KEY, campus.areaId);
      await store.flush();
    } catch (error) {
      // 记不住也照常查询。
    }
  }

  /**
   * 查询入口。
   *
   * 同一块表在不同校区的 areaId 下只有一个是有效的，选错校区时 /meter_main
   * 会直接挂住（不是报错），所以先记住表号、再按「当前校区 → 其余校区」回退，
   * 命中后把校区也记住，下次直接命中。
   */
  private async query(): Promise<void> {
    if (this.loading) {
      return;
    }
    const meter: string = this.meter.trim();
    if (meter.length === 0) {
      this.toast('请输入电表表号');
      return;
    }
    this.loading = true;
    this.error = '';
    this.reading = null;
    const started: number = this.campusIndex;
    // 先落盘表号与当前校区：查询失败也不至于下次重新输
    this.rememberQuery(ELECTRIC_CAMPUSES[started], meter);

    const order: number[] = [started];
    for (let index = 0; index < ELECTRIC_CAMPUSES.length; index++) {
      if (index !== started) {
        order.push(index);
      }
    }
    try {
      let lastError: ElectricError | null = null;
      for (let attempt = 0; attempt < order.length; attempt++) {
        const index: number = order[attempt];
        const campus: ElectricCampus = ELECTRIC_CAMPUSES[index];
        this.progress = attempt === 0
          ? `正在查询 ${campus.label} …`
          : `该校区没有这块表，正在尝试 ${campus.label} …`;
        try {
          const reading: MeterReading = await ElectricClient.query(campus, meter);
          this.reading = reading;
          this.campusIndex = index;
          this.rememberQuery(campus, meter);
          if (index !== started) {
            this.toast(`该表号属于${campus.label}，已自动切换`);
          }
          return;
        } catch (failure) {
          lastError = failure instanceof ElectricError
            ? failure : new ElectricError('查询失败，请稍后重试', ElectricErrorKind.NETWORK);
        }
      }
      if (lastError !== null) {
        this.error = lastError.kind === ElectricErrorKind.NETWORK
          ? `已尝试全部校区：${lastError.message}`
          : lastError.message;
      } else {
        this.error = '查询失败，请稍后重试';
      }
    } finally {
      this.loading = false;
      this.progress = '';
    }
  }

  private money(value: string): string {
    return PowerPage.decimal(value);
  }

  private kwh(value: string): string {
    const formatted: string = PowerPage.decimal(value);
    return formatted === '--' ? '--' : `${formatted} 度`;
  }

  private static decimal(value: string): string {
    if (value.length === 0) {
      return '--';
    }
    const parsed: number = Number.parseFloat(value);
    return Number.isNaN(parsed) ? value : parsed.toFixed(2);
  }

  @Builder
  campusChips() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(ELECTRIC_CAMPUSES, (campus: ElectricCampus, index: number) => {
          Text(campus.label)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(this.campusIndex === index ? Color.White : AppTheme.TEXT_SECONDARY)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(this.campusIndex === index ? this.brandColor : AppTheme.CARD_BG)
            .borderRadius(14)
            .onClick(() => {
              if (this.campusIndex !== index) {
                this.campusIndex = index;
                this.reading = null;
                this.error = '';
              }
            })
        }, (campus: ElectricCampus) => campus.areaId)
      }
      .padding({ right: 4 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .align(Alignment.Start)
  }

  @Builder
  queryCard() {
    Column({ space: 10 }) {
      Text('电表表号')
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .width('100%')
      Row({ space: AppTheme.SPACE_SM }) {
        TextInput({ text: this.meter, placeholder: '输入 12 位表号' })
          .type(InputType.Number)
          .maxLength(20)
          .height(40)
          .layoutWeight(1)
          .fontSize(AppTheme.FONT_BODY)
          .backgroundColor(AppTheme.BG)
          .borderRadius(12)
          .enterKeyType(EnterKeyType.Search)
          .onChange((value: string) => {
            this.meter = value;
          })
          .onSubmit(() => {
            this.query();
          })
        Button(this.loading ? '查询中' : '查询')
          .height(40)
          .fontSize(AppTheme.FONT_BODY)
          .backgroundColor(this.brandColor)
          .fontColor(Color.White)
          .enabled(!this.loading)
          .onClick(() => this.query())
      }
      .width('100%')
      Text('表号可在电精灵（微信服务号）里的房间信息，或电表本体上查看。')
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .width('100%')
        .lineHeight(16)
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  balanceCard(reading: MeterReading) {
    Column({ space: 12 }) {
      Row() {
        Text('当前余额')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_SECONDARY)
        Blank()
        Text(`${reading.campusLabel} · ${reading.meter}`)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .maxLines(1)
      }
      .width('100%')

      Row({ space: 4 }) {
        Text('¥')
          .fontSize(AppTheme.FONT_HEADING)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.brandTextColor)
        Text(this.money(reading.totalYuan))
          .fontSize(38)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.brandTextColor)
      }
      .alignItems(VerticalAlign.Bottom)

      Divider().color(AppTheme.DIVIDER).opacity(0.5)

      Row() {
        PowerStatCell({ label: '预付费余额', value: this.money(reading.prepaidYuan) })
        PowerStatCell({ label: '补助余额', value: this.money(reading.subsidyYuan) })
        PowerStatCell({ label: '累计电量', value: this.kwh(reading.totalKwh) })
      }
      .width('100%')

      if (reading.room.length > 0 || reading.meterStatus.length > 0 || reading.readingTime.length > 0) {
        Column({ space: 3 }) {
          if (reading.room.length > 0) {
            Text(`房间 ${reading.room}`)
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .width('100%')
          }
          if (reading.meterStatus.length > 0) {
            Text(`电表状态 ${reading.meterStatus}`)
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .width('100%')
          }
          if (reading.readingTime.length > 0) {
            Text(`抄表时间 ${reading.readingTime}`)
              .fontSize(AppTheme.FONT_TINY)
              .fontColor(AppTheme.TEXT_TERTIARY)
              .width('100%')
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  billCard(reading: MeterReading) {
    Column({ space: 8 }) {
      Row() {
        Text('月账单')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_SECONDARY)
        Blank()
        Text(reading.billMonth.length > 0 ? reading.billMonth : '--')
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_TERTIARY)
      }
      .width('100%')
      Row() {
        Column({ space: 2 }) {
          Text(this.kwh(reading.billKwh))
            .fontSize(AppTheme.FONT_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_PRIMARY)
          Text('用电量')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Column({ space: 2 }) {
          Text(reading.billYuan.length > 0 ? `¥ ${reading.billYuan}` : '--')
            .fontSize(AppTheme.FONT_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_PRIMARY)
          Text('用电金额')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  errorCard() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(26)
        .fontColor([AppTheme.TEXT_TERTIARY])
      Text(this.error)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .lineHeight(18)
      Text('重试')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(this.brandTextColor)
        .onClick(() => this.query())
    }
    .width('100%')
    .padding(AppTheme.SPACE_XL)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: AppTheme.SPACE_MD }) {
          this.campusChips()
          this.queryCard()

          if (this.loading) {
            Column({ space: 8 }) {
              LoadingProgress()
                .width(28)
                .height(28)
                .color(this.brandTextColor)
              Text(this.progress.length > 0 ? this.progress : '正在查询电表…')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_TERTIARY)
                .textAlign(TextAlign.Center)
                .padding({ left: AppTheme.SPACE_LG, right: AppTheme.SPACE_LG })
            }
            .width('100%')
            .height(150)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.error.length > 0) {
            this.errorCard()
          } else if (this.reading !== null) {
            this.balanceCard(this.reading)
            if (this.reading.billMonth.length > 0 || this.reading.billKwh.length > 0) {
              this.billCard(this.reading)
            }
          }

          Text('Beta 功能：接口由电表服务商（电精灵）提供，仍在适配中，可能随时调整或中断；' +
            '结果仅供参考，请以电表读数和缴费记录为准。表号仅保存在本机，余额不写入备份。')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .width('100%')
            .lineHeight(17)
            .padding({ top: 4, bottom: 8 })
        }
        .width('100%')
        .padding({
          left: AppTheme.PAGE_PADDING,
          right: AppTheme.PAGE_PADDING,
          top: AppTheme.TALL_PAGE_TOP_INSET + 12,
          bottom: AppTheme.PAGE_PADDING
        })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .titleBar(immersiveTitleBar('电费查询'))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
  }
}
