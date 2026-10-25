//
//  LocalVideoPlaybackState.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** The playback state of a local video file stream. */
export enum LocalVideoPlaybackState {

  /** The local video file is playing. */
  PLAYING = 'playing',

  /** The local video file is paused. */
  PAUSE = 'pause',

  /** The non-looping local video file has ended. */
  ENDED = 'ended'
}

/**
 * A local video file playback state handler.
 *
 * @param state The lifecycle or playback state to deliver.
 */
export type LocalVideoPlaybackStateListener = (
  state: LocalVideoPlaybackState
) => void;
