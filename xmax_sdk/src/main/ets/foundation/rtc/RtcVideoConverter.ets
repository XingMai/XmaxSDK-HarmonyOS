import {
  CameraID,
  MirrorType,
  RenderMode,
  VideoBufferType,
  VideoCanvas,
  VideoFrameData,
  VideoPixelFormat as RtcVideoPixelFormat,
  VideoRotation as RtcVideoRotation
} from '@bytertc/volcenginertc';
import {
  XmaxError,
  XmaxErrorCode
} from '../errors/XmaxError';
import { CameraPosition } from '../media/camera/CameraPosition';
import { VideoContentMode } from '../media/video/VideoContentMode';
import { VideoFrame } from '../media/video/VideoFrame';
import { VideoFramePlane } from '../media/video/VideoFramePlane';
import { VideoPixelFormat } from '../media/video/VideoPixelFormat';
import { VideoRotation } from '../media/video/VideoRotation';

const EMPTY_SEI_DATA: Uint8Array = new Uint8Array();

export class RtcVideoConverter {
  static convertFrame(
    frame: VideoFrame,
    seiData?: Uint8Array
  ): VideoFrameData {
    const firstPlane: VideoFramePlane | undefined = frame.planes[0];
    const secondPlane: VideoFramePlane | undefined = frame.planes[1];
    const thirdPlane: VideoFramePlane | undefined = frame.planes[2];

    return {
      buffer_type: VideoBufferType.kVideoBufferTypeRawMemory,
      pixel_format: RtcVideoConverter.convertPixelFormat(
        frame.format.pixelFormat
      ),
      plane_data: RtcVideoConverter.convertPlaneData(
        frame.format.pixelFormat,
        firstPlane,
        secondPlane,
        thirdPlane
      ),
      plane_stride: RtcVideoConverter.convertPlaneStride(
        frame.format.pixelFormat,
        firstPlane,
        secondPlane,
        thirdPlane
      ),
      sei_data: seiData ?? EMPTY_SEI_DATA,
      width: frame.format.width,
      height: frame.format.height,
      rotation: RtcVideoConverter.convertRotation(frame.rotation),
      timestamp_us: frame.timestampUs
    };
  }

  static convertCameraId(position: CameraPosition): CameraID {
    return position === CameraPosition.FRONT ?
      CameraID.kCameraIDFront : CameraID.kCameraIDBack;
  }

  static convertMirrorType(position: CameraPosition): MirrorType {
    return position === CameraPosition.FRONT ?
      MirrorType.kMirrorTypeRenderAndEncoder : MirrorType.kMirrorTypeNone;
  }

  static createCanvas(
    viewId: string,
    contentMode: VideoContentMode
  ): VideoCanvas {
    const renderMode: RenderMode = contentMode === VideoContentMode.FIT ?
      RenderMode.kRenderModeFit : RenderMode.kRenderModeHidden;

    return RtcVideoConverter.canvas(viewId, renderMode);
  }

  static createHiddenCanvas(): VideoCanvas {
    return RtcVideoConverter.canvas('', RenderMode.kRenderModeHidden);
  }

  private static convertPlaneData(
    pixelFormat: VideoPixelFormat,
    firstPlane?: VideoFramePlane,
    secondPlane?: VideoFramePlane,
    thirdPlane?: VideoFramePlane
  ): [Uint8Array?, Uint8Array?, Uint8Array?] {
    const first: Uint8Array = RtcVideoConverter.planeData(
      RtcVideoConverter.requirePlane(firstPlane, 0)
    );
    if (pixelFormat === VideoPixelFormat.NV12) {
      return [
        first,
        RtcVideoConverter.planeData(
          RtcVideoConverter.requirePlane(secondPlane, 1)
        )
      ];
    }
    if (pixelFormat === VideoPixelFormat.I420) {
      return [
        first,
        RtcVideoConverter.planeData(
          RtcVideoConverter.requirePlane(secondPlane, 1)
        ),
        RtcVideoConverter.planeData(
          RtcVideoConverter.requirePlane(thirdPlane, 2)
        )
      ];
    }

    return [first];
  }

  private static convertPlaneStride(
    pixelFormat: VideoPixelFormat,
    firstPlane?: VideoFramePlane,
    secondPlane?: VideoFramePlane,
    thirdPlane?: VideoFramePlane
  ): [number?, number?, number?] {
    const first: VideoFramePlane = RtcVideoConverter.requirePlane(firstPlane, 0);
    if (pixelFormat === VideoPixelFormat.NV12) {
      return [
        first.stride,
        RtcVideoConverter.requirePlane(secondPlane, 1).stride
      ];
    }
    if (pixelFormat === VideoPixelFormat.I420) {
      return [
        first.stride,
        RtcVideoConverter.requirePlane(secondPlane, 1).stride,
        RtcVideoConverter.requirePlane(thirdPlane, 2).stride
      ];
    }

    return [first.stride];
  }

  private static convertPixelFormat(
    pixelFormat: VideoPixelFormat
  ): RtcVideoPixelFormat {
    switch (pixelFormat) {
      case VideoPixelFormat.I420:
        return RtcVideoPixelFormat.kVideoPixelFormatI420;
      case VideoPixelFormat.NV12:
        return RtcVideoPixelFormat.kVideoPixelFormatNV12;
      case VideoPixelFormat.RGBA:
        return RtcVideoPixelFormat.kVideoPixelFormatRGBA;
      case VideoPixelFormat.BGRA:
        return RtcVideoPixelFormat.kVideoPixelFormatBGRA;
      case VideoPixelFormat.ARGB:
        return RtcVideoPixelFormat.kVideoPixelFormatARGB;
      default:
        throw new XmaxError(
          XmaxErrorCode.RTC_ERROR,
          'Unsupported video pixel format'
        );
    }
  }

  private static convertRotation(rotation: VideoRotation): RtcVideoRotation {
    switch (rotation) {
      case VideoRotation.ROTATION_0:
        return RtcVideoRotation.kVideoRotation0;
      case VideoRotation.ROTATION_90:
        return RtcVideoRotation.kVideoRotation90;
      case VideoRotation.ROTATION_180:
        return RtcVideoRotation.kVideoRotation180;
      case VideoRotation.ROTATION_270:
        return RtcVideoRotation.kVideoRotation270;
      default:
        return RtcVideoRotation.kVideoRotation0;
    }
  }

  private static planeData(plane: VideoFramePlane): Uint8Array {
    return new Uint8Array(
      plane.data,
      plane.byteOffset,
      plane.byteLength
    );
  }

  private static requirePlane(
    plane: VideoFramePlane | undefined,
    index: number
  ): VideoFramePlane {
    if (plane === undefined) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        `Video frame plane ${index} is missing`
      );
    }

    return plane;
  }

  private static canvas(
    viewId: string,
    renderMode: RenderMode
  ): VideoCanvas {
    return {
      view: viewId,
      render_mode: renderMode,
      background_color: 0,
      render_target_type: 0,
      render_rotation: 0
    };
  }
}
