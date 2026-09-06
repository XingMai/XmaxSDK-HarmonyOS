import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { DefaultTrajectoryEffectRenderer } from '../trajectory/DefaultTrajectoryEffectRenderer';
import { TrajectoryEffectRendering } from '../trajectory/TrajectoryEffectRendering';
import { XmaxVideoView } from './XmaxVideoView';

/** 持续显示本地预览，在远端首帧渲染后渐入生成画面。 */
@Component
export struct XmaxRealtimeVideoView {
  @Prop localTrack?: RealtimeVideoTrack = undefined;
  @Prop @Watch('onRemoteTrackChanged') remoteTrack?: RealtimeVideoTrack = undefined;
  @Prop contentMode: VideoContentMode = VideoContentMode.FILL;
  @Prop isInteractionEnabled: boolean = true;

  /** 初始化时设置自定义轨迹效果渲染器。 */
  trajectoryRenderer: TrajectoryEffectRendering = new DefaultTrajectoryEffectRenderer();

  @State private remoteReady: boolean = false;
  @State private remoteViewKey: number = 0;
  private currentRemoteTrack?: RealtimeVideoTrack;

  aboutToAppear(): void {
    this.currentRemoteTrack = this.remoteTrack === undefined ? undefined :
      RealtimeVideoTrack.resolve(this.remoteTrack);
  }

  private onRemoteTrackChanged(): void {
    const track: RealtimeVideoTrack | undefined = this.remoteTrack === undefined ? undefined :
      RealtimeVideoTrack.resolve(this.remoteTrack);
    if (track === this.currentRemoteTrack) {
      return;
    }
    this.currentRemoteTrack = track;
    this.remoteReady = false;
    this.remoteViewKey++;
  }

  private onRemoteVideoReady(key: number, ready: boolean): void {
    if (key === this.remoteViewKey && this.remoteTrack !== undefined) {
      this.remoteReady = ready;
    }
  }

  build() {
    Stack() {
      XmaxVideoView({
        track: this.localTrack,
        contentMode: this.contentMode,
        isInteractionEnabled: false
      })
        .width('100%')
        .height('100%')

      ForEach(this.remoteTrack === undefined ? [] : [this.remoteViewKey], (key: number) => {
        XmaxVideoView({
          track: this.remoteTrack,
          contentMode: this.contentMode,
          isInteractionEnabled: this.isInteractionEnabled && this.remoteReady,
          trajectoryRenderer: this.trajectoryRenderer,
          onVideoReadyChanged: (ready: boolean): void => {
            this.onRemoteVideoReady(key, ready);
          }
        })
          .width('100%')
          .height('100%')
          // 保持 Surface 布局与渲染，收到 RTC 首帧事件后再显示。
          .opacity(this.remoteReady ? 1 : 0)
          .animation({ duration: this.remoteReady ? 300 : 0, curve: Curve.EaseInOut })
          .hitTestBehavior(this.remoteReady ? HitTestMode.Default : HitTestMode.None)
      }, (key: number): string => key.toString())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .clip(true)
  }
}
