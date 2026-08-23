import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { RealtimePoint } from '../../service/realtime/RealtimePoint';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import { InteractionPoint } from './InteractionPoint';

export class InteractionCoordinateMapper {
  static map(
    point: InteractionPoint,
    viewportWidth: number,
    viewportHeight: number,
    videoFormat: RealtimeVideoFormat,
    contentMode: VideoContentMode
  ): RealtimePoint | null {
    if (!Number.isFinite(point.x) || !Number.isFinite(point.y) ||
      viewportWidth <= 0 || viewportHeight <= 0) {
      return null;
    }

    const horizontalScale: number = viewportWidth / videoFormat.width;
    const verticalScale: number = viewportHeight / videoFormat.height;
    const scale: number = contentMode === VideoContentMode.FIT ?
      Math.min(horizontalScale, verticalScale) :
      Math.max(horizontalScale, verticalScale);
    if (scale <= 0) {
      return null;
    }

    const displayedWidth: number = videoFormat.width * scale;
    const displayedHeight: number = videoFormat.height * scale;
    const displayedLeft: number = (viewportWidth - displayedWidth) / 2;
    const displayedTop: number = (viewportHeight - displayedHeight) / 2;
    if (contentMode === VideoContentMode.FIT &&
      (point.x < displayedLeft || point.x > displayedLeft + displayedWidth ||
      point.y < displayedTop || point.y > displayedTop + displayedHeight)) {
      return null;
    }

    const mappedX: number = Math.round((point.x - displayedLeft) / scale);
    const mappedY: number = Math.round((point.y - displayedTop) / scale);

    return new RealtimePoint(
      Math.max(0, Math.min(videoFormat.width - 1, mappedX)),
      Math.max(0, Math.min(videoFormat.height - 1, mappedY))
    );
  }
}
