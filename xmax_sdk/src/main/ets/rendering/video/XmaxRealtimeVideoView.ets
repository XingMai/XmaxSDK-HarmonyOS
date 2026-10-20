//
//  XmaxRealtimeVideoView.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeInteractionListener } from '../../service/realtime/RealtimeInteraction';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { RealtimeVideoTrack } from '../../service/realtime/RealtimeVideoTrack';
import { DefaultTrajectoryEffectRenderer } from '../trajectory/DefaultTrajectoryEffectRenderer';
import { TrajectoryEffectRendering } from '../trajectory/TrajectoryEffectRendering';
import { XmaxVideoView } from './XmaxVideoView';

/** 持续显示本地预览，在远端首帧渲染后渐入生成画面。 */
@Component
export struct XmaxRealtimeVideoView {

  /** 本地预览与远端结果轨道 */
  @Prop localTrack?: RealtimeVideoTrack = undefined;
  @Prop @Watch('onRemoteTrackChanged') remoteTrack?: RealtimeVideoTrack = undefined;

  /** 显示与交互配置 */
  @Prop contentMode: VideoContentMode = VideoContentMode.FILL;
  @Prop isInteractionEnabled: boolean = true;

  /** 有效远端拖拽的生命周期通知。 */
  onInteractionChanged?: RealtimeInteractionListener;
  /** 是否显示远端视频画面；隐藏时保留轨迹绘制和交互绑定。 */
  @Prop isVideoVisible: boolean = true;

  /** 初始化时设置自定义轨迹效果渲染器。 */
  trajectoryRenderer: TrajectoryEffectRendering = new DefaultTrajectoryEffectRenderer();

  /** 远端首帧状态与视图版本 */
  @State private remoteReady: boolean = false;
  @State private remoteViewKey: number = 0;
  private currentRemoteTrack?: RealtimeVideoTrack;

  /**
   * 初始化组合视频视图的远端轨道和就绪状态。
   *
   * @returns 无返回值。
   */
  aboutToAppear(): void {
    this.currentRemoteTrack = this.remoteTrack === undefined ? undefined :
      RealtimeVideoTrack.resolve(this.remoteTrack);
  }

  /**
   * 在生成结果轨道变化时重建远端显示状态。
   *
   * @returns 无返回值。
   */
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
   * 仅接受当前远端视图的画面就绪通知。
   *
   * @param key 数值存储键。
   * @param ready 视频画面是否已经可见。
   * @returns 无返回值。
   */
  private onRemoteVideoReady(key: number, ready: boolean): void {
    if (key === this.remoteViewKey && this.remoteTrack !== undefined) {
      this.remoteReady = ready;
    }
  }

  /**
   * 构建视频或交互视图的 ArkUI 组件树。
   *
   * @returns 由 ArkUI 管理的视图声明，无直接返回值。
   */
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
          onInteractionChanged: this.onInteractionChanged,
          isVideoVisible: this.isVideoVisible,
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
