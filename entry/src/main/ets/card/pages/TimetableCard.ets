import { WidgetCourse, WidgetWeekDay } from '../../services/widget/WidgetSnapshotService';

@Entry
@Component
struct TimetableCard {
  @LocalStorageProp('week') week: string = '';
  @LocalStorageProp('weekDays') weekDays: WidgetWeekDay[] = [];

  build() {
    Column({ space: 2 }) {
      Row() {
        Text('本周课表')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#182431')
        Blank()
        Text(this.week)
          .fontSize(10)
          .fontColor('#0A59F7')
      }
      .width('100%')
      .margin({ bottom: 4 })
      Row({ space: 2 }) {
        ForEach(this.weekDays, (day: WidgetWeekDay) => {
          Column({ space: 3 }) {
            Text(day.label)
              .fontSize(9)
              .fontColor('#65707D')
              .width('100%')
              .textAlign(TextAlign.Center)
            ForEach(day.courses, (course: WidgetCourse, index: number) => {
              Text(course.name)
                .fontSize(8)
                .fontColor('#182431')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .height(34)
                .padding(2)
                .backgroundColor('#F1F3F5')
                .borderRadius(5)
            }, (course: WidgetCourse, index: number) => `${day.label}-${index}`)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }, (day: WidgetWeekDay) => `day-${day.label}`)
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding(10)
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { source: 'timetable_card' }
      });
    })
  }
}
