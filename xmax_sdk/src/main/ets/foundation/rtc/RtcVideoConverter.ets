import { RealtimeVideoFrame } from '../../service/realtime/RealtimeVideoFrame';
import {
  IVideoFrame,
  MirrorType,
  RenderMode,
  VideoBufferType,
  VideoEncodePreference,
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

import { VideoEncoderPreference } from './VideoEncodingConfiguration';

const EMPTY_SEI_DATA: Uint8Array = new Uint8Array();

export class RtcVideoConverter {
  /** 在 RTC 回调返回前复制 I420 有效像素，不让接入方依赖 RTC 缓冲区生命周期。 */
  static copyRemoteFrame(frame: IVideoFrame): RealtimeVideoFrame {
    if (frame.pixel_format !== RtcVideoPixelFormat.kVideoPixelFormatI420 ||
      !Number.isSafeInteger(frame.width) || !Number.isSafeInteger(frame.height) ||
      frame.width <= 0 || frame.height <= 0 || frame.width > 32768 || frame.height > 32768 ||
      !Number.isFinite(frame.timestamp_us) || frame.timestamp_us < 0 || frame.number_of_planes !== 3) {
      throw new XmaxError(XmaxErrorCode.RTC_ERROR, 'Invalid remote I420 video frame');
    }
    let rotation: VideoRotation;
    switch (frame.rotation) {
      case 0: rotation = VideoRotation.ROTATION_0; break;
      case 90: rotation = VideoRotation.ROTATION_90; break;
      case 180: rotation = VideoRotation.ROTATION_180; break;
      case 270: rotation = VideoRotation.ROTATION_270; break;
      default:
        throw new XmaxError(XmaxErrorCode.RTC_ERROR, 'Unsupported remote video rotation');
    }
    const planes: VideoFramePlane[] = [];
    for (let index: number = 0; index < 3; index++) {
      const width: number = index === 0 ? frame.width : Math.ceil(frame.width / 2);
      const height: number = index === 0 ? frame.height : Math.ceil(frame.height / 2);
      const source: ArrayBuffer | undefined = frame.plane_data[index];
      const stride: number | undefined = frame.plane_stride[index];
      if (source === undefined || stride === undefined || !Number.isSafeInteger(stride) ||
        stride < width || source.byteLength < (height - 1) * stride + width) {
        throw new XmaxError(XmaxErrorCode.RTC_ERROR, 'Invalid remote video plane or stride');
      }
      const data: ArrayBuffer = new ArrayBuffer(width * height);
      const pixels: Uint8Array = new Uint8Array(data);
      const input: Uint8Array = new Uint8Array(source);
      for (let row: number = 0; row < height; row++) {
        pixels.set(input.subarray(row * stride, row * stride + width), row * width);
      }
      planes.push(new VideoFramePlane(data, width));
    }
    return new RealtimeVideoFrame(frame.width, frame.height, VideoPixelFormat.I420,
      planes, frame.timestamp_us, rotation);
  }

  static convertEncoderPreference(preference: VideoEncoderPreference): VideoEncodePreference {
    switch (preference) {
      case VideoEncoderPreference.AUTO:
        return VideoEncodePreference.kVideoEncodePreferenceBalance;
      case VideoEncoderPreference.MAINTAIN_FRAMERATE:
        return VideoEncodePreference.kVideoEncodePreferenceFramerate;
      case VideoEncoderPreference.MAINTAIN_QUALITY:
        return VideoEncodePreference.kVideoEncodePreferenceQuality;
      default:
        throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION, 'Unsupported video encoder preference');
    }
  }

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
