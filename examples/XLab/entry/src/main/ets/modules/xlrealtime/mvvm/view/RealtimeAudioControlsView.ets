import { RealtimeViewState } from '../model/RealtimeViewState';

@Component
export struct RealtimeAudioControlsView {
  @ObjectLink state: RealtimeViewState;
  onLocalVolumeChanged: (volume: number) => void = (_volume: number): void => {};
  onRemoteVolumeChanged: (volume: number) => void = (_volume: number): void => {};
  onMuteChanged: (muted: boolean) => void = (_muted: boolean): void => {};
  @State private isVolumeMenuVisible: boolean = false;

  @Builder
  private volumeSlider(title: string, isLocal: boolean, onChange: (volume: number) => void) {
    Column() {
      Row() {
        Text(title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.realtime_volume_label'))
        Blank()
        Text(`${Math.round((isLocal ? this.state.localAudioVolume : this.state.remoteAudioVolume) * 100)}%`)
          .fontSize(12)
          .fontColor($r('app.color.realtime_volume_secondary_label'))
      }
      .width('100%')

      Slider({
        value: (isLocal ? this.state.localAudioVolume : this.state.remoteAudioVolume) * 100,
        min: 0, max: 100, step: 1
      })
        .width('100%')
        .height(32)
        .blockColor('#FFFFFF')
        .selectedColor($r('app.color.realtime_volume_tint'))
        .trackColor($r('app.color.realtime_volume_track'))
        .accessibilityText(title)
        .accessibilityDescription(
          `${Math.round((isLocal ? this.state.localAudioVolume : this.state.remoteAudioVolume) * 100)}%`)
        .onChange((value: number): void => onChange(value / 100))
    }
    .width('100%')
  }

  @Builder
  private volumeMenu() {
    Column({ space: 8 }) {
      this.volumeSlider('本地音量', true, this.onLocalVolumeChanged)
      this.volumeSlider('远端音量', false, this.onRemoteVolumeChanged)
    }
    .width(260)
    .height(144)
    .padding(14)
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor($r('app.color.realtime_volume_background'))
    .borderRadius(14)
  }

  @Builder
  private actionContent(isVolumeButton: boolean) {
    Column({ space: 4 }) {
      SymbolGlyph(isVolumeButton ? $r('sys.symbol.slider_horizontal_2') :
        (this.state.isAudioMuted ? $r('sys.symbol.speaker_slash_fill') : $r('sys.symbol.speaker_wave_2_fill')))
        .fontSize(20)
        .fontColor(['#FFFFFF'])
      Text(isVolumeButton ? '音量' : (this.state.isAudioMuted ? '静音' : '声音'))
        .fontSize(10)
        .lineHeight(12)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
    }
    .height(36)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Row() {
      Button({ type: ButtonType.Normal }) {
        this.actionContent(true)
      }
      .width(44)
      .height(58)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText('调整音量')
      .onClick((): void => {
        this.isVolumeMenuVisible = !this.isVolumeMenuVisible;
      })
      .bindPopup(this.isVolumeMenuVisible, {
        builder: this.volumeMenu,
        placement: Placement.Bottom,
        popupColor: $r('app.color.realtime_volume_background'),
        backgroundBlurStyle: BlurStyle.NONE,
        radius: 14,
        onStateChange: (event): void => {
          this.isVolumeMenuVisible = event.isVisible;
        }
      })

      Button({ type: ButtonType.Normal }) {
        this.actionContent(false)
      }
      .width(44)
      .height(58)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText(this.state.isAudioMuted ? '开启声音' : '关闭声音')
      .accessibilityDescription(this.state.isAudioMuted ? '已静音' : '已开启')
      .onClick((): void => {
        this.onMuteChanged(!this.state.isAudioMuted);
      })
    }
    .width(88)
    .height(58)
  }
}
