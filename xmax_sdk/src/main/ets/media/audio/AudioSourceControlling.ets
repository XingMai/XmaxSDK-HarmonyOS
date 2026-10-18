//
//  AudioSourceControlling.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { MediaTimeline } from '../MediaTimeline';

/** 定义本地文件音频轨输出能力。 */
export interface AudioSourceControlling {

  /**
   * 配置待输出的本地媒体文件。
   *
   * @param filePath 本地媒体文件路径。
   * @param loop 是否在文件结束后循环播放。
   * @returns 无返回值。
   */
  configure(filePath: string, loop?: boolean): void;

  /**
   * 按共享时间轴开始输出音频帧。
   *
   * @param timeline 音视频共享播放时间轴。
   * @returns 无返回值。
   */
  start(timeline: MediaTimeline): void;

  /**
   * 暂停当前解码器，保留媒体位置与资源。
   *
   * @returns 无返回值。
   */
  pause(): void;

  /**
   * 使用统一的暂停时长恢复当前解码器。
   *
   * @param pausedDurationUs 本次暂停持续时间，单位微秒。
   * @returns 无返回值。
   */
  resume(pausedDurationUs: number): void;

  /**
   * 停止输出并释放音频解码资源。
   *
   * @returns 无返回值。
   */
  stop(): void;
}
