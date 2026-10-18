//
//  index.d.ts
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/**
 * 接收原生视频解码帧、文件结束通知或解码错误。
 *
 * @param data 当前帧的有效媒体数据。
 * @param width 画面宽度，单位像素。
 * @param height 画面高度，单位像素。
 * @param stride 相邻图像行之间的字节跨度。
 * @param timestampUs 媒体帧时间戳，单位微秒。
 * @param endOfStream 是否已到达文件末尾。
 * @param error 当前操作失败或终止的原因。
 * @returns 无返回值。
 */
type NativeVideoFileFrameListener = (
  data: ArrayBuffer | undefined,
  width: number,
  height: number,
  stride: number,
  timestampUs: number,
  endOfStream: boolean,
  error?: string
) => void;

/** 控制原生视频文件解码的暂停、恢复和异步资源释放。 */
export interface NativeVideoFileDecoder {
  /**
   * 暂停媒体时间轴上的连续解码输出。
   *
   * @returns 无返回值。
   */
  pause(): void;

  /**
   * 恢复解码并将播放锚点向后平移本次暂停时长。
   *
   * @param pausedDurationUs 本次暂停持续时间，单位微秒。
   * @returns 无返回值。
   */
  resume(pausedDurationUs: number): void;

  /**
   * 停止连续解码并释放文件、解封装器与解码器资源。
   *
   * @returns 操作完成时兑现的 Promise。
   */
  release(): Promise<void>;
}

/**
 * 接收原生音频解码后的 PCM 数据、文件结束通知或错误。
 *
 * @param data 当前帧的有效媒体数据。
 * @param timestampUs 媒体帧时间戳，单位微秒。
 * @param endOfStream 是否已到达文件末尾。
 * @param error 当前操作失败或终止的原因。
 * @returns 无返回值。
 */
type NativeAudioFileFrameListener = (
  data: ArrayBuffer | undefined,
  timestampUs: number,
  endOfStream: boolean,
  error?: string
) => void;

/** 控制原生音频文件解码的暂停、恢复和资源释放。 */
export interface NativeAudioFileDecoder {
  /**
   * 暂停媒体时间轴上的连续解码输出。
   *
   * @returns 无返回值。
   */
  pause(): void;

  /**
   * 恢复解码并将播放锚点向后平移本次暂停时长。
   *
   * @param pausedDurationUs 本次暂停持续时间，单位微秒。
   * @returns 无返回值。
   */
  resume(pausedDurationUs: number): void;

  /**
   * 停止连续解码并释放文件、解封装器与解码器资源。
   *
   * @returns 无返回值。
   */
  release(): void;
}

/**
 * 接收原生摄像头转换后的 NV12 数据或处理错误。
 *
 * @param data 当前帧的有效媒体数据。
 * @param width 画面宽度，单位像素。
 * @param height 画面高度，单位像素。
 * @param timestampUs 媒体帧时间戳，单位微秒。
 * @param error 当前操作失败或终止的原因。
 * @returns 无返回值。
 */
type NativeCameraFrameListener = (
  data: ArrayBuffer | undefined,
  width: number,
  height: number,
  timestampUs: number,
  error?: string
) => void;

/** 接收 CameraKit 原始帧，并按目标尺寸、方向和帧率输出。 */
export interface NativeFrameReceiver {
  /**
   * 返回可绑定到 CameraKit 输出的 Native 接收 Surface。
   *
   * @returns 可传给 CameraKit 输出创建接口的原生 Surface 标识。
   */
  getSurfaceId(): string;

  /**
   * 配置目标尺寸、旋转角度和帧率。
   *
   * @param width 画面宽度，单位像素。
   * @param height 画面高度，单位像素。
   * @param rotation 视频画面需要应用的旋转方向。
   * @param frameRate 目标视频帧率，单位 fps。
   * @param captureFrameRate 采集帧率，单位 fps。
   * @returns 无返回值。
   */
  configure(
    width: number,
    height: number,
    rotation: number,
    frameRate: number,
    captureFrameRate: number
  ): void;

  /**
   * 停止帧回调并释放 Native 图像接收资源。
   *
   * @returns 无返回值。
   */
  release(): void;
}

/** 提供 SDK 原生摄像头接收及音视频文件解码的 ArkTS 桥接入口。 */
interface XmaxVideoNative {
  /**
   * 创建 CameraKit 原始帧接收器。
   *
   * @param sourceWidth 原始摄像头帧宽度，单位像素。
   * @param sourceHeight 原始摄像头帧高度，单位像素。
   * @param listener 接收媒体帧与解码状态的监听器。
   * @returns 可绑定到 CameraKit 输出的原生接收器。
   */
  createFrameReceiver(
    sourceWidth: number,
    sourceHeight: number,
    listener: NativeCameraFrameListener
  ): NativeFrameReceiver;

  /**
   * 后台初始化系统视频解码器；就绪后处于暂停状态，调用 resume 开始输出。
   *
   * @param fd 已打开的本地文件描述符。
   * @param size 本地媒体文件的字节长度。
   * @param playbackAnchorUs 媒体起点对应的单调播放时间，单位微秒。
   * @param mediaStartUs 媒体时间轴的起始时间，单位微秒。
   * @param rotation 视频画面需要应用的旋转方向。
   * @param outputWidth 解码输出宽度，单位像素。
   * @param outputHeight 解码输出高度，单位像素。
   * @param frameIntervalUs 视频帧输出间隔，单位微秒。
   * @param cycleDurationUs 单轮媒体播放时长，单位微秒。
   * @param listener 接收媒体帧与解码状态的监听器。
   * @returns 异步初始化完成的原生视频解码器；初始暂停，需调用 resume 开始输出。
   */
  createVideoFileDecoder(
    fd: number,
    size: number,
    playbackAnchorUs: number,
    mediaStartUs: number,
    rotation: number,
    outputWidth: number,
    outputHeight: number,
    frameIntervalUs: number,
    cycleDurationUs: number,
    listener: NativeVideoFileFrameListener
  ): Promise<NativeVideoFileDecoder>;

  /**
   * 使用系统音频解码器连续输出 48 kHz 单声道 PCM 帧。
   *
   * @param fd 已打开的本地文件描述符。
   * @param size 本地媒体文件的字节长度。
   * @param playbackAnchorUs 媒体起点对应的单调播放时间，单位微秒。
   * @param mediaStartUs 媒体时间轴的起始时间，单位微秒。
   * @param cycleDurationUs 单轮媒体播放时长，单位微秒。
   * @param listener 接收媒体帧与解码状态的监听器。
   * @returns 开始按播放时间轴输出 PCM 帧的原生音频解码器。
   */
  createAudioFileDecoder(
    fd: number,
    size: number,
    playbackAnchorUs: number,
    mediaStartUs: number,
    cycleDurationUs: number,
    listener: NativeAudioFileFrameListener
  ): NativeAudioFileDecoder;
}

declare const xmaxVideoNative: XmaxVideoNative;
export default xmaxVideoNative;
