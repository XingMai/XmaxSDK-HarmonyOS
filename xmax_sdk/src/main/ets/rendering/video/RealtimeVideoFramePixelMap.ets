import { image } from '@kit.ImageKit';
import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { VideoFramePlane } from '../../foundation/media/video/VideoFramePlane';
import { VideoPixelFormat } from '../../foundation/media/video/VideoPixelFormat';
import { VideoRotation } from '../../foundation/media/video/VideoRotation';
import { RealtimeVideoFrame } from '../../service/realtime/RealtimeVideoFrame';

/** 将一次性捕获的远端 I420 帧转换成可覆盖在 Surface 上的 RGBA PixelMap。 */
export class RealtimeVideoFramePixelMap {
  static create(frame: RealtimeVideoFrame): Promise<image.PixelMap> {
    if (frame.pixelFormat !== VideoPixelFormat.I420 || frame.planes.length !== 3) {
      return Promise.reject(new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Remote freeze frame must use I420'
      ));
    }

    const sourceWidth: number = frame.width;
    const sourceHeight: number = frame.height;
    const swapsDimensions: boolean = frame.rotation === VideoRotation.ROTATION_90 ||
      frame.rotation === VideoRotation.ROTATION_270;
    const outputWidth: number = swapsDimensions ? sourceHeight : sourceWidth;
    const outputHeight: number = swapsDimensions ? sourceWidth : sourceHeight;
    const output: Uint8Array = new Uint8Array(outputWidth * outputHeight * 4);
    const yPlane: VideoFramePlane = frame.planes[0];
    const uPlane: VideoFramePlane = frame.planes[1];
    const vPlane: VideoFramePlane = frame.planes[2];
    const yData: Uint8Array = RealtimeVideoFramePixelMap.data(yPlane);
    const uData: Uint8Array = RealtimeVideoFramePixelMap.data(uPlane);
    const vData: Uint8Array = RealtimeVideoFramePixelMap.data(vPlane);

    for (let outputY: number = 0; outputY < outputHeight; outputY++) {
      for (let outputX: number = 0; outputX < outputWidth; outputX++) {
        let sourceX: number = outputX;
        let sourceY: number = outputY;
        switch (frame.rotation) {
          case VideoRotation.ROTATION_90:
            sourceX = outputY;
            sourceY = sourceHeight - 1 - outputX;
            break;
          case VideoRotation.ROTATION_180:
            sourceX = sourceWidth - 1 - outputX;
            sourceY = sourceHeight - 1 - outputY;
            break;
          case VideoRotation.ROTATION_270:
            sourceX = sourceWidth - 1 - outputY;
            sourceY = outputX;
            break;
        }
        const yValue: number = yData[sourceY * yPlane.stride + sourceX];
        const chromaX: number = Math.floor(sourceX / 2);
        const chromaY: number = Math.floor(sourceY / 2);
        const uValue: number = uData[chromaY * uPlane.stride + chromaX];
        const vValue: number = vData[chromaY * vPlane.stride + chromaX];
        const c: number = Math.max(yValue - 16, 0);
        const d: number = uValue - 128;
        const e: number = vValue - 128;
        const offset: number = (outputY * outputWidth + outputX) * 4;
        output[offset] = RealtimeVideoFramePixelMap.clamp((298 * c + 409 * e + 128) >> 8);
        output[offset + 1] = RealtimeVideoFramePixelMap.clamp((298 * c - 100 * d - 208 * e + 128) >> 8);
        output[offset + 2] = RealtimeVideoFramePixelMap.clamp((298 * c + 516 * d + 128) >> 8);
        output[offset + 3] = 255;
      }
    }

    return image.createPixelMap(output.buffer, {
      size: {
        width: outputWidth,
        height: outputHeight
      },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: false
    });
  }

  private static data(plane: VideoFramePlane): Uint8Array {
    return new Uint8Array(
      plane.data,
      plane.byteOffset,
      plane.byteLength
    );
  }

  private static clamp(value: number): number {
    return Math.max(0, Math.min(255, value));
  }
}
