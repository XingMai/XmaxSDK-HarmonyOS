//
//  VideoStatistics.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** RTC 实际上行视频统计；不可用的指标为 undefined。 */
export class UplinkVideoStatistics {

  /** 实际编码分辨率 */
  /** 实际视频宽度，单位 px。 */
  readonly width?: number;

  /** 实际视频高度，单位 px。 */
  readonly height?: number;

  /** 采集、编码与发送帧率 */
  /** 采集帧率，单位 fps。 */
  readonly captureFrameRate?: number;

  /** 编码帧率，单位 fps。 */
  readonly encodeFrameRate?: number;

  /** 发送帧率，单位 fps。 */
  readonly sendFrameRate?: number;

  /** 上行码率与丢包指标 */
  /** 发送码率，单位 kbps。 */
  readonly bitrateKbps?: number;

  /** 本地到 RTC 服务的丢包率，范围 0～100，保留小数。 */
  readonly packetLossPercent?: number;

  /**
   * 创建上行视频统计快照。
   *
   * @param width 实际视频宽度，单位 px。
   * @param height 实际视频高度，单位 px。
   * @param captureFrameRate 采集帧率，单位 fps。
   * @param encodeFrameRate 编码帧率，单位 fps。
   * @param sendFrameRate 发送帧率，单位 fps。
   * @param bitrateKbps 发送码率，单位 kbps。
   * @param packetLossPercent 本地到 RTC 服务的丢包率，范围 0～100，保留小数。
   * @returns 新建的 UplinkVideoStatistics 实例。
   */
  constructor(
    width?: number,
    height?: number,
    captureFrameRate?: number,
    encodeFrameRate?: number,
    sendFrameRate?: number,
    bitrateKbps?: number,
    packetLossPercent?: number
  ) {
    this.width = width;
    this.height = height;
    this.captureFrameRate = captureFrameRate;
    this.encodeFrameRate = encodeFrameRate;
    this.sendFrameRate = sendFrameRate;
    this.bitrateKbps = bitrateKbps;
    this.packetLossPercent = packetLossPercent;
  }
}

/** RTC 实际下行视频统计；不可用的指标为 undefined。 */
export class DownlinkVideoStatistics {

  /** 远端流身份 */
  /** 当前生成流的远端用户标识。 */
  readonly userId: string;

  /** 实际接收分辨率 */
  /** 实际视频宽度，单位 px。 */
  readonly width?: number;

  /** 实际视频高度，单位 px。 */
  readonly height?: number;

  /** 解码与渲染帧率 */
  /** 解码帧率，单位 fps。 */
  readonly decodeFrameRate?: number;

  /** RTC 渲染帧率，不包含客户端插帧。 */
  readonly renderFrameRate?: number;

  /** 下行码率、丢包与传输延迟 */
  /** 接收码率，单位 kbps。 */
  readonly bitrateKbps?: number;

  /** 丢包率，范围 0～100，保留小数。 */
  readonly packetLossPercent?: number;

  /** RTC 媒体端到端延迟，单位 ms，不代表完整 AI 生成耗时。 */
  readonly endToEndDelayMs?: number;

  /**
   * 创建下行视频统计快照。
   *
   * @param userId 当前生成流的远端用户标识。
   * @param width 实际视频宽度，单位 px。
   * @param height 实际视频高度，单位 px。
   * @param decodeFrameRate 解码帧率，单位 fps。
   * @param renderFrameRate RTC 渲染帧率，不包含客户端插帧。
   * @param bitrateKbps 接收码率，单位 kbps。
   * @param packetLossPercent 丢包率，范围 0～100，保留小数。
   * @param endToEndDelayMs RTC 媒体端到端延迟，单位 ms，不代表完整 AI 生成耗时。
   * @returns 新建的 DownlinkVideoStatistics 实例。
   */
  constructor(
    userId: string,
    width?: number,
    height?: number,
    decodeFrameRate?: number,
    renderFrameRate?: number,
    bitrateKbps?: number,
    packetLossPercent?: number,
    endToEndDelayMs?: number
  ) {
    this.userId = userId;
    this.width = width;
    this.height = height;
    this.decodeFrameRate = decodeFrameRate;
    this.renderFrameRate = renderFrameRate;
    this.bitrateKbps = bitrateKbps;
    this.packetLossPercent = packetLossPercent;
    this.endToEndDelayMs = endToEndDelayMs;
  }
}

/**
 * ArkTS 事件循环中异步交付；停止发布或断开时以 undefined 清空旧统计。
 *
 * @param statistics 统一视频统计；undefined 表示清除旧统计。
 * @returns 无返回值。
 */
export type UplinkVideoStatisticsListener = (statistics: UplinkVideoStatistics | undefined) => void;

/**
 * 仅交付当前匹配生成流的统计；流清理或断开时以 undefined 清空。
 *
 * @param statistics 统一视频统计；undefined 表示清除旧统计。
 * @returns 无返回值。
 */
export type DownlinkVideoStatisticsListener = (statistics: DownlinkVideoStatistics | undefined) => void;
