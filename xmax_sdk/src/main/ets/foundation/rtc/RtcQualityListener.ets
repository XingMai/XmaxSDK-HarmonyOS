export enum RtcQualityLevel {
  UNKNOWN,
  EXCELLENT,
  GOOD,
  POOR,
  BAD,
  VERY_BAD,
  DOWN
}

export interface RtcQualityListener {
  /**
   * 处理实时网络质量变化。
   *
   * @param uplink 本地发送上行质量。
   * @param downlink 远端视频接收下行质量。
   */
  onNetworkQuality(
    uplink: RtcQualityLevel,
    downlink: RtcQualityLevel
  ): void;

  /**
   * 处理实时性能受限或恢复事件。
   *
   * @param limited 是否处于性能受限状态。
   * @param suggestedWidth 建议的视频输入宽度。
   * @param suggestedHeight 建议的视频输入高度。
   * @param suggestedFrameRate 建议的视频输入帧率。
   */
  onPerformanceAlarm(
    limited: boolean,
    suggestedWidth: number,
    suggestedHeight: number,
    suggestedFrameRate: number
  ): void;
}
