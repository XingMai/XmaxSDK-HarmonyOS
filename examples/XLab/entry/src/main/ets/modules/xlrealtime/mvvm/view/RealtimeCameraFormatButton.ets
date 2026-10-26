import { RealtimeVideoFormat } from '@xmax/sdk';
import { XLabLocalization } from '../../../../localization/XLabLocalization';
import { RealtimeViewState } from '../model/RealtimeViewState';

@Component
export struct RealtimeCameraFormatButton {
  @StorageLink(XLabLocalization.REVISION_KEY) private languageRevision: number = 0;
  @ObjectLink state: RealtimeViewState;
  @Prop isCameraSwitching: boolean = false;
  onSelect: (format: RealtimeVideoFormat) => void = (_format: RealtimeVideoFormat): void => {};

  private ratioLabel(format: RealtimeVideoFormat): string {
    let divisor: number = format.width;
    let remainder: number = format.height;
    while (remainder !== 0) {
      const next: number = divisor % remainder;
      divisor = remainder;
      remainder = next;
    }
    return `${format.width / divisor}:${format.height / divisor}`;
  }

  @Builder
  private formatMenu() {
    Menu() {
      ForEach(this.state.supportedCameraFormats, (format: RealtimeVideoFormat) => {
        MenuItem({ content: this.ratioLabel(format) })
          .selected(this.state.localVideoTrack?.videoFormat?.width === format.width &&
            this.state.localVideoTrack?.videoFormat?.height === format.height)
          .enabled(this.state.canUpdateCameraFormat && !this.isCameraSwitching)
          .onClick((): void => { this.onSelect(format); })
      }, (format: RealtimeVideoFormat): string => `${format.width}x${format.height}`)
    }
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 4 }) {
        Image($r('app.media.realtime_camera_format'))
          .width(20)
          .height(20)

        Text(XLabLocalization.text('camera_format', this.languageRevision))
          .fontSize(10)
          .lineHeight(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .textShadow({ radius: 2, color: '#80000000', offsetX: 0, offsetY: 1 })
      }
      .height(36)
      .justifyContent(FlexAlign.Center)
    }
    .width(58)
    .height(58)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .enabled(this.state.canUpdateCameraFormat && !this.isCameraSwitching)
    .opacity(this.state.canUpdateCameraFormat && !this.isCameraSwitching ? 1 : 0.4)
    .accessibilityText(XLabLocalization.text('camera_format', this.languageRevision))
    .bindMenu(this.formatMenu)
  }
}
