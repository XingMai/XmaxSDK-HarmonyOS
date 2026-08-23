import { vibrator } from '@kit.SensorServiceKit';
import { RealtimeReferenceItemState, RealtimeReferenceListState } from '../model/RealtimeViewState';
import { RealtimeReferenceCell } from './RealtimeReferenceCell';

@Component
export struct RealtimeReferenceListView {
  @ObjectLink listState: RealtimeReferenceListState;
  onSelectReference: (item: RealtimeReferenceItemState) => void =
    (_item: RealtimeReferenceItemState): void => {};
  onAddReference: (categoryId: string) => void = (_categoryId: string): void => {};
  private readonly scroller: Scroller = new Scroller();

  private selectReference(item: RealtimeReferenceItemState): void {
    if (item.reference.isAddAction) {
      this.onAddReference(item.reference.categoryId);
      return;
    }
    this.onSelectReference(item);
    this.playSelectionFeedback();

    if (!item.isSelected) {
      return;
    }
    const index: number = this.listState.items.indexOf(item);
    if (index >= 0) {
      this.scroller.scrollToIndex(index, true, ScrollAlign.CENTER);
    }
  }

  private playSelectionFeedback(): void {
    vibrator.startVibration(
      {
        type: 'preset',
        effectId: vibrator.HapticFeedback.EFFECT_SOFT,
        count: 1
      },
      { usage: 'touch' }
    ).catch((_error: Object): void => {});
  }

  build() {
    List({ space: 6, scroller: this.scroller }) {
      ForEach(this.listState.items, (item: RealtimeReferenceItemState) => {
        ListItem() {
          RealtimeReferenceCell({
            item: item,
            reference: item.reference
          })
        }
        .onClick(() => {
          this.selectReference(item);
        })
      }, (item: RealtimeReferenceItemState): string => item.reference.id)
    }
    .listDirection(Axis.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .contentStartOffset(14)
    .contentEndOffset(14)
    .width('100%')
    .height(48)
  }
}
