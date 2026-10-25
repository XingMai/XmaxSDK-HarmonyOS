import { RealtimeConnectionState } from '@xmax/sdk';
import { XLabLocalization } from '../../../../localization/XLabLocalization';
import { RealtimeRecordingState } from '../../recording/RealtimeRecordingState';
import { RealtimeViewState } from '../model/RealtimeViewState';

@Component
export struct RealtimeRecordingButton {
  @StorageLink(XLabLocalization.REVISION_KEY) private languageRevision: number = 0;
  @ObjectLink state: RealtimeViewState;
  onToggle: () => void = (): void => {};

  private label(): string {
    const key: string = this.state.recordingState === RealtimeRecordingState.RECORDING ? 'record_stop' :
      this.state.recordingState === RealtimeRecordingState.SAVING ? 'record_saving' : 'record_start';
    return XLabLocalization.text(key, this.languageRevision);
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 4 }) {
        Stack() {
          if (this.state.recordingState === RealtimeRecordingState.SAVING) {
            LoadingProgress().width(20).height(20).color('#FFB74D')
          } else {
            Circle().width(20).height(20).fill(Color.Transparent).stroke('#FFFFFF').strokeWidth(1.5)
            if (this.state.recordingState === RealtimeRecordingState.RECORDING) {
              Rect().width(10).height(10).radius(2).fill('#FF453A')
            } else {
              Circle().width(12).height(12).fill('#FF453A')
            }
          }
        }
        .width(20)
        .height(20)

        Text(this.label())
          .fontSize(10)
          .lineHeight(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .textShadow({ radius: 2, color: '#80000000', offsetX: 0, offsetY: 1 })
      }
      .height(36)
      .justifyContent(FlexAlign.Center)
    }
    .width(44)
    .height(58)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .enabled(this.state.recordingState === RealtimeRecordingState.RECORDING ||
      (this.state.recordingState === RealtimeRecordingState.IDLE &&
        this.state.connectionState === RealtimeConnectionState.GENERATING))
    .accessibilityText(this.label())
    .onClick(this.onToggle)
  }
}
