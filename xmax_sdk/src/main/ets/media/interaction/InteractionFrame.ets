import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { InteractionPoint } from './InteractionPoint';

export class InteractionFrame {
  readonly points: InteractionPoint[];
  readonly viewportWidth: number;
  readonly viewportHeight: number;
  readonly contentMode: VideoContentMode;

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
