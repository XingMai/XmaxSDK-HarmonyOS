//
//  LocalVideoPlaybackState.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** 本地视频文件流的播放状态。 */
export enum LocalVideoPlaybackState {
  PLAYING = 'playing',
  PAUSE = 'pause',
  ENDED = 'ended'
}

/**
 * 本地视频文件流播放状态监听器。
 *
 * @param state 需要通知的业务状态。
 * @returns 无返回值。
 */
export type LocalVideoPlaybackStateListener = (
  state: LocalVideoPlaybackState
) => void;
