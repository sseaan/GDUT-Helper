import { common } from '@kit.AbilityKit';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { AppTheme } from '../../common/Theme';
import { immersiveTitleBar } from '../../common/TitleBarOptions';
import { TimetableRepository } from '../../data/TimetableRepository';
import { isoDate, mondayOf, parseIsoDate, weekOf } from '../../domain/timetable/TimetableEngine';
import {
  ClassroomBuilding,
  ClassroomOccupancy,
  ClassroomRoom,
  JwcwxError,
  JwcwxErrorKind,
  OccupancyType
} from '../../services/jwcwx/JwcwxModels';
import { JwcwxClient } from '../../services/jwcwx/JwcwxClient';
import { JwcwxCache } from '../../services/jwcwx/JwcwxCache';
import { DEFAULT_PERIOD_TIMES } from '../../domain/model/Periods';

interface DayOption {
  iso: string;
  weekday: string;
  label: string;
  today: boolean;
}

interface CampusOption {
  code: string;
  name: string;
}

interface RoomDaySchedule {
  iso: string;
  weekday: string;
  label: string;
  items: ClassroomOccupancy[];
}

const PERIODS: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
const WEEKDAYS: string[] = ['一', '二', '三', '四', '五', '六', '日'];

@Component
export struct EmptyClassroomPage {
  onOpenSync: () => void = () => {};
  private client: JwcwxClient | null = null;
  @State buildings: ClassroomBuilding[] = [];
  @State campuses: CampusOption[] = [];
  @State rooms: ClassroomRoom[] = [];
  @State occupancies: ClassroomOccupancy[] = [];
  @State days: DayOption[] = [];
  @State selectedCampusCode: string = '';
  @State selectedBuildingCode: string = '';
  @State selectedDate: string = '';
  @State selectedFilter: string = 'all';
  @State currentWeek: number = 1;
  @State semesterStart: string = '';
  @State loading: boolean = true;
  @State error: string = '';
  @State needLogin: boolean = false;
  @State showPicker: boolean = false;
  @State searchText: string = '';
  @State offline: boolean = false;
  @State sheetMode: string = 'building';
  @State selectedRoom: ClassroomRoom | null = null;
  @State roomWeek: RoomDaySchedule[] = [];
  @State roomLoading: boolean = false;

  aboutToAppear(): void {
    this.init();
  }

  private async init(): Promise<void> {
    await this.initWeek();
    await this.load();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async initWeek(): Promise<void> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const semester = await TimetableRepository.getCurrentSemester(context);
      if (semester !== null && semester !== undefined) {
        this.semesterStart = semester.startDate;
        this.currentWeek = weekOf(semester.startDate, new Date());
      }
    } catch (error) {
      this.semesterStart = '';
      this.currentWeek = 1;
    }
    this.buildWeek();
  }

  private buildWeek(): void {
    const now: Date = new Date();
    const today: string = isoDate(new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate())));
    let monday: Date;
    if (this.semesterStart.length > 0) {
      const startMonday: Date = mondayOf(parseIsoDate(this.semesterStart));
      monday = new Date(Date.UTC(startMonday.getUTCFullYear(), startMonday.getUTCMonth(),
        startMonday.getUTCDate() + (this.currentWeek - 1) * 7));
    } else {
      monday = mondayOf(new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate())));
    }
    const result: DayOption[] = [];
    for (let offset = 0; offset < 7; offset++) {
      const date: Date = new Date(Date.UTC(monday.getUTCFullYear(), monday.getUTCMonth(),
        monday.getUTCDate() + offset));
      const iso: string = isoDate(date);
      result.push({
        iso: iso,
        weekday: WEEKDAYS[offset],
        label: `${date.getUTCMonth() + 1}/${date.getUTCDate()}`,
        today: iso === today
      });
    }
    this.days = result;
    const todayInWeek: DayOption | undefined = result.find((item: DayOption) => item.today);
    this.selectedDate = todayInWeek === undefined ? result[0].iso : todayInWeek.iso;
  }

  private async shiftWeek(delta: number): Promise<void> {
    const next: number = this.currentWeek + delta;
    if (next < 1) {
      return;
    }
    this.currentWeek = next;
    this.buildWeek();
    if (this.selectedBuildingCode.length > 0) {
      await this.loadOccupancy();
    }
  }

  private selectedBuilding(): ClassroomBuilding | null {
    return this.buildings.find((item: ClassroomBuilding) => item.code === this.selectedBuildingCode) ?? null;
  }

  private selectedCampusName(): string {
    const campus: CampusOption | undefined = this.campuses.find((item: CampusOption) =>
      item.code === this.selectedCampusCode);
    return campus === undefined ? '' : campus.name;
  }

  private buildingLabel(): string {
    const building: ClassroomBuilding | null = this.selectedBuilding();
    if (building === null) {
      return '请选择教学楼';
    }
    return building.campusName.length > 0 ? `${building.campusName} · ${building.name}` : building.name;
  }

  private buildCampuses(buildings: ClassroomBuilding[]): CampusOption[] {
    const result: CampusOption[] = [];
    for (const building of buildings) {
      const code: string = building.campusCode.length > 0 ? building.campusCode : building.campusName;
      const name: string = building.campusName.length > 0 ? building.campusName : '未标注校区';
      if (!result.some((item: CampusOption) => item.code === code)) {
        result.push({ code: code, name: name });
      }
    }
    return result;
  }

  private sheetBuildings(): ClassroomBuilding[] {
    const keyword: string = this.searchText.trim();
    return this.buildings.filter((building: ClassroomBuilding) => {
      const campusMatch: boolean = this.selectedCampusCode.length === 0 ||
        building.campusCode === this.selectedCampusCode ||
        (building.campusCode.length === 0 && building.campusName === this.selectedCampusCode);
      if (!campusMatch) {
        return false;
      }
      if (keyword.length === 0) {
        return true;
      }
      return building.name.includes(keyword) || building.campusName.includes(keyword);
    });
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    this.needLogin = false;
    try {
      if (this.client === null) {
        this.client = new JwcwxClient();
      }
      this.buildings = await this.client.fetchBuildings();
      this.campuses = this.buildCampuses(this.buildings);
      this.offline = false;
      if (this.campuses.length === 0) {
        this.error = '没有可查询的教学楼';
      } else {
        await JwcwxCache.saveBuildings(this.context(), this.buildings);
      }
    } catch (error) {
      this.buildings = await JwcwxCache.loadBuildings(this.context());
      this.campuses = this.buildCampuses(this.buildings);
      if (this.buildings.length > 0) {
        this.offline = true;
        this.error = '无法连接教室查询系统，当前显示本地教学楼缓存';
      } else {
        this.handleError(error);
      }
    } finally {
      this.loading = false;
    }
  }

  private async loadRoomsAndOccupancy(): Promise<void> {
    if (this.client === null || this.selectedBuildingCode.length === 0) {
      return;
    }
    this.loading = true;
    this.error = '';
    try {
      const loadedRooms: ClassroomRoom[] = await this.client.fetchRooms(this.selectedBuildingCode);
      if (loadedRooms.length === 0) {
        throw new JwcwxError('该教学楼暂未返回教室数据，请切换楼栋重试', JwcwxErrorKind.PROTOCOL);
      }
      this.rooms = loadedRooms;
      this.occupancies = await this.client.fetchOccupancy(this.selectedBuildingCode, this.selectedDate);
      this.offline = false;
      await JwcwxCache.saveRooms(this.context(), this.selectedBuildingCode, this.rooms);
      await JwcwxCache.saveOccupancy(this.context(), this.selectedBuildingCode, this.selectedDate,
        this.occupancies);
    } catch (error) {
      const cachedRooms: ClassroomRoom[] = await JwcwxCache.loadRooms(this.context(), this.selectedBuildingCode);
      const cachedOccupancy: ClassroomOccupancy[] = await JwcwxCache.loadOccupancy(this.context(),
        this.selectedBuildingCode, this.selectedDate);
      if (cachedRooms.length > 0) {
        this.rooms = cachedRooms;
        this.occupancies = cachedOccupancy;
        this.offline = true;
        this.error = '无法连接教室查询系统，当前显示本地缓存';
      } else {
        this.handleError(error);
      }
    } finally {
      this.loading = false;
    }
  }

  private async loadOccupancy(): Promise<void> {
    if (this.client === null || this.selectedBuildingCode.length === 0) {
      return;
    }
    this.loading = true;
    this.error = '';
    try {
      this.occupancies = await this.client.fetchOccupancy(this.selectedBuildingCode, this.selectedDate);
      this.offline = false;
      await JwcwxCache.saveOccupancy(this.context(), this.selectedBuildingCode, this.selectedDate,
        this.occupancies);
    } catch (error) {
      const cachedOccupancy: ClassroomOccupancy[] = await JwcwxCache.loadOccupancy(this.context(),
        this.selectedBuildingCode, this.selectedDate);
      if (cachedOccupancy.length > 0) {
        this.occupancies = cachedOccupancy;
        this.offline = true;
        this.error = '无法连接教室查询系统，当前显示本地缓存';
      } else {
        this.handleError(error);
      }
    } finally {
      this.loading = false;
    }
  }

  private handleError(error: Object): void {
    if (error instanceof JwcwxError) {
      this.error = error.message;
      if (error.kind === JwcwxErrorKind.CREDENTIALS || error.kind === JwcwxErrorKind.SESSION) {
        this.needLogin = true;
      }
    } else if (error instanceof Error) {
      this.error = error.message.length > 0 ? error.message : '查询空教室失败，请稍后重试';
    } else {
      this.error = '查询空教室失败，请稍后重试';
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      // Toast failure must not break the page.
    }
  }

  private filterPeriods(): number[] {
    if (this.selectedFilter === 'free' || this.selectedFilter === 'all') {
      return [];
    }
    const bounds: string[] = this.selectedFilter.split('-');
    if (bounds.length !== 2) {
      return [];
    }
    const start: number = Number.parseInt(bounds[0], 10);
    const end: number = Number.parseInt(bounds[1], 10);
    if (Number.isNaN(start) || Number.isNaN(end)) {
      return [];
    }
    const result: number[] = [];
    for (let period = start; period <= end; period++) {
      result.push(period);
    }
    return result;
  }

  private isOccupied(room: ClassroomRoom, period: number): boolean {
    return this.occupancies.some((item: ClassroomOccupancy) =>
      item.roomCode === room.code && item.periods.includes(period));
  }

  private occupancyAt(room: ClassroomRoom, period: number): ClassroomOccupancy | null {
    return this.occupancies.find((item: ClassroomOccupancy) =>
      item.roomCode === room.code && item.periods.includes(period)) ?? null;
  }

  private occupancyColor(item: ClassroomOccupancy | null): string {
    if (item === null) {
      return '#E4E7EC';
    }
    return item.type === OccupancyType.COURSE ? '#BBD8FF' : '#FFC1C1';
  }

  private occupancyTag(item: ClassroomOccupancy): string {
    if (item.type === OccupancyType.COURSE) {
      return '课';
    }
    if (item.type === OccupancyType.BORROWED) {
      return '借';
    }
    if (item.type === OccupancyType.LOCKED) {
      return '锁';
    }
    if (item.type === OccupancyType.EXAM) {
      return '考';
    }
    return '占';
  }

  private roomOccupancyTitle(item: ClassroomOccupancy): string {
    if (item.courseName.length > 0) {
      return item.courseName;
    }
    if (item.note.length > 0) {
      return item.note;
    }
    return this.typeLabel(item.type);
  }

  private freePeriods(room: ClassroomRoom): number[] {
    return PERIODS.filter((period: number) => !this.isOccupied(room, period));
  }

  private matchesFilter(room: ClassroomRoom): boolean {
    if (this.selectedFilter === 'all') {
      return true;
    }
    const free: number[] = this.freePeriods(room);
    if (this.selectedFilter === 'free') {
      return free.length === PERIODS.length;
    }
    return this.filterPeriods().every((period: number) => free.includes(period));
  }

  private visibleRooms(): ClassroomRoom[] {
    return this.rooms.filter((room: ClassroomRoom) => this.matchesFilter(room));
  }

  private periodText(periods: number[]): string {
    if (periods.length === 0) {
      return '无';
    }
    const result: string[] = [];
    let start: number = periods[0];
    let previous: number = periods[0];
    for (let i = 1; i <= periods.length; i++) {
      const current: number = i < periods.length ? periods[i] : -1;
      if (current !== previous + 1) {
        result.push(start === previous ? `${start}` : `${start}-${previous}`);
        start = current;
      }
      previous = current === -1 ? previous : current;
    }
    return result.join('、');
  }

  private occupiedText(room: ClassroomRoom): string {
    const items: ClassroomOccupancy[] = this.occupancies.filter((item: ClassroomOccupancy) =>
      item.roomCode === room.code);
    if (items.length === 0) {
      return '全天空闲';
    }
    return items.slice(0, 2).map((item: ClassroomOccupancy) => {
      if (item.courseName.length > 0) {
        return item.courseName;
      }
      return item.note.length > 0 ? item.note : this.typeLabel(item.type);
    }).join(' · ');
  }

  private typeLabel(type: OccupancyType): string {
    if (type === OccupancyType.COURSE) {
      return '上课';
    }
    if (type === OccupancyType.BORROWED) {
      return '借用';
    }
    if (type === OccupancyType.LOCKED) {
      return '锁定';
    }
    if (type === OccupancyType.EXAM) {
      return '考试';
    }
    return '占用';
  }

  private selectedDateLabel(): string {
    const day: DayOption | undefined = this.days.find((item: DayOption) => item.iso === this.selectedDate);
    return day === undefined ? this.selectedDate : `周${day.weekday} ${day.label}`;
  }

  private filterLabel(value: string): string {
    if (value === 'all') {
      return '全部';
    }
    if (value === 'free') {
      return '全天空闲';
    }
    return `${value} 节`;
  }

  private filters(): string[] {
    return ['all', 'free', '1-4', '5-8', '9-12'];
  }

  private async refresh(): Promise<void> {
    if (this.selectedBuildingCode.length === 0) {
      this.toast('请先选择校区和教学楼');
      return;
    }
    await this.loadRoomsAndOccupancy();
  }

  private async openRoom(room: ClassroomRoom): Promise<void> {
    this.selectedRoom = room;
    this.sheetMode = 'room';
    this.showPicker = true;
    this.roomWeek = [];
    if (this.client === null || this.selectedBuildingCode.length === 0) {
      return;
    }
    this.roomLoading = true;
    try {
      const result: RoomDaySchedule[] = [];
      for (const day of this.days) {
        const all: ClassroomOccupancy[] =
          await this.client.fetchOccupancy(this.selectedBuildingCode, day.iso);
        await JwcwxCache.saveOccupancy(this.context(), this.selectedBuildingCode, day.iso, all);
        result.push({
          iso: day.iso,
          weekday: day.weekday,
          label: day.label,
          items: all.filter((item: ClassroomOccupancy) =>
            item.roomCode === room.code && item.periods.length > 0)
        });
      }
      this.roomWeek = result;
    } catch (error) {
      this.error = error instanceof Error ? error.message : '读取教室周课表失败';
    } finally {
      this.roomLoading = false;
    }
  }

  private periodStart(period: number): string {
    return period >= 1 && period <= DEFAULT_PERIOD_TIMES.length
      ? DEFAULT_PERIOD_TIMES[period - 1][0] : '';
  }

  @Builder
  roomBlock(item: ClassroomOccupancy) {
    Column({ space: 1 }) {
      Text(this.occupancyTag(item))
        .fontSize(8)
        .fontColor('#2B4C6F')
        .padding({ left: 3, right: 3, top: 1, bottom: 1 })
        .backgroundColor('#FFFFFF99')
        .borderRadius(4)
      Text(this.roomOccupancyTitle(item))
        .fontSize(8)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1D2B3A')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (item.teacher.length > 0) {
        Text(item.teacher)
          .fontSize(7)
          .fontColor('#3A4A5A')
          .maxLines(1)
      }
    }
    .width('100%')
    .height((Math.max(...item.periods) - Math.min(...item.periods) + 1) * 24 - 2)
    .padding(3)
    .backgroundColor(this.occupancyColor(item))
    .borderRadius(6)
    .alignItems(HorizontalAlign.Start)
    .position({ x: 0, y: (Math.min(...item.periods) - 1) * 24 + 1 })
  }

  @Builder
  roomDayColumn(day: RoomDaySchedule) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        ForEach(PERIODS, (period: number) => {
          Column()
            .width('100%')
            .height(24)
            .border({ width: { bottom: 0.5 }, color: '#22000000' })
        }, (period: number) => `grid-${day.iso}-${period}`)
      }
      .width('100%')
      .height(12 * 24)

      ForEach(day.items, (item: ClassroomOccupancy) => {
        this.roomBlock(item)
      }, (item: ClassroomOccupancy) => `${day.iso}-${item.id}`)
    }
    .layoutWeight(1)
    .height(12 * 24)
    .margin({ left: 2 })
    .border({ width: { right: 0.5 }, color: '#22000000' })
  }

  @Builder
  roomSheet() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(`${this.selectedRoom?.name ?? '教室'} · ${this.selectedRoom?.capacity ?? 0}座`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TEXT_PRIMARY)
            .maxLines(1)
          Text(`第 ${this.currentWeek} 周 · ${this.days.length > 0 ? this.days[0].label : ''}–${this.days.length > 0 ? this.days[6].label : ''}`)
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_SECONDARY)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(17)
            .fontColor([AppTheme.TEXT_SECONDARY])
        }
        .width(36)
        .height(36)
        .backgroundColor(AppTheme.CARD_BG)
        .onClick(() => { this.showPicker = false; })
      }
      .width('100%')

      if (this.roomLoading) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18)
          Text('正在读取周课表…')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_SECONDARY)
        }
        .height(50)
      } else {
        if (this.roomWeek.length > 0 && this.roomWeek.every((day: RoomDaySchedule) => day.items.length === 0)) {
          Text('本周全天空闲')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_SECONDARY)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 4, bottom: 2 })
        }
        Row() {
          Column().width(34)
          ForEach(this.roomWeek, (day: RoomDaySchedule) => {
            Column({ space: 1 }) {
              Text(`周${day.weekday}`)
                .fontSize(9)
                .fontColor(AppTheme.TEXT_SECONDARY)
              Text(day.label)
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.TEXT_PRIMARY)
            }
            .layoutWeight(1)
            .height(38)
            .justifyContent(FlexAlign.Center)
          }, (day: RoomDaySchedule) => `head-${day.iso}`)
        }
        .width('100%')

        Scroll() {
          Row() {
            Column() {
              ForEach(PERIODS, (period: number) => {
                Column({ space: 0 }) {
                  Text(`${period}`)
                    .fontSize(9)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(AppTheme.TEXT_PRIMARY)
                  Text(this.periodStart(period))
                    .fontSize(7)
                    .fontColor(AppTheme.TEXT_TERTIARY)
                }
                .width('100%')
                .height(24)
                .justifyContent(FlexAlign.Center)
              }, (period: number) => `time-${period}`)
            }
            .width(34)
            .height(12 * 24)

            ForEach(this.roomWeek, (day: RoomDaySchedule) => {
              this.roomDayColumn(day)
            }, (day: RoomDaySchedule) => `col-${day.iso}`)
          }
          .width('100%')
          .height(12 * 24)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .scrollable(ScrollDirection.Vertical)

        Row({ space: 12 }) {
          Row({ space: 4 }) {
            Column().width(8).height(8).borderRadius(4).backgroundColor('#E4E7EC')
            Text('空闲').fontSize(9).fontColor(AppTheme.TEXT_TERTIARY)
          }
          Row({ space: 4 }) {
            Column().width(8).height(8).borderRadius(4).backgroundColor('#BBD8FF')
            Text('课程').fontSize(9).fontColor(AppTheme.TEXT_TERTIARY)
          }
          Row({ space: 4 }) {
            Column().width(8).height(8).borderRadius(4).backgroundColor('#FFC1C1')
            Text('个人占用').fontSize(9).fontColor(AppTheme.TEXT_TERTIARY)
          }
        }
        .width('100%')
        .padding({ top: 4 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppTheme.PAGE_PADDING, right: AppTheme.PAGE_PADDING, top: 18, bottom: 12 })
  }

  @Builder
  modalSheet() {
    if (this.sheetMode === 'room') {
      this.roomSheet()
    } else {
      this.pickerSheet()
    }
  }

  @Builder
  dayTab(day: DayOption) {
    Column({ space: 3 }) {
      Text(`周${day.weekday}`)
        .fontSize(AppTheme.FONT_TINY)
        .fontColor(day.iso === this.selectedDate ? AppTheme.ON_BRAND : AppTheme.TEXT_SECONDARY)
      Text(day.label)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontWeight(day.iso === this.selectedDate ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(day.iso === this.selectedDate ? AppTheme.ON_BRAND : AppTheme.TEXT_PRIMARY)
      Column()
        .width(4)
        .height(4)
        .borderRadius(2)
        .backgroundColor(day.iso === this.selectedDate ? AppTheme.ON_BRAND : Color.Transparent)
    }
    .layoutWeight(1)
    .height(58)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(day.iso === this.selectedDate ? AppTheme.BRAND : Color.Transparent)
    .borderRadius(14)
    .onClick(async () => {
      if (day.iso === this.selectedDate) {
        return;
      }
      this.selectedDate = day.iso;
      await this.loadOccupancy();
    })
  }

  @Builder
  periodBars(room: ClassroomRoom) {
    Row({ space: 3 }) {
      ForEach(PERIODS, (period: number) => {
        Column()
          .layoutWeight(1)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.occupancyColor(this.occupancyAt(room, period)))
      }, (period: number) => `bar-${room.code}-${period}`)
    }
    .width('100%')
  }

  @Builder
  roomCard(room: ClassroomRoom) {
    Column({ space: 9 }) {
      Row() {
        Column({ space: 3 }) {
          Text(room.name)
            .fontSize(AppTheme.FONT_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_PRIMARY)
          Text(this.occupiedText(room))
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column({ space: 3 }) {
          Text(room.capacity > 0 ? `${room.capacity} 座` : '容量未知')
            .fontSize(AppTheme.FONT_TINY)
            .fontColor(AppTheme.TEXT_SECONDARY)
          Text(`${this.freePeriods(room).length}/12 空闲`)
            .fontSize(AppTheme.FONT_TINY)
            .fontColor('#2F6B4F')
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor('#DFF0E4')
            .borderRadius(9)
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')

      this.periodBars(room)

      Row() {
        Text(`空闲 ${this.periodText(this.freePeriods(room))} 节`)
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_SECONDARY)
        Blank()
        Text(this.selectedFilter === 'all' ? '共 12 节' : this.filterLabel(this.selectedFilter))
          .fontSize(AppTheme.FONT_TINY)
          .fontColor(AppTheme.TEXT_TERTIARY)
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.CARD_BG)
    .borderRadius(AppTheme.CARD_RADIUS)
    .onClick(() => this.openRoom(room))
  }

  @Builder
  buildingChip(building: ClassroomBuilding) {
    Column({ space: 3 }) {
      Text(building.name)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontWeight(building.code === this.selectedBuildingCode ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(building.code === this.selectedBuildingCode ? AppTheme.BRAND : AppTheme.TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(building.campusName)
        .fontSize(9)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .maxLines(1)
    }
    .alignItems(HorizontalAlign.Start)
    .width('48%')
    .height(58)
    .margin({ bottom: 9 })
    .padding({ left: 12, right: 10, top: 8, bottom: 8 })
    .backgroundColor(building.code === this.selectedBuildingCode ? '#EAF1FF' : AppTheme.CARD_BG)
    .borderRadius(14)
    .onClick(async () => {
      this.showPicker = false;
      this.selectedCampusCode = building.campusCode;
      this.selectedBuildingCode = building.code;
      this.rooms = [];
      this.occupancies = [];
      await this.loadRoomsAndOccupancy();
    })
  }

  @Builder
  pickerSheet() {
    Column({ space: 10 }) {
      Row() {
        Text('选择教学楼')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT_PRIMARY)
        Blank()
        Text('关闭')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.BRAND)
          .onClick(() => { this.showPicker = false; })
      }
      .width('100%')

      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(16)
          .fontColor([AppTheme.TEXT_TERTIARY])
        TextInput({ placeholder: '搜索教学楼或校区…', text: this.searchText })
          .layoutWeight(1)
          .height(42)
          .fontSize(AppTheme.FONT_BODY)
          .backgroundColor(Color.Transparent)
          .placeholderColor(AppTheme.TEXT_TERTIARY)
          .onChange((value: string) => { this.searchText = value; })
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .backgroundColor(AppTheme.CARD_BG)
      .borderRadius(16)

      Flex({ wrap: FlexWrap.Wrap }) {
        Text('全部校区')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(this.selectedCampusCode.length === 0 ? AppTheme.ON_BRAND : AppTheme.TEXT_SECONDARY)
          .padding({ left: 13, right: 13, top: 7, bottom: 7 })
          .backgroundColor(this.selectedCampusCode.length === 0 ? AppTheme.BRAND : AppTheme.CARD_BG)
          .borderRadius(16)
          .margin({ right: 8, bottom: 8 })
          .onClick(() => { this.selectedCampusCode = ''; })
        ForEach(this.campuses, (campus: CampusOption) => {
          Text(campus.name)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(this.selectedCampusCode === campus.code ? AppTheme.ON_BRAND : AppTheme.TEXT_SECONDARY)
            .padding({ left: 13, right: 13, top: 7, bottom: 7 })
            .backgroundColor(this.selectedCampusCode === campus.code ? AppTheme.BRAND : AppTheme.CARD_BG)
            .borderRadius(16)
            .margin({ right: 8, bottom: 8 })
            .onClick(() => { this.selectedCampusCode = campus.code; })
        }, (campus: CampusOption) => campus.code)
      }
      .width('100%')

      Scroll() {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.sheetBuildings(), (building: ClassroomBuilding) => {
            this.buildingChip(building)
          }, (building: ClassroomBuilding) => building.code)
        }
        .width('100%')
        .padding({ bottom: 20 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppTheme.PAGE_PADDING, right: AppTheme.PAGE_PADDING, top: 18, bottom: 10 })
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: AppTheme.SPACE_MD }) {
          Row({ space: AppTheme.SPACE_SM }) {
            Row({ space: 7 }) {
              SymbolGlyph($r('sys.symbol.square_fill_grid_2x2'))
                .fontSize(17)
                .fontColor([AppTheme.BRAND])
              Text(this.buildingLabel())
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(this.selectedBuildingCode.length > 0 ? AppTheme.TEXT_PRIMARY : AppTheme.TEXT_SECONDARY)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(12)
                .fontColor([AppTheme.TEXT_SECONDARY])
            }
            .layoutWeight(1)
            .height(50)
            .padding({ left: 13, right: 11 })
            .backgroundColor(AppTheme.CARD_BG)
            .borderRadius(18)
            .onClick(() => {
              this.searchText = '';
              this.sheetMode = 'building';
              this.showPicker = true;
            })

            Row({ space: 2 }) {
              Row() {
                SymbolGlyph($r('sys.symbol.chevron_left'))
                  .fontSize(13)
                  .fontColor([this.currentWeek > 1 ? AppTheme.TEXT_SECONDARY : AppTheme.TEXT_TERTIARY])
              }
              .width(28)
              .height(40)
              .justifyContent(FlexAlign.Center)
              .onClick(() => this.shiftWeek(-1))
              Text(`第 ${this.currentWeek} 周`)
                .fontSize(AppTheme.FONT_CAPTION)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.TEXT_PRIMARY)
              Row() {
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(13)
                  .fontColor([AppTheme.TEXT_SECONDARY])
              }
              .width(28)
              .height(40)
              .justifyContent(FlexAlign.Center)
              .onClick(() => this.shiftWeek(1))
            }
            .height(50)
            .padding({ left: 10, right: 10 })
            .backgroundColor(AppTheme.CARD_BG)
            .borderRadius(18)
          }
          .width('100%')

          Row() {
            ForEach(this.days, (day: DayOption) => {
              this.dayTab(day)
            }, (day: DayOption) => day.iso)
          }
          .width('100%')
          .padding(4)
          .backgroundColor(AppTheme.CARD_BG)
          .borderRadius(20)

          Row() {
            Scroll() {
              Row({ space: AppTheme.SPACE_XS }) {
                ForEach(this.filters(), (filter: string) => {
                  Text(this.filterLabel(filter))
                    .fontSize(AppTheme.FONT_CAPTION)
                    .fontColor(this.selectedFilter === filter ? AppTheme.ON_BRAND : AppTheme.TEXT_SECONDARY)
                    .padding({ left: 13, right: 13, top: 7, bottom: 7 })
                    .backgroundColor(this.selectedFilter === filter ? AppTheme.BRAND : AppTheme.CARD_BG)
                    .borderRadius(16)
                    .onClick(() => { this.selectedFilter = filter; })
                }, (filter: string) => filter)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }
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

          if (this.needLogin) {
            Column({ space: 10 }) {
              Text('需要登录教务')
                .fontSize(AppTheme.FONT_TITLE)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.TEXT_PRIMARY)
                .width('100%')
              Text('空教室查询使用教务统一认证。请先在“教务同步”完成一次登录。')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
                .width('100%')
                .lineHeight(18)
              Button('去教务同步登录')
                .width('100%')
                .height(44)
                .borderRadius(22)
                .onClick(() => this.onOpenSync())
            }
            .width('100%')
            .padding(16)
            .backgroundColor(AppTheme.CARD_BG)
            .borderRadius(20)
          } else if (this.selectedBuildingCode.length === 0) {
            Column({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.square_fill_grid_2x2'))
                .fontSize(32)
                .fontColor([AppTheme.TEXT_TERTIARY])
              Text(this.buildings.length === 0 && !this.loading ? '教学楼数据加载失败' : '选择教学楼后查询')
                .fontSize(AppTheme.FONT_TITLE)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.TEXT_PRIMARY)
              Text(this.buildings.length === 0 && !this.loading ? '请检查校园网/VPN 后重试' :
                '可搜索校区和教学楼，查看当天占用与空闲节次')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
              if (this.buildings.length === 0 && !this.loading) {
                Button('重新加载')
                  .height(38)
                  .borderRadius(19)
                  .fontSize(AppTheme.FONT_CAPTION)
                  .onClick(() => this.load())
              }
            }
            .width('100%')
            .padding(28)
            .backgroundColor(AppTheme.CARD_BG)
            .borderRadius(20)
          } else {
            Row({ space: 8 }) {
              Text(`${this.selectedDateLabel()} · ${this.visibleRooms().length} 间可选`)
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
              Blank()
              Text(this.offline ? '本地缓存' : `共 ${this.rooms.length} 间`)
                .fontSize(AppTheme.FONT_TINY)
                .fontColor(this.offline ? '#B26A00' : AppTheme.TEXT_TERTIARY)
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                  .fontSize(13)
                  .fontColor([AppTheme.BRAND])
                Text(this.loading ? '查询中' : '刷新')
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(AppTheme.BRAND)
              }
              .padding({ left: 8, right: 8, top: 5, bottom: 5 })
              .backgroundColor(AppTheme.CARD_BG)
              .borderRadius(14)
              .onClick(() => this.refresh())
            }
            .width('100%')

            if (!this.loading && this.visibleRooms().length === 0 && this.rooms.length > 0) {
              Text('当前筛选没有符合条件的教室')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
                .width('100%')
                .padding(20)
                .backgroundColor(AppTheme.CARD_BG)
                .borderRadius(18)
            }

            ForEach(this.visibleRooms(), (room: ClassroomRoom) => {
              this.roomCard(room)
            }, (room: ClassroomRoom) => room.code)

            Row({ space: 12 }) {
              Row({ space: 5 }) {
                Column().width(10).height(10).borderRadius(5).backgroundColor('#E4E7EC')
                Text('空闲')
                  .fontSize(AppTheme.FONT_TINY)
                  .fontColor(AppTheme.TEXT_TERTIARY)
              }
              Row({ space: 5 }) {
                Column().width(10).height(10).borderRadius(5).backgroundColor('#BBD8FF')
                Text('课程')
                  .fontSize(AppTheme.FONT_TINY)
                  .fontColor(AppTheme.TEXT_TERTIARY)
              }
              Row({ space: 5 }) {
                Column().width(10).height(10).borderRadius(5).backgroundColor('#FFC1C1')
                Text('个人占用')
                  .fontSize(AppTheme.FONT_TINY)
                  .fontColor(AppTheme.TEXT_TERTIARY)
              }
              Blank()
            }
            .width('100%')
            .padding({ top: 4 })
          }
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
    .titleBar(immersiveTitleBar($r('app.string.classroom_title')))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(AppTheme.BG)
    .bindSheet(this.showPicker, this.modalSheet(), {
      height: this.sheetMode === 'room' ? 480 : 640,
      dragBar: true,
      showClose: false,
      backgroundColor: AppTheme.BG,
      onDisappear: () => { this.showPicker = false; }
    })
  }
}
