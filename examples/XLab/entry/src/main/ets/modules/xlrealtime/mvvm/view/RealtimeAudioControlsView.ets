import { XLabLocalization } from '../../../../localization/XLabLocalization';
import { RealtimeViewState } from '../model/RealtimeViewState';

@Component
export struct RealtimeAudioControlsView {
  @StorageLink(XLabLocalization.REVISION_KEY) private languageRevision: number = 0;

  private text(key: string): string {
    return XLabLocalization.text(key, this.languageRevision);
  }

  @ObjectLink state: RealtimeViewState;
  @Prop isCamera: boolean = false;
  onOpenVolumeMenu: () => void = (): void => {};
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
      if (!this.isCamera) {
        this.volumeSlider(this.text('local_volume'), true, this.onLocalVolumeChanged)
      }
      this.volumeSlider(this.text('remote_volume'), false, this.onRemoteVolumeChanged)
    }
    .width(260)
    .height(this.isCamera ? 82 : 144)
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
      Text(isVolumeButton ? this.text('volume') : (this.state.isAudioMuted ? this.text('mute') : this.text('sound')))
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
      .width(this.isCamera ? 58 : 44)
      .height(58)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText(this.text('adjust_volume'))
      .onClick((): void => {
        if (!this.isVolumeMenuVisible) {
          this.onOpenVolumeMenu();
        }
        this.isVolumeMenuVisible = !this.isVolumeMenuVisible;
      })
      .bindPopup(this.isVolumeMenuVisible, {
        builder: this.volumeMenu,
        placement: this.isCamera ? Placement.Left : Placement.Bottom,
        popupColor: $r('app.color.realtime_volume_background'),
        backgroundBlurStyle: BlurStyle.NONE,
        radius: 14,
        onStateChange: (event): void => {
          this.isVolumeMenuVisible = event.isVisible;
        }
      })

      if (!this.isCamera) {
        Button({ type: ButtonType.Normal }) {
          this.actionContent(false)
        }
        .width(44)
        .height(58)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText(this.state.isAudioMuted ? this.text('unmute') : this.text('mute_action'))
        .accessibilityDescription(this.state.isAudioMuted ? this.text('muted') : this.text('sound_on'))
        .onClick((): void => {
          this.onMuteChanged(!this.state.isAudioMuted);
        })
      }
    }
    .width(this.isCamera ? 58 : 88)
    .height(58)
  }
}
