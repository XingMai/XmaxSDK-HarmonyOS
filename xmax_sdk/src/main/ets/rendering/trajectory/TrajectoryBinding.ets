import { ImageSize } from '../../service/media/ImageSize';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { InteractionControlling } from '../../media/interaction/InteractionControlling';
import { InteractionFrame } from '../../media/interaction/InteractionFrame';
import { InteractionPoint } from '../../media/interaction/InteractionPoint';

export class TrajectoryBinding {
  // 业务层组件
  private readonly interactionController: InteractionControlling;

  private mediaSize: ImageSize;

  constructor(interactionController: InteractionControlling, resolvedMediaSize: ImageSize) {
    this.interactionController = interactionController;
    this.mediaSize = resolvedMediaSize;
  }

  /** 固定的处理后媒体基准；远端轨道或回传分辨率变化不改变此值。 */
  get resolvedMediaSize(): ImageSize {
    return this.mediaSize;
  }

  /** 仅在本地媒体规格变化（例如相机转屏）时更新。 */
  updateResolvedMediaSize(size: ImageSize): void {
    this.mediaSize = size;
  }

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
