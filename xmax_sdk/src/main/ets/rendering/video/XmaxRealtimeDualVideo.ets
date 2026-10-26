//
//  XmaxRealtimeDualVideo.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeInteractionListener } from '../../service/realtime/RealtimeInteraction';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { DefaultTrajectoryEffectRenderer } from '../trajectory/DefaultTrajectoryEffectRenderer';
import { TrajectoryEffectRendering } from '../trajectory/TrajectoryEffectRendering';
import { XmaxRealtimeVideo } from './XmaxRealtimeVideo';

/**
 * A video container preserving local preview and fading in remote video after its first rendered
 * frame.
 */
@Component
export struct XmaxRealtimeDualVideo {

  /** The local preview track. */
  @Prop localTrack?: RealtimeVideoTrack = undefined;

  /** The remote generation track. */
  @Prop @Watch('onRemoteTrackChanged') remoteTrack?: RealtimeVideoTrack = undefined;

  /** The aspect-fit or aspect-fill display mode. */
  @Prop contentMode: VideoContentMode = VideoContentMode.FILL;

  /** Whether trajectory interaction is enabled. */
  @Prop isInteractionEnabled: boolean = true;

  /** Whether remote interaction continues sending the last point after release; defaults to false. */
  @Prop continuesInteractionAfterRelease: boolean = false;

  /** The valid remote drag lifecycle handler. */
  onInteractionChanged?: RealtimeInteractionListener;

  /** Whether remote video is visible; hiding preserves trajectory drawing and interaction bindings. */
  @Prop isVideoVisible: boolean = true;

  /** The custom trajectory effect renderer configured at initialization. */
  trajectoryRenderer: TrajectoryEffectRendering = new DefaultTrajectoryEffectRenderer();

  /** Whether the current remote view has displayed its first frame. */
  @State private remoteReady: boolean = false;

  /** The revision identifying the current remote view instance. */
  @State private remoteViewKey: number = 0;

  /** The original remote track identity for replacement detection. */
  private currentRemoteTrack?: RealtimeVideoTrack;

  /** Initializes the combined view's remote track and readiness. */
  aboutToAppear(): void {
    this.currentRemoteTrack = this.remoteTrack === undefined ? undefined :
      RealtimeVideoTrack.resolve(this.remoteTrack);
  }

  /** Resets remote display state when the result track changes. */
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

  /**
   * Accepts readiness notifications only from the current remote view.
   *
   * @param key The revision identifying the current remote view.
   * @param ready Whether video is visible.
   */
  private onRemoteVideoReady(
    key: number,
    ready: boolean
  ): void {
    if (key === this.remoteViewKey && this.remoteTrack !== undefined) {
      this.remoteReady = ready;
    }
  }

  /** Builds the video or interaction component tree. */
  build() {
    Stack() {
      XmaxRealtimeVideo({
        track: this.localTrack,
        contentMode: this.contentMode,
        isInteractionEnabled: false
      })
        .width('100%')
        .height('100%')

      ForEach(
        this.remoteTrack === undefined ? [] : [this.remoteViewKey],
        (key: number) => {
        XmaxRealtimeVideo({
          track: this.remoteTrack,
          contentMode: this.contentMode,
          isInteractionEnabled: this.isInteractionEnabled && this.remoteReady,
          continuesInteractionAfterRelease: this.continuesInteractionAfterRelease,
          trajectoryRenderer: this.trajectoryRenderer,
          onInteractionChanged: this.onInteractionChanged,
          isVideoVisible: this.isVideoVisible,
          onVideoReadyChanged: (ready: boolean): void => {
            this.onRemoteVideoReady(
              key,
              ready
            );
          }
        })
          .width('100%')
          .height('100%')
          // Keep the Surface laid out and rendering; reveal it after the RTC first-frame event.
          .opacity(this.remoteReady ? 1 : 0)
          .animation({ duration: this.remoteReady ? 300 : 0, curve: Curve.EaseInOut })
          .hitTestBehavior(this.remoteReady ? HitTestMode.Default : HitTestMode.None)
      },
        (key: number): string => key.toString()
      )
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .clip(true)
  }
}
