//
//  InteractionFrame.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { InteractionPoint } from './InteractionPoint';

/** 携带触点、视口尺寸与显示模式，供交互坐标转换使用。 */
export class InteractionFrame {

  /** 交互触点 */
  readonly points: InteractionPoint[];

  /** 触点视口与显示模式 */
  readonly viewportWidth: number;
  readonly viewportHeight: number;
  readonly contentMode: VideoContentMode;

  /**
   * 创建视口交互帧。
   *
   * @param points 本次提交或绘制的触点集合。
   * @param viewportWidth 交互视口宽度，单位与触点坐标一致。
   * @param viewportHeight 交互视口高度，单位与触点坐标一致。
   * @param contentMode 媒体在视口中的完整显示或裁剪填充方式。
   * @returns 新建的 InteractionFrame 实例。
   */
  constructor(
    points: InteractionPoint[],
    viewportWidth: number,
    viewportHeight: number,
    contentMode: VideoContentMode
  ) {
    this.points = points;
    this.viewportWidth = viewportWidth;
    this.viewportHeight = viewportHeight;
    this.contentMode = contentMode;
  }
}
