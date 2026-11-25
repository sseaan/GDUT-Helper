import { WidgetCourse } from '../../services/widget/WidgetSnapshotService';

@Entry
@Component
struct NextCard {
  @LocalStorageProp('next') next: WidgetCourse = { time: '', name: '暂无课程', room: '' };
  @LocalStorageProp('week') week: string = '';

  build() {
    Column({ space: 4 }) {
      Row() {
        Text('下一节课')
          .fontSize(11)
          .fontColor('#65707D')
        Blank()
        Text(this.week)
          .fontSize(10)
          .fontColor('#0A59F7')
      }
      .width('100%')
      Text(this.next.name)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#182431')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Blank()
      Text(`${this.next.time}${this.next.room.length > 0 ? ' · ' + this.next.room : ''}`)
        .fontSize(11)
        .fontColor('#65707D')
        .maxLines(1)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { source: 'next_card' }
      });
    })
  }
}
