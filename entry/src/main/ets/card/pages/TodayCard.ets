import { WidgetCourse } from '../../services/widget/WidgetSnapshotService';

@Entry
@Component
struct TodayCard {
  @LocalStorageProp('date') date: string = '--';
  @LocalStorageProp('weekday') weekday: string = '';
  @LocalStorageProp('week') week: string = '';
  @LocalStorageProp('courses') courses: WidgetCourse[] = [];
  @LocalStorageProp('next') next: WidgetCourse = { time: '', name: '暂无课程', room: '' };

  build() {
    Column({ space: 4 }) {
      Row() {
        Text('工大助手')
          .fontSize(11)
          .fontColor('#65707D')
        Blank()
        Text(this.weekday)
          .fontSize(11)
          .fontColor('#65707D')
      }
      .width('100%')

      Row() {
        Text(this.date)
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor('#182431')
          .layoutWeight(1)
          .maxLines(1)
        Text(this.week)
          .fontSize(10)
          .fontColor('#0A59F7')
          .maxLines(1)
      }
      .width('100%')

      if (this.courses.length > 0) {
        ForEach(this.courses, (course: WidgetCourse, index: number) => {
          Row({ space: 6 }) {
            Text(course.time)
              .fontSize(10)
              .fontColor('#0A59F7')
              .width(34)
            Text(course.name)
              .fontSize(11)
              .fontColor('#182431')
              .maxLines(1)
              .layoutWeight(1)
            Text(course.room)
              .fontSize(9)
              .fontColor('#65707D')
              .maxLines(1)
          }
          .width('100%')
        }, (course: WidgetCourse, index: number) => `course-${index}`)
      } else {
        Text('今日暂无课程')
          .fontSize(11)
          .fontColor('#65707D')
      }

      Blank()
      Row() {
        Text('接下来')
          .fontSize(9)
          .fontColor('#65707D')
        Text(this.next.name)
          .fontSize(10)
          .fontColor('#182431')
          .maxLines(1)
          .layoutWeight(1)
          .margin({ left: 4 })
        Text(this.next.time)
          .fontSize(9)
          .fontColor('#65707D')
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { source: 'today_card' }
      });
    })
  }
}
