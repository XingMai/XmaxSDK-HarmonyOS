//
//  InteractionFrame.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { InteractionPoint } from './InteractionPoint';

/** Touch points, viewport dimensions, and content mode for coordinate mapping. */
export class InteractionFrame {

  /** The touch points carried by this interaction frame. */
  readonly points: InteractionPoint[];

  /** The interaction viewport width, in touch-coordinate units. */
  readonly viewportWidth: number;

  /** The interaction viewport height, in touch-coordinate units. */
  readonly viewportHeight: number;

  /** The aspect-fit or aspect-fill display mode. */
  readonly contentMode: VideoContentMode;

  /** Creates a viewport interaction frame. */
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
