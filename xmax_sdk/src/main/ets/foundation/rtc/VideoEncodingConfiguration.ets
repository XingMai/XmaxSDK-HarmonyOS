//
//  VideoEncodingConfiguration.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** 选择视频编码在流畅度、清晰度与均衡表现之间的优先策略。 */
export enum VideoEncoderPreference {
  AUTO,
  MAINTAIN_FRAMERATE,
  MAINTAIN_QUALITY
}

/** 配置上行编码的尺寸、帧率、码率范围与编码偏好。 */
export class VideoEncodingConfiguration {

  /** 编码画面与帧率 */
  readonly width: number;
  readonly height: number;
  readonly frameRate: number;

  /** 码率边界与编码偏好 */
  readonly minimumBitrate: number;
  readonly maximumBitrate: number;
  readonly encoderPreference: VideoEncoderPreference;

  /**
   * 创建视频编码配置。
   *
   * @param width 画面宽度，单位像素。
   * @param height 画面高度，单位像素。
   * @param frameRate 目标视频帧率，单位 fps。
   * @param minimumBitrate 可选的编码码率下限，单位 kbps。
   * @param maximumBitrate 可选的编码码率上限，单位 kbps。
   * @param encoderPreference 流畅、清晰或均衡的编码优先策略。
   * @returns 新建的 VideoEncodingConfiguration 实例。
   */
  constructor(
    width: number,
    height: number,
    frameRate: number,
    minimumBitrate: number = 0,
    maximumBitrate: number = -1,
    encoderPreference: VideoEncoderPreference = VideoEncoderPreference.AUTO
  ) {
    this.width = width;
    this.height = height;
    this.frameRate = frameRate;
    this.minimumBitrate = minimumBitrate;
    this.maximumBitrate = maximumBitrate;
    this.encoderPreference = encoderPreference;
  }
}
