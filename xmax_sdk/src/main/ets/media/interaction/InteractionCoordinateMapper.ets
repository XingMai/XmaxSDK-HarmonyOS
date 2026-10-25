//
//  InteractionCoordinateMapper.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { ImageSize } from '../../service/media/ImageSize';
import { RealtimePoint } from '../../service/realtime/RealtimePoint';
import { InteractionPoint } from './InteractionPoint';

/** The processed media rectangle in viewport units. */
export class InteractionMediaFrame {

  /** The horizontal coordinate. */
  readonly x: number;

  /** The vertical coordinate. */
  readonly y: number;

  /** The displayed media width, in viewport units. */
  readonly width: number;

  /** The displayed media height, in viewport units. */
  readonly height: number;

  /** Creates an interaction media rectangle. */
  constructor(
    x: number,
    y: number,
    width: number,
    height: number
  ) {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }
}

/** Maps viewport touches into normalized coordinates using a fixed processed-media baseline. */
export class InteractionCoordinateMapper {

  /**
   * Resolves the media rectangle from viewport size, media aspect ratio, and content mode.
   *
   * @param viewportWidth The viewport width, in the same units as touch coordinates.
   * @param viewportHeight The viewport height, in the same units as touch coordinates.
   * @param resolvedMediaSize The processed media dimensions defining interaction coordinates and
   * aspect ratio.
   * @param contentMode The aspect-fit or aspect-fill content mode.
   *
   * @returns The displayed media rectangle, or null for invalid dimensions.
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
    return new InteractionMediaFrame(
      (viewportWidth - width) / 2,
      (viewportHeight - height) / 2,
      width,
      height
    );
  }

  /**
   * FIT ignores padding; FILL includes crop offsets. Preserve fractional precision and clamp to [0,
   * 1].
   *
   * @param point The touch point in viewport coordinates.
   * @param viewportWidth The viewport width, in the same units as touch coordinates.
   * @param viewportHeight The viewport height, in the same units as touch coordinates.
   * @param resolvedMediaSize The processed media dimensions defining interaction coordinates and
   * aspect ratio.
   * @param contentMode The aspect-fit or aspect-fill content mode.
   *
   * @returns The normalized media point, or null for invalid dimensions or touches in FIT padding.
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
      viewportWidth,
      viewportHeight,
      resolvedMediaSize,
      contentMode
    );
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
