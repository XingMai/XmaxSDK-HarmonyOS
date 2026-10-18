//
//  RtcVideoConverter.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

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

/** 在 SDK 视频帧、显示配置与 RTC 平台类型之间转换。 */
export class RtcVideoConverter {
  /**
   * 在 RTC 回调返回前复制 I420 有效像素，不让接入方依赖 RTC 缓冲区生命周期。
   *
   * @param frame 需要处理或交付的媒体帧。
   * @returns 可交付给接入方的视频帧。
   */
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

  /**
   * 将 SDK 编码偏好映射为 RTC 编码偏好。
   *
   * @param preference 视频编码的优先策略。
   * @returns RTC 可接受的编码优先策略。
   */
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

  /**
   * 将 SDK 视频帧与可选 SEI 数据封装为 RTC 外部视频帧。
   *
   * @param frame 需要处理或交付的媒体帧。
   * @param seiData 随视频帧提交的可选 SEI 数据。
   * @returns 可提交到 RTC 的视频帧数据。
   */
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

  /**
   * 根据摄像头位置选择本地视频的镜像策略。
   *
   * @param position 使用的摄像头位置。
   * @returns 对应摄像头位置的 RTC 镜像模式。
   */
  static convertMirrorType(position: CameraPosition): MirrorType {
    return position === CameraPosition.FRONT ?
      MirrorType.kMirrorTypeRenderAndEncoder : MirrorType.kMirrorTypeNone;
  }

  /**
   * 创建绑定指定视图并使用指定显示模式的 RTC 画布。
   *
   * @param viewId 用于原生视频显示的视图标识。
   * @param contentMode 媒体在视口中的完整显示或裁剪填充方式。
   * @returns RTC 视频画布配置。
   */
  static createCanvas(
    viewId: string,
    contentMode: VideoContentMode
  ): VideoCanvas {
    const renderMode: RenderMode = contentMode === VideoContentMode.FIT ?
      RenderMode.kRenderModeFit : RenderMode.kRenderModeHidden;

    return RtcVideoConverter.canvas(viewId, renderMode);
  }

  /**
   * 创建用于解绑视频显示的空 RTC 画布。
   *
   * @returns 无可见视图绑定的画布配置。
   */
  static createHiddenCanvas(): VideoCanvas {
    return RtcVideoConverter.canvas('', RenderMode.kRenderModeHidden);
  }

  /**
   * 按像素格式提取 RTC 需要的各图像平面数据。
   *
   * @param pixelFormat 媒体数据的像素排列格式。
   * @param firstPlane 第一图像平面，通常为亮度或打包像素数据。
   * @param secondPlane 第二图像平面，通常为色度数据。
   * @param thirdPlane 第三图像平面，供三平面像素格式使用。
   * @returns 按 RTC 平面顺序排列的数据；不需要的平面为空。
   */
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

  /**
   * 按像素格式提取 RTC 需要的各图像平面行跨度。
   *
   * @param pixelFormat 媒体数据的像素排列格式。
   * @param firstPlane 第一图像平面，通常为亮度或打包像素数据。
   * @param secondPlane 第二图像平面，通常为色度数据。
   * @param thirdPlane 第三图像平面，供三平面像素格式使用。
   * @returns 与 RTC 数据平面一一对应的行跨度。
   */
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

  /**
   * 将 SDK 像素格式映射为 RTC 支持的像素格式。
   *
   * @param pixelFormat 媒体数据的像素排列格式。
   * @returns 对应的 RTC 像素格式。
   */
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

  /**
   * 将 SDK 视频旋转方向映射为 RTC 旋转枚举。
   *
   * @param rotation 视频画面需要应用的旋转方向。
   * @returns 对应的 RTC 旋转方向。
   */
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

  /**
   * 从平面缓冲区的有效区间创建字节视图。
   *
   * @param plane 待校验或读取的图像平面。
   * @returns 覆盖指定偏移与长度的平面数据视图。
   */
  private static planeData(plane: VideoFramePlane): Uint8Array {
    return new Uint8Array(
      plane.data,
      plane.byteOffset,
      plane.byteLength
    );
  }

  /**
   * 取得必须存在的图像平面；缺失时抛出配置错误。
   *
   * @param plane 待校验或读取的图像平面。
   * @param index 图像平面或档位的索引。
   * @returns 已确认存在的图像平面。
   */
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

  /**
   * 创建指定渲染模式与视图标识的 RTC 画布。
   *
   * @param viewId 用于原生视频显示的视图标识。
   * @param renderMode RTC 画布的显示填充模式。
   * @returns 可供 RTC 绑定的视频画布。
   */
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
