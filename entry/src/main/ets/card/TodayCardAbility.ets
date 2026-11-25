import { Want } from '@kit.AbilityKit';
import { formBindingData, formProvider, FormExtensionAbility } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WidgetSnapshot, WidgetSnapshotService } from '../services/widget/WidgetSnapshotService';

const DOMAIN: number = 0x0000;
const TAG: string = 'TodayCardAbility';

function emptySnapshot(): WidgetSnapshot {
  return {
    date: '--',
    weekday: '',
    week: '打开应用后更新',
    courses: [],
    next: { time: '', name: '暂无课程', room: '' },
    weekDays: [],
    updatedAt: ''
  };
}

export default class TodayCardAbility extends FormExtensionAbility {
  private data(): WidgetSnapshot {
    const snapshot: WidgetSnapshot | null = WidgetSnapshotService.read(this.context);
    hilog.info(DOMAIN, TAG, 'snapshot path=%{public}s exists=%{public}d date=%{public}s',
      WidgetSnapshotService.path(this.context), snapshot === null ? 0 : 1,
      snapshot === null ? 'null' : snapshot.date);
    return snapshot ?? emptySnapshot();
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onAddForm');
    return formBindingData.createFormBindingData(this.data());
  }

  onUpdateForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onUpdateForm: %{public}s', formId);
    WidgetSnapshotService.write(this.context).then(() => {
      return formProvider.updateForm(formId, formBindingData.createFormBindingData(this.data()));
    }).catch(() => {});
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onRemoveForm: %{public}s', formId);
  }
}
