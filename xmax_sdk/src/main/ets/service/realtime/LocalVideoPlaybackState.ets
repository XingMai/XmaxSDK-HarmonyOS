/** 本地视频文件流的播放状态。 */
export enum LocalVideoPlaybackState {
  PLAYING = 'playing',
  PAUSE = 'pause'
}

/** 本地视频文件流播放状态监听器。 */
export type LocalVideoPlaybackStateListener = (
  state: LocalVideoPlaybackState
) => void;
