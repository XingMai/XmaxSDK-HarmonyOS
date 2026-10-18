//
//  TrajectoryPoint.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { TrajectoryId } from './TrajectoryId';

/** 同时携带视口坐标、归一化坐标与时间的轨迹采样点。 */
export class TrajectoryPoint {

  /** 触点身份 */
  readonly id: TrajectoryId;

  /** 视口内坐标 */
  readonly x: number;
  readonly y: number;

  /** 媒体内归一化坐标 */
  /** 相对于处理后完整媒体区域的归一化坐标，包含 Fit/Fill 的留白或裁剪偏移。 */
  readonly normalizedX: number;
  readonly normalizedY: number;

  /** 触点采样时间 */
  readonly timestamp: number;

  /**
   * 创建轨迹采样点。
   *
   * @param id 当前资源的唯一标识。
   * @param x 横坐标。
   * @param y 纵坐标。
   * @param normalizedX 相对于处理后完整媒体区域的归一化坐标，包含 Fit/Fill 的留白或裁剪偏移。
   * @param normalizedY 媒体画面内的归一化纵坐标，范围 0～1。
   * @param timestamp 轨迹采样或动画更新时间，单位毫秒。
   * @returns 新建的 TrajectoryPoint 实例。
   */
  constructor(
    id: TrajectoryId,
    x: number,
    y: number,
    normalizedX: number,
    normalizedY: number,
    timestamp: number
  ) {
    this.id = id;
    this.x = x;
    this.y = y;
    this.normalizedX = normalizedX;
    this.normalizedY = normalizedY;
    this.timestamp = timestamp;
  }
}
