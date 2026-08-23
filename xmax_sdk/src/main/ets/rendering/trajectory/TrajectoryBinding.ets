import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { InteractionControlling } from '../../media/interaction/InteractionControlling';
import { InteractionFrame } from '../../media/interaction/InteractionFrame';
import { InteractionPoint } from '../../media/interaction/InteractionPoint';

export class TrajectoryBinding {
  // 业务层组件
  private readonly interactionController: InteractionControlling;

  constructor(interactionController: InteractionControlling) {
    this.interactionController = interactionController;
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
