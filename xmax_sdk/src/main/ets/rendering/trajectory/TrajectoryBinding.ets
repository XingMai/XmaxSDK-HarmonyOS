//
//  TrajectoryBinding.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { ImageSize } from '../../service/media/ImageSize';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { InteractionControlling } from '../../media/interaction/InteractionControlling';
import { InteractionFrame } from '../../media/interaction/InteractionFrame';
import { InteractionPoint } from '../../media/interaction/InteractionPoint';

/** A generation interaction binding with the media coordinate baseline used by a view. */
export class TrajectoryBinding {

  /** The controller mapping and sending task interactions. */
  private readonly interactionController: InteractionControlling;

  /** The fixed processed-media dimensions for coordinate mapping. */
  private mediaSize: ImageSize;

  /** Creates a track interaction binding. */
  constructor(
    interactionController: InteractionControlling,
    resolvedMediaSize: ImageSize
  ) {
    this.interactionController = interactionController;
    this.mediaSize = resolvedMediaSize;
  }

  /** The fixed processed-media baseline, independent of remote track or return resolution changes. */
  get resolvedMediaSize(): ImageSize {
    return this.mediaSize;
  }

  /**
   * Updates the coordinate baseline after local media format changes, such as camera rotation.
   *
   * @param size The new processed local media dimensions, in pixels.
   */
  updateResolvedMediaSize(
    size: ImageSize
  ): void {
    this.mediaSize = size;
  }

  /**
   * Maps viewport touches into normalized visible-media coordinates and sends them.
   *
   * @param points The touch points to submit or draw.
   * @param viewportWidth The viewport width, in the same units as touch coordinates.
   * @param viewportHeight The viewport height, in the same units as touch coordinates.
   * @param contentMode The aspect-fit or aspect-fill content mode.
   */
  submit(
    points: InteractionPoint[],
    viewportWidth: number,
    viewportHeight: number,
    contentMode: VideoContentMode
  ): void {
    if (points.length === 0) {
      return;
    }

    this.interactionController.submit(new InteractionFrame(
      points,
      viewportWidth,
      viewportHeight,
      contentMode
    ));
  }
}
