import { SELECTION_QUEUE_REVISION_KEY } from '../services/selection/SelectionModels';

/** 队列变更计数：页面用它触发重新读取，避免直接共享可变数组。 */
export class SelectionState {
  static queueRevision(): number {
    const value: number | undefined = AppStorage.get<number>(SELECTION_QUEUE_REVISION_KEY);
    return value === undefined ? 0 : value;
  }

  static bumpQueue(): void {
    AppStorage.setOrCreate(SELECTION_QUEUE_REVISION_KEY, SelectionState.queueRevision() + 1);
  }
}
