//
//  InteractionCoordinateMapper.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { ImageSize } from '../../service/media/ImageSize';
import { RealtimePoint } from '../../service/realtime/RealtimePoint';
import { InteractionPoint } from './InteractionPoint';

/** 处理后媒体在视口中的显示区域，单位与视口一致。 */
export class InteractionMediaFrame {

  /** 媒体显示矩形 */
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;

  /**
   * 创建交互画面矩形。
   *
   * @param x 横坐标。
   * @param y 纵坐标。
   * @param width 画面宽度，单位像素。
   * @param height 画面高度，单位像素。
   * @returns 新建的 InteractionMediaFrame 实例。
   */
  constructor(x: number, y: number, width: number, height: number) {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }
}

/** 以处理后的本地媒体为固定基准，将视口触点转换为 [0, 1] 坐标。 */
export class InteractionCoordinateMapper {
  /**
   * 根据视口、媒体比例和显示模式计算实际画面矩形。
   *
   * @param viewportWidth 交互视口宽度，单位与触点坐标一致。
   * @param viewportHeight 交互视口高度，单位与触点坐标一致。
   * @param resolvedMediaSize 处理后的媒体宽高，作为交互坐标与比例基准。
   * @param contentMode 媒体在视口中的完整显示或裁剪填充方式。
   * @returns 有效画面矩形；尺寸无效时返回 null。
   */
  static displayedFrame(
    viewportWidth: number,
    viewportHeight: number,
    resolvedMediaSize: ImageSize,
    contentMode: VideoContentMode
  ): InteractionMediaFrame | null {
    if (!Number.isFinite(viewportWidth) || !Number.isFinite(viewportHeight) ||
      !Number.isFinite(resolvedMediaSize.width) || !Number.isFinite(resolvedMediaSize.height) ||
      viewportWidth <= 0 || viewportHeight <= 0 ||
      resolvedMediaSize.width < 1 || resolvedMediaSize.height < 1) {
      return null;
    }
    const horizontalScale: number = viewportWidth / resolvedMediaSize.width;
    const verticalScale: number = viewportHeight / resolvedMediaSize.height;
    const scale: number = contentMode === VideoContentMode.FIT ?
      Math.min(horizontalScale, verticalScale) : Math.max(horizontalScale, verticalScale);
    if (!Number.isFinite(scale) || scale <= 0) {
      return null;
    }
    const width: number = resolvedMediaSize.width * scale;
    const height: number = resolvedMediaSize.height * scale;
    return new InteractionMediaFrame((viewportWidth - width) / 2, (viewportHeight - height) / 2, width, height);
  }

  /**
   * Fit 忽略留白区域；Fill 计入裁剪偏移，保留小数精度并限制到 [0, 1]。
   *
   * @param point 视口坐标系中的交互点。
   * @param viewportWidth 交互视口宽度，单位与触点坐标一致。
   * @param viewportHeight 交互视口高度，单位与触点坐标一致。
   * @param resolvedMediaSize 处理后的媒体宽高，作为交互坐标与比例基准。
   * @param contentMode 媒体在视口中的完整显示或裁剪填充方式。
   * @returns 媒体画面内 0～1 的归一化触点；尺寸无效或点位于 FIT 留白区时返回 null。
   */
  static map(
    point: InteractionPoint,
    viewportWidth: number,
    viewportHeight: number,
    resolvedMediaSize: ImageSize,
    contentMode: VideoContentMode
  ): RealtimePoint | null {
    if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) {
      return null;
    }
    const frame: InteractionMediaFrame | null = InteractionCoordinateMapper.displayedFrame(
      viewportWidth, viewportHeight, resolvedMediaSize, contentMode);
    if (frame === null) {
      return null;
    }
    if (contentMode === VideoContentMode.FIT &&
      (point.x < frame.x || point.x > frame.x + frame.width ||
      point.y < frame.y || point.y > frame.y + frame.height)) {
      return null;
    }
    return new RealtimePoint(
      Math.max(0, Math.min(1, (point.x - frame.x) / frame.width)),
      Math.max(0, Math.min(1, (point.y - frame.y) / frame.height))
    );
  }
}
