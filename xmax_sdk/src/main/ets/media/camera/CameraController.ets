import { common } from '@kit.AbilityKit';
import { camera } from '@kit.CameraKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  XmaxError,
  XmaxErrorCode,
  XmaxErrorListener,
  XmaxErrorSeverity
} from '../../foundation/errors/XmaxError';
import { XmaxLogger } from '../../foundation/logging/XmaxLogger';
import { CameraPosition } from '../../foundation/media/camera/CameraPosition';
import { PermissionManager } from '../../foundation/permissions/PermissionManager';
import { PermissionManaging } from '../../foundation/permissions/PermissionManaging';
import { RtcManaging } from '../../foundation/rtc/RtcManaging';
import { VideoContentMode } from '../../foundation/media/video/VideoContentMode';
import { VideoFrame } from '../../foundation/media/video/VideoFrame';
import { CameraPreviewRatio } from '../../rendering/video/CameraPreviewRatio';
import {
  VideoRenderBinding,
  VideoRenderRegistry
} from '../../rendering/video/VideoRenderRegistry';
import { ImageSize } from '../../service/media/ImageSize';
import { MediaService } from '../../service/media/MediaService';
import { MediaServicing } from '../../service/media/MediaServicing';
import { RealtimeCameraPreviewReadyListener } from '../../service/realtime/RealtimeCameraPreview';
import { RealtimeMediaStream } from '../../service/realtime/RealtimeMediaStream';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import {
  RealtimeVideoTrack,
  updateRealtimeVideoTrackPosition
} from '../../service/realtime/RealtimeVideoTrack';
import { StreamControlling } from '../../stream/StreamControlling';
import { StreamId } from '../../stream/StreamId';
import { CameraFrameOutput } from './CameraFrameOutput';

const MAXIMUM_CAPTURE_WIDTH: number = 1920;
const MAXIMUM_CAPTURE_HEIGHT: number = 1440;
const CAMERA_CAPTURE_FRAME_RATE: number = 30;

/** 使用 CameraKit 采集原始视频帧，并交给 RTC 外部视频源。 */
export class CameraController {

  private readonly rtcManager: RtcManaging;
  private readonly permissionManager: PermissionManaging;
  private readonly platformManager: camera.CameraManager;
  private readonly mediaService: MediaServicing;
  private readonly streamController: StreamControlling;
  private readonly errorListener: XmaxErrorListener;

  private cameraInput: camera.CameraInput | null = null;
  private frameOutput: CameraFrameOutput | null = null;
  private captureSession: camera.Session | null = null;

  private activeTrack: RealtimeVideoTrack | null = null;
  private acceptsFrames: boolean = false;
  private captureGeneration: number = 0;

  private previewReadyListener: RealtimeCameraPreviewReadyListener | null = null;
  private hasCapturedFrame: boolean = false;
  private hasBoundPreview: boolean = false;
  private hasReportedPreviewReady: boolean = false;

  constructor(
    context: common.UIAbilityContext,
    rtcManager: RtcManaging,
    streamController: StreamControlling,
    mediaService: MediaServicing = new MediaService(),
    errorListener: XmaxErrorListener = (_error: XmaxError): void => {}
  ) {
    this.rtcManager = rtcManager;
    this.permissionManager = new PermissionManager(context);
    this.platformManager = camera.getCameraManager(context);
    this.mediaService = mediaService;
    this.streamController = streamController;
    this.errorListener = errorListener;
  }

  /** @returns 当前活动的本地相机视频轨道；尚未创建时返回空值。 */
  get currentTrack(): RealtimeVideoTrack | null {
    return this.activeTrack;
  }

  /** 设置摄像头预览就绪监听器。 */
  setPreviewReadyListener(
    listener: RealtimeCameraPreviewReadyListener | null
  ): void {
    this.previewReadyListener = listener;
    this.notifyPreviewReadyIfNeeded();
  }

  /** 创建并启动 CameraKit 本地相机流。 */
  async createLocalCameraStream(
    videoFormat: RealtimeVideoFormat,
    position: CameraPosition
  ): Promise<RealtimeMediaStream> {
    if (this.activeTrack !== null || this.captureSession !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Stop the current local camera stream before creating another one'
      );
    }

    return this.createStream(videoFormat, position);
  }

  /** 停止 CameraKit 采集并释放本地预览绑定。 */
  async stopLocalCameraStream(): Promise<void> {
    const track: RealtimeVideoTrack | null = this.activeTrack;
    this.prepareForStop();
    this.activeTrack = null;

    if (track !== null) {
      VideoRenderRegistry.unregister(track);
    }
    await this.releaseCamera();
  }

  /** 立即阻断相机帧输出并解除本地预览绑定。 */
  prepareForStop(): void {
    this.acceptsFrames = false;
    this.captureGeneration += 1;
    this.resetPreviewReadiness();
    try {
      this.rtcManager.unbindLocalVideo();
    } catch (error) {
      this.logResourceError('解除相机预览绑定', error);
    }
  }

  /** 在前置和后置 CameraKit 摄像头之间切换。 */
  async switchCamera(): Promise<RealtimeMediaStream> {
    const currentTrack: RealtimeVideoTrack | null = this.activeTrack;
    const videoFormat: RealtimeVideoFormat | undefined = currentTrack?.videoFormat;
    const position: CameraPosition | undefined = currentTrack?.position;
    if (currentTrack === null || videoFormat === undefined || position === undefined ||
      this.captureSession === null) {
      throw new XmaxError(XmaxErrorCode.INVALID_CONFIGURATION, 'Local camera preview is not started');
    }

    const nextPosition: CameraPosition = position === CameraPosition.FRONT ?
      CameraPosition.BACK : CameraPosition.FRONT;
    this.acceptsFrames = false;
    this.resetPreviewReadiness();
    await this.releaseCamera();

    try {
      this.rtcManager.configureLocalVideoMirror(nextPosition);
      this.acceptsFrames = true;
      await this.startCamera(videoFormat, nextPosition);
      updateRealtimeVideoTrackPosition(currentTrack, nextPosition);
      return new RealtimeMediaStream(StreamId.LOCAL, currentTrack);
    } catch (error) {
      this.acceptsFrames = false;
      await this.releaseCamera();
      await this.restoreCameraAfterFailedSwitch(videoFormat, position);
      throw XmaxError.from(error);
    }
  }

  /** 完成权限检查、外部视频源配置、CameraKit 启动和预览注册。 */
  private async createStream(
    videoFormat: RealtimeVideoFormat,
    position: CameraPosition
  ): Promise<RealtimeMediaStream> {
    const resolvedFormat: RealtimeVideoFormat = this.resolveVideoFormat(videoFormat);
    const track = new RealtimeVideoTrack('video0', resolvedFormat, position);

    try {
      await this.permissionManager.ensureCameraPermission();
      this.streamController.setVideoEncoderConfig(resolvedFormat);
      this.rtcManager.useExternalVideoSource();
      this.rtcManager.configureLocalVideoMirror(position);
      this.acceptsFrames = true;
      await this.startCamera(resolvedFormat, position);

      VideoRenderRegistry.register(track, new VideoRenderBinding(
        this.rtcManager.renderLibraryName(),
        (viewId: string, contentMode: VideoContentMode): void => {
          this.rtcManager.bindLocalVideo(viewId, contentMode);
          this.hasBoundPreview = true;
          this.notifyPreviewReadyIfNeeded();
        },
        (_viewId: string): void => {
          this.hasBoundPreview = false;
          this.rtcManager.unbindLocalVideo();
        },
        CameraPreviewRatio.FILL
      ));
      this.activeTrack = track;

      return new RealtimeMediaStream(StreamId.LOCAL, track);
    } catch (error) {
      this.acceptsFrames = false;
      VideoRenderRegistry.unregister(track);
      await this.releaseCamera();
      throw XmaxError.from(error);
    }
  }

  /** 创建 CameraKit 会话，并将帧输出绑定到 Native ImageReceiver Surface。 */
  private async startCamera(
    videoFormat: RealtimeVideoFormat,
    position: CameraPosition
  ): Promise<void> {
    if (videoFormat.fps > CAMERA_CAPTURE_FRAME_RATE ||
      Math.floor(videoFormat.fps) !== videoFormat.fps) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Camera frame output configuration is invalid'
      );
    }

    let operation: string = 'Select camera capture profiles';
    try {
      const device: camera.CameraDevice = this.selectCamera(position);
      const profiles: Array<camera.Profile> = this.captureProfiles(device);
      this.resetPreviewReadiness();

      for (const profile of profiles) {
        const dimensions: string = `${profile.size.width} × ${profile.size.height}`;
        operation = `Configure CameraKit session (${dimensions})`;
        const generation: number = ++this.captureGeneration;
        const output: CameraFrameOutput = await this.prepareFrameOutput(device, profile, generation);

        // 帧率能力依赖输出所关联的相机和会话，必须在提交配置后查询。
        operation = `Query CameraKit frame rates (${dimensions})`;
        const ranges: Array<camera.FrameRateRange> = output.output.getSupportedFrameRates();
        if (ranges.length === 0) {
          throw this.cameraError(`${operation}: no frame rate capabilities returned`);
        }
        if (!ranges.some((range: camera.FrameRateRange): boolean =>
          range.min <= CAMERA_CAPTURE_FRAME_RATE && range.max >= CAMERA_CAPTURE_FRAME_RATE)) {
          XmaxLogger.debug(
            `CameraKit 采集规格 ${dimensions} 不支持 30 fps，尝试下一档规格`, 'Camera');
          await this.releaseCamera();
          continue;
        }

        operation = `Set CameraKit frame rate to 30 fps (${dimensions})`;
        output.output.setFrameRate(CAMERA_CAPTURE_FRAME_RATE, CAMERA_CAPTURE_FRAME_RATE);
        operation = `Start CameraKit capture (${dimensions})`;
        await this.captureSession!.start();
        output.configure(videoFormat, CAMERA_CAPTURE_FRAME_RATE);

        XmaxLogger.debug(
          `CameraKit 相机采集已启动\n` +
          `├─ 采集：${dimensions} @ ${CAMERA_CAPTURE_FRAME_RATE} fps\n` +
          `└─ 输出：${videoFormat.width} × ${videoFormat.height} @ ${videoFormat.fps} fps`,
          'Camera'
        );
        return;
      }

      throw this.cameraError('Camera does not support a compatible 4:3 YUV output at 30 fps');
    } catch (error) {
      await this.releaseCamera();
      if (error instanceof XmaxError) {
        throw error;
      }
      const platformError: BusinessError = error as BusinessError;
      const code: string = typeof platformError.code === 'number' ?
        ` (CameraKit code ${platformError.code})` : '';
      const reason: string = platformError.message || String(error);
      throw this.cameraError(`${operation}${code}: ${reason}`);
    }
  }

  /** 将候选输出接入实际会话，使帧率查询具备设备与配置上下文。 */
  private async prepareFrameOutput(
    device: camera.CameraDevice,
    profile: camera.Profile,
    generation: number
  ): Promise<CameraFrameOutput> {
    const input: camera.CameraInput = this.platformManager.createCameraInput(device);
    this.cameraInput = input;
    await input.open();
    const output: CameraFrameOutput = CameraFrameOutput.create(
      this.platformManager,
      profile,
      (frame: VideoFrame): void => this.handleFrame(frame, generation),
      (error: XmaxError): void => this.errorListener(error)
    );
    this.frameOutput = output;
    const session: camera.Session = this.platformManager.createSession<camera.Session>(
      camera.SceneMode.NORMAL_VIDEO
    );
    this.captureSession = session;
    session.beginConfig();
    if (!session.canAddInput(input)) {
      throw this.cameraError('Camera input is not supported by the capture session');
    }
    session.addInput(input);
    if (!session.canAddOutput(output.output)) {
      throw this.cameraError('Camera frame output is not supported by the capture session');
    }
    session.addOutput(output.output);
    await session.commitConfig();
    return output;
  }

  private cameraError(message: string): XmaxError {
    return new XmaxError(XmaxErrorCode.MEDIA_ERROR, message,
      undefined, undefined, XmaxErrorSeverity.RECOVERABLE);
  }

  /** 将相机帧交给统一外部视频推送链路。 */
  private handleFrame(frame: VideoFrame, generation: number): void {
    if (!this.acceptsFrames || generation !== this.captureGeneration) {
      return;
    }

    try {
      this.streamController.pushLocalVideoFrame(frame);
      this.hasCapturedFrame = true;
      this.notifyPreviewReadyIfNeeded();
    } catch (error) {
      this.errorListener(XmaxError.from(error));
    }
  }

  /** 尝试在切换失败后恢复原摄像头。 */
  private async restoreCameraAfterFailedSwitch(
    videoFormat: RealtimeVideoFormat,
    position: CameraPosition
  ): Promise<void> {
    try {
      this.rtcManager.configureLocalVideoMirror(position);
      this.acceptsFrames = true;
      await this.startCamera(videoFormat, position);
    } catch (rollbackError) {
      this.acceptsFrames = false;
      const track: RealtimeVideoTrack | null = this.activeTrack;
      this.activeTrack = null;
      if (track !== null) {
        VideoRenderRegistry.unregister(track);
      }
      await this.releaseCamera();
      XmaxLogger.error(
        `恢复 CameraKit 相机失败\n└─ 原因：${XmaxError.from(rollbackError).message}`,
        'Camera'
      );
    }
  }

  /** 按停止会话、释放输出、关闭输入的顺序释放 CameraKit。 */
  private async releaseCamera(): Promise<void> {
    this.captureGeneration += 1;
    const session: camera.Session | null = this.captureSession;
    const output: CameraFrameOutput | null = this.frameOutput;
    const input: camera.CameraInput | null = this.cameraInput;
    this.captureSession = null;
    this.frameOutput = null;
    this.cameraInput = null;

    if (session !== null) {
      try {
        await session.stop();
      } catch (error) {
        this.logResourceError('停止 CameraKit 会话', error);
      }
      try {
        await session.release();
      } catch (error) {
        this.logResourceError('释放 CameraKit 会话', error);
      }
    }
    if (output !== null) {
      await output.release();
    }
    if (input !== null) {
      try {
        await input.close();
      } catch (error) {
        this.logResourceError('关闭 CameraKit 输入', error);
      }
    }
  }

  /** 选择指定方向的相机设备。 */
  private selectCamera(position: CameraPosition): camera.CameraDevice {
    const platformPosition: camera.CameraPosition = position === CameraPosition.FRONT ?
      camera.CameraPosition.CAMERA_POSITION_FRONT :
      camera.CameraPosition.CAMERA_POSITION_BACK;
    const device: camera.CameraDevice | undefined = this.platformManager
      .getSupportedCameras()
      .find((candidate: camera.CameraDevice): boolean =>
        candidate.cameraPosition === platformPosition);
    if (device === undefined) {
      throw this.cameraError('Requested camera is unavailable');
    }
    return device;
  }

  /** 按面积从 1920×1440 向下排列设备支持的 4:3 YUV 采集规格。 */
  private captureProfiles(device: camera.CameraDevice): Array<camera.Profile> {
    const capability: camera.CameraOutputCapability = this.platformManager
      .getSupportedOutputCapability(device, camera.SceneMode.NORMAL_VIDEO);
    const profiles: Array<camera.Profile> = capability.previewProfiles.filter(
      (profile: camera.Profile): boolean => {
        const width: number = Math.max(profile.size.width, profile.size.height);
        const height: number = Math.min(profile.size.width, profile.size.height);
        return profile.format === camera.CameraFormat.CAMERA_FORMAT_YUV_420_SP &&
          width * 3 === height * 4 &&
          width <= MAXIMUM_CAPTURE_WIDTH && height <= MAXIMUM_CAPTURE_HEIGHT;
      });
    profiles.sort((left: camera.Profile, right: camera.Profile): number =>
      right.size.width * right.size.height - left.size.width * left.size.height);
    if (profiles.length === 0) {
      throw this.cameraError('Camera does not support a compatible 4:3 YUV preview output');
    }
    return profiles;
  }

  /** 校验视频格式并将尺寸调整为模型支持的输入规格。 */
  private resolveVideoFormat(videoFormat: RealtimeVideoFormat): RealtimeVideoFormat {
    videoFormat.validate();
    const targetSize: ImageSize = this.mediaService.resolveModelInputSize(
      new ImageSize(videoFormat.width, videoFormat.height)
    );
    return new RealtimeVideoFormat(targetSize.width, targetSize.height, videoFormat.fps);
  }

  private resetPreviewReadiness(): void {
    this.hasCapturedFrame = false;
    this.hasReportedPreviewReady = false;
  }

  private notifyPreviewReadyIfNeeded(): void {
    const listener: RealtimeCameraPreviewReadyListener | null = this.previewReadyListener;
    if (listener === null || !this.hasCapturedFrame || !this.hasBoundPreview ||
      this.hasReportedPreviewReady) {
      return;
    }
    this.hasReportedPreviewReady = true;
    try {
      listener();
    } catch (error) {
      this.logResourceError('执行摄像头预览就绪监听器', error);
    }
  }

  private logResourceError(action: string, error: Object): void {
    const reason: string = error instanceof Error ? error.message : String(error);
    XmaxLogger.error(`${action}失败\n└─ 原因：${reason}`, 'Camera');
  }
}
