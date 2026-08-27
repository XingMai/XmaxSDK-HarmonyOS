import {
  XmaxError,
  XmaxErrorCode
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { BufferVideoFrame } from '../../foundation/media/video/BufferVideoFrame';
import {
  VideoFileDecodedFrame,
  VideoFileFrameDecoder,
  VideoFileFrameDecoderListener
} from '../../foundation/media/video/VideoFileFrameDecoder';
import { VideoFormat } from '../../foundation/media/video/VideoFormat';
import { VideoFramePlane } from '../../foundation/media/video/VideoFramePlane';
import { VideoRotation } from '../../foundation/media/video/VideoRotation';
import { MediaTimeline } from '../MediaTimeline';
import {
  VideoSourceControlling,
  VideoSourceErrorListener,
  VideoSourceFrameListener
} from './VideoSourceControlling';

const FRAME_INTERVAL_TOLERANCE: number = 0.75;

/** 解码本地媒体文件中的视频轨，并按共享时间轴循环输出采样后的视频帧。 */
export class VideoSourceController implements VideoSourceControlling {

  // 视频帧监听器
  private readonly frameListener: VideoSourceFrameListener;
  private readonly errorListener: VideoSourceErrorListener;

  // 视频文件资源
  private decoder: VideoFileFrameDecoder | null = null;
  private filePath: string = '';
  private sourceRotation: VideoRotation = VideoRotation.ROTATION_0;

  // 播放进度
  private timeline: MediaTimeline | null = null;
  private loopIndex: number = 0;
  private frameIntervalUs: number = 0;
  private lastSourceTimestampUs: number = -1;

  /**
   * 创建视频源 Controller。
   *
   * @param frameListener 视频帧输出监听器。
   * @param errorListener 视频源错误监听器。
   */
  constructor(
    frameListener: VideoSourceFrameListener,
    errorListener: VideoSourceErrorListener
  ) {
    this.frameListener = frameListener;
    this.errorListener = errorListener;
  }

  /**
   * 配置待解码的视频文件、旋转方向和目标帧率。
   *
   * @param filePath 本地视频文件路径。
   * @param rotation 视频源旋转方向。
   * @param frameRate 目标视频帧率。
   * @returns 无返回值。
   */
  configure(
    filePath: string,
    rotation: VideoRotation,
    frameRate: number
  ): void {
    if (this.decoder !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Stop the current video source before configuring another file'
      );
    }

    this.filePath = filePath;
    this.sourceRotation = rotation;
    this.frameIntervalUs = 1000000 / frameRate;
    this.resetFrameSampling();
  }

  /**
   * 按共享时间轴开始输出视频帧。
   *
   * @param timeline 音视频共享播放时间轴。
   * @returns 无返回值。
   */
  start(timeline: MediaTimeline): void {
    if (this.filePath.length === 0) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Configure the local media file before starting the video source'
      );
    }
    if (this.decoder !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Local video source is already active'
      );
    }

    this.timeline = timeline;
    this.loopIndex = 0;
    this.resetFrameSampling();
    this.decoder = this.createDecoder();
  }

  /**
   * 释放当前解码器并按新时间轴重新输出视频帧。
   *
   * @param timeline 新的音视频共享播放时间轴。
   * @returns 无返回值。
   */
  restart(timeline: MediaTimeline): void {
    this.releaseDecoder();
    this.timeline = timeline;
    this.loopIndex = 0;
    this.resetFrameSampling();
    this.decoder = this.createDecoder();
  }

  /**
   * 停止输出并清理视频文件状态。
   *
   * @returns 无返回值。
   */
  stop(): void {
    this.releaseDecoder();
    this.filePath = '';
    this.sourceRotation = VideoRotation.ROTATION_0;
    this.timeline = null;
    this.loopIndex = 0;
    this.frameIntervalUs = 0;
    this.resetFrameSampling();
  }

  /**
   * 根据当前文件和时间轴创建视频帧解码器。
   *
   * @returns 已启动的视频帧解码器。
   */
  private createDecoder(): VideoFileFrameDecoder {
    const timeline: MediaTimeline | null = this.timeline;
    if (timeline === null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Video source timeline is unavailable'
      );
    }

    const loopIndex: number = this.loopIndex;
    return new VideoFileFrameDecoder(
      this.filePath,
      this.sourceRotation,
      new VideoSourceDecoderListener(
        (frame: VideoFileDecodedFrame): void => {
          this.handleFrame(frame);
        },
        (): void => {
          this.handleEndOfStream(loopIndex);
        },
        (message: string): void => {
          this.errorListener(message);
        }
      ),
      timeline.playbackAnchorForLoop(loopIndex),
      timeline.mediaStartUs
    );
  }

  /**
   * 将已转正且符合采样节奏的解码帧封装为统一视频帧并输出。
   *
   * @param frame 视频文件解码帧。
   * @returns 无返回值。
   */
  private handleFrame(frame: VideoFileDecodedFrame): void {
    if (!this.shouldOutputFrame(frame)) {
      return;
    }

    const lumaLength: number = frame.width * frame.height;
    const videoFrame = new BufferVideoFrame(
      new VideoFormat(
        frame.width,
        frame.height,
        frame.pixelFormat
      ),
      frame.timestampUs,
      [
        new VideoFramePlane(
          frame.data,
          frame.stride,
          0,
          lumaLength
        ),
        new VideoFramePlane(
          frame.data,
          frame.stride,
          lumaLength,
          lumaLength / 2
        )
      ],
      VideoRotation.ROTATION_0
    );

    try {
      this.frameListener(videoFrame);
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      this.errorListener(reason);
    }
  }

  /**
   * 在当前循环结束后创建下一轮视频解码器。
   *
   * @param loopIndex 结束解码器所属的循环序号。
   * @returns 无返回值。
   */
  private handleEndOfStream(loopIndex: number): void {
    const endedDecoder: VideoFileFrameDecoder | null = this.decoder;
    if (endedDecoder === null || loopIndex !== this.loopIndex) {
      return;
    }

    setTimeout((): void => {
      if (this.decoder !== endedDecoder || loopIndex !== this.loopIndex) {
        return;
      }

      this.decoder = null;
      this.releaseDecoderInstance(endedDecoder);
      this.loopIndex++;
      this.resetFrameSampling();

      try {
        this.decoder = this.createDecoder();
      } catch (error) {
        const reason: string = error instanceof Error ? error.message : String(error);
        this.errorListener(reason);
      }
    }, 0);
  }

  /**
   * 根据播放进度和目标帧率判断解码帧是否需要输出。
   *
   * @param frame 视频文件解码帧。
   * @returns 当前解码帧需要输出时返回 true，否则返回 false。
   */
  private shouldOutputFrame(frame: VideoFileDecodedFrame): boolean {
    if (MediaTimeline.currentTimestampUs() - frame.timestampUs >
      this.frameIntervalUs) {
      return false;
    }

    const lastTimestampUs: number = this.lastSourceTimestampUs;
    if (lastTimestampUs >= 0 && frame.timestampUs - lastTimestampUs <
      this.frameIntervalUs * FRAME_INTERVAL_TOLERANCE) {
      return false;
    }

    this.lastSourceTimestampUs = frame.timestampUs;
    return true;
  }

  /**
   * 重置视频帧采样进度。
   *
   * @returns 无返回值。
   */
  private resetFrameSampling(): void {
    this.lastSourceTimestampUs = -1;
  }

  /**
   * 释放当前视频解码器。
   *
   * @returns 无返回值。
   */
  private releaseDecoder(): void {
    const decoder: VideoFileFrameDecoder | null = this.decoder;
    this.decoder = null;

    if (decoder !== null) {
      this.releaseDecoderInstance(decoder);
    }
  }

  /**
   * 安全释放指定视频解码器并记录释放错误。
   *
   * @param decoder 待释放的视频解码器。
   * @returns 无返回值。
   */
  private releaseDecoderInstance(decoder: VideoFileFrameDecoder): void {
    try {
      decoder.release();
    } catch (error) {
      const reason: string = error instanceof Error ? error.message : String(error);
      XmaxLogger.error(
        `释放本地视频解码器失败\n└─ 原因：${reason}`,
        'Video'
      );
    }
  }
}

/** 将视频解码器事件转发给视频源 Controller。 */
class VideoSourceDecoderListener implements VideoFileFrameDecoderListener {

  private readonly frameHandler: (frame: VideoFileDecodedFrame) => void;
  private readonly endHandler: () => void;
  private readonly errorHandler: (message: string) => void;

  /**
   * 创建视频解码事件转发器。
   *
   * @param frameHandler 视频帧处理方法。
   * @param endHandler 视频流结束处理方法。
   * @param errorHandler 视频解码错误处理方法。
   */
  constructor(
    frameHandler: (frame: VideoFileDecodedFrame) => void,
    endHandler: () => void,
    errorHandler: (message: string) => void
  ) {
    this.frameHandler = frameHandler;
    this.endHandler = endHandler;
    this.errorHandler = errorHandler;
  }

  /**
   * 转发解码后的视频帧。
   *
   * @param frame 视频文件解码帧。
   * @returns 无返回值。
   */
  onFrame(frame: VideoFileDecodedFrame): void {
    this.frameHandler(frame);
  }

  /**
   * 转发视频流结束事件。
   *
   * @returns 无返回值。
   */
  onEndOfStream(): void {
    this.endHandler();
  }

  /**
   * 转发视频解码错误。
   *
   * @param message 错误信息。
   * @returns 无返回值。
   */
  onError(message: string): void {
    this.errorHandler(message);
  }
}
