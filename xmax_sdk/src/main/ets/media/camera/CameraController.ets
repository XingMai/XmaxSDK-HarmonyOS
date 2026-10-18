//
//  CameraController.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeMediaSource } from '../../service/realtime/RealtimeMediaSource';
import { common } from '@kit.AbilityKit';
import { camera } from '@kit.CameraKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  XmaxError,
  XmaxErrorCode,
  XmaxErrorListener
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
import { CameraPreviewReadyHandler } from './CameraPreviewReadyHandler';
import { RealtimeMediaStream } from '../../service/realtime/RealtimeMediaStream';
import { RealtimeVideoFormat } from '../../service/realtime/RealtimeVideoFormat';
import {
  RealtimeVideoTrack,
  updateRealtimeVideoTrackFormat,
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

  /** 采集平台与业务依赖 */
  private readonly rtcManager: RtcManaging;
  private readonly permissionManager: PermissionManaging;
  private readonly platformManager: camera.CameraManager;
  private readonly mediaService: MediaServicing;
  private readonly streamController: StreamControlling;

  /** 错误与输出格式通知 */
  private readonly errorListener: XmaxErrorListener;
  /**
   * 通知摄像头实际输出的视频格式变化。
   *
   * @param format 需要使用的视频格式。
   * @returns 无返回值。
   */
  private readonly formatListener: (format: RealtimeVideoFormat) => void;

  /** 摄像头会话资源 */
  private cameraInput: camera.CameraInput | null = null;
  private frameOutput: CameraFrameOutput | null = null;
  private captureSession: camera.Session | null = null;

  /** 输出轨道与采集开关 */
  private activeTrack: RealtimeVideoTrack | null = null;
  private acceptsFrames: boolean = false;

  /** 音频与方向配置 */
  private storedUseMicrophone: boolean = false;
  private observeDisplayChange: boolean = true;
  private isMicrophoneCapturing: boolean = false;

  /** 采集回调版本 */
  private captureGeneration: number = 0;

  /** 预览就绪条件与通知 */
  private previewReadyListener: CameraPreviewReadyHandler | null = null;
  private hasCapturedFrame: boolean = false;
  private hasBoundPreview: boolean = false;
  private hasReportedPreviewReady: boolean = false;

  /**
   * 创建摄像头媒体控制器。
   *
   * @param context 平台应用上下文，用于权限、媒体与存储能力。
   * @param rtcManager 提供音视频采集、发布和订阅能力的 RTC 组件。
   * @param streamController 管理传输、房间信令和生成任务的组件。
   * @param mediaService 计算媒体处理、生成与目标尺寸的业务服务。
   * @param errorListener 接收组件错误的监听器。
   * @param formatListener 接收视频格式变化的监听器。
   * @returns 新建的 CameraController 实例。
   */
  constructor(
    context: common.UIAbilityContext,
    rtcManager: RtcManaging,
    streamController: StreamControlling,
    mediaService: MediaServicing = new MediaService(),
    errorListener: XmaxErrorListener = (_error: XmaxError): void => {},
    formatListener: (format: RealtimeVideoFormat) => void = (_format: RealtimeVideoFormat): void => {}
  ) {
    this.rtcManager = rtcManager;
    this.permissionManager = new PermissionManager(context);
    this.platformManager = camera.getCameraManager(context);
    this.mediaService = mediaService;
    this.streamController = streamController;
    this.errorListener = errorListener;
    this.formatListener = formatListener;
  }

  /**
   * 读取当前本地输入提供的视频轨道。
   *
   * @returns 当前轨道；尚无本地媒体时返回 null。
   */
  get currentTrack(): RealtimeVideoTrack | null {
    return this.activeTrack;
  }

  /**
   * 当前相机是否配置为在连接时采集麦克风。
   *
   * @returns 当前摄像头流已启用麦克风时返回 true。
   */
  get useMicrophone(): boolean {
    return this.activeTrack !== null && this.storedUseMicrophone;
  }

  /**
   * 设置摄像头预览就绪监听器。
   *
   * @param listener 接收事件的监听器；可空接口传入 null 时清除监听器。
   * @returns 无返回值。
   */
  setPreviewReadyListener(
    listener: CameraPreviewReadyHandler | null
  ): void {
    this.previewReadyListener = listener;
    this.notifyPreviewReadyIfNeeded();
  }

  /**
   * 创建并启动 CameraKit 本地相机流。
   *
   * @param videoFormat 媒体输出或传输所需的视频规格。
   * @param position 使用的摄像头位置。
   * @param useMicrophone 是否采集并发布麦克风音频。
   * @param observeDisplayChange 是否跟随设备显示方向更新输出格式。
   * @returns 异步返回可用于后续连接、生成或显示的媒体流的 Promise。
   */
  async createLocalCameraStream(
    videoFormat: RealtimeVideoFormat,
    position: CameraPosition,
    useMicrophone: boolean = false,
    observeDisplayChange: boolean = true
  ): Promise<RealtimeMediaStream> {
    if (this.activeTrack !== null || this.captureSession !== null) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        'Stop the current local camera stream before creating another one'
      );
    }

    return this.createStream(videoFormat, position, useMicrophone, observeDisplayChange);
  }

  /**
   * 在窗口转屏和建连前同步 Native 方向，不等待下一帧才更新轨道规格。
   *
   * @returns 无返回值。
   */
  updateOrientation(): void {
    const track = this.activeTrack;
    const format = track?.videoFormat;
    const output = this.frameOutput;
    if (track !== null && format !== undefined && output !== null) {
      output.configure(format, CAMERA_CAPTURE_FRAME_RATE, this.observeDisplayChange);
      this.synchronizeVideoFormat(track, output.currentVideoFormat ?? format);
    }
  }

  /**
   * 在连接时启动 RTC 内部麦克风采集，不开启本地回放。
   *
   * @returns 无返回值。
   */
  startMicrophoneCapture(): void {
    if (!this.useMicrophone || this.isMicrophoneCapturing) {
      return;
    }
    // 即使启动失败，也由连接清理停止可能已经打开的设备。
    this.isMicrophoneCapturing = true;
    this.rtcManager.startMicrophoneCapture();
  }

  /**
   * 停止采集并保留重连配置；停止失败时保留标记，允许清理重试。
   *
   * @returns 无返回值。
   */
  stopMicrophoneCapture(): void {
    if (!this.isMicrophoneCapturing) {
      return;
    }
    this.rtcManager.stopMicrophoneCapture();
    this.isMicrophoneCapturing = false;
  }

  /**
   * 停止 CameraKit 采集并释放本地预览绑定。
   *
   * @returns 操作完成时兑现的 Promise。
   */
  async stopLocalCameraStream(): Promise<void> {
    const track: RealtimeVideoTrack | null = this.activeTrack;
    this.prepareForStop();
    this.activeTrack = null;
    this.storedUseMicrophone = false;

    if (track !== null) {
      VideoRenderRegistry.unregister(track);
    }
    await this.releaseCamera();
    this.isMicrophoneCapturing = false;
  }

  /**
   * 立即停止麦克风、阻断相机帧输出并解除本地预览绑定。
   *
   * @returns 无返回值。
   */
  prepareForStop(): void {
    try {
      this.stopMicrophoneCapture();
    } catch (error) {
      this.logResourceError('停止麦克风采集 (Stop Microphone Capture)', error);
    }
    this.acceptsFrames = false;
    this.captureGeneration += 1;
    this.resetPreviewReadiness();
    try {
      this.rtcManager.unbindLocalVideo();
    } catch (error) {
      this.logResourceError(XmaxLogger.localized("解除相机预览绑定", "Unbind Camera Preview"), error);
    }
  }

  /**
   * 在前置和后置 CameraKit 摄像头之间切换。
   *
   * @returns 异步返回可用于后续连接、生成或显示的媒体流的 Promise。
   */
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
      this.synchronizeVideoFormat(currentTrack, this.frameOutput?.currentVideoFormat ?? videoFormat);
      updateRealtimeVideoTrackPosition(currentTrack, nextPosition);
      return new RealtimeMediaStream(StreamId.LOCAL, currentTrack);
    } catch (error) {
      this.acceptsFrames = false;
      await this.releaseCamera();
      await this.restoreCameraAfterFailedSwitch(videoFormat, position);
      throw XmaxError.from(error);
    }
  }

  /**
   * 完成权限检查、外部视频源配置、CameraKit 启动和预览注册。
   *
   * @param videoFormat 媒体输出或传输所需的视频规格。
   * @param position 使用的摄像头位置。
   * @param useMicrophone 是否采集并发布麦克风音频。
   * @param observeDisplayChange 是否跟随设备显示方向更新输出格式。
   * @returns 异步返回可用于后续连接、生成或显示的媒体流的 Promise。
   */
  private async createStream(
    videoFormat: RealtimeVideoFormat,
    position: CameraPosition,
    useMicrophone: boolean = false,
    observeDisplayChange: boolean = true
  ): Promise<RealtimeMediaStream> {
    const resolvedFormat: RealtimeVideoFormat = this.resolveVideoFormat(videoFormat);
    const track = new RealtimeVideoTrack('video0', resolvedFormat, position);
    this.observeDisplayChange = observeDisplayChange;

    try {
      await this.permissionManager.ensureCameraPermission();
      if (useMicrophone) {
        await this.permissionManager.ensureMicrophonePermission();
      }
      this.streamController.setVideoEncoderConfig(resolvedFormat);
      this.rtcManager.useExternalVideoSource();
      this.rtcManager.configureLocalVideoMirror(position);
      this.acceptsFrames = true;
      await this.startCamera(resolvedFormat, position);
      this.synchronizeVideoFormat(track, this.frameOutput?.currentVideoFormat ?? resolvedFormat);

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
      this.storedUseMicrophone = useMicrophone;

      return new RealtimeMediaStream(StreamId.LOCAL, track);
    } catch (error) {
      this.acceptsFrames = false;
      VideoRenderRegistry.unregister(track);
      await this.releaseCamera();
      throw XmaxError.from(error);
    }
  }

  /**
   * 创建 CameraKit 会话，并将帧输出绑定到 Native ImageReceiver Surface。
   *
   * @param videoFormat 媒体输出或传输所需的视频规格。
   * @param position 使用的摄像头位置。
   * @returns 操作完成时兑现的 Promise。
   */
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
            `${XmaxLogger.localized("CameraKit 采集规格 ", "CameraKit Capture Profile ")}${dimensions}${XmaxLogger.localized(" 不支持 30 fps，尝试下一档规格", " does not support 30 fps; trying the next profile")}`, 'Camera');
          await this.releaseCamera();
          continue;
        }

        operation = `Set CameraKit frame rate to 30 fps (${dimensions})`;
        output.output.setFrameRate(CAMERA_CAPTURE_FRAME_RATE, CAMERA_CAPTURE_FRAME_RATE);
        operation = `Start CameraKit capture (${dimensions})`;
        await this.captureSession!.start();
        output.configure(videoFormat, CAMERA_CAPTURE_FRAME_RATE, this.observeDisplayChange);
        const outputFormat: RealtimeVideoFormat = output.currentVideoFormat ?? videoFormat;

        XmaxLogger.debug(
          "CameraKit 相机采集已启动 (CameraKit Capture Started)\n" +
          `${XmaxLogger.localized("├─ 采集：", "├─ Capture: ")}${dimensions} @ ${CAMERA_CAPTURE_FRAME_RATE} fps\n` +
          `${XmaxLogger.localized("└─ 输出：", "└─ Output: ")}${outputFormat.width} × ${outputFormat.height} @ ${outputFormat.fps} fps`,
          'Camera'
        );
        return;
      }

      throw this.cameraError('Camera does not support a compatible 16:9 or 4:3 YUV output at 30 fps');
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

  /**
   * 将候选输出接入实际会话，使帧率查询具备设备与配置上下文。
   *
   * @param device 所选摄像头设备。
   * @param profile 摄像头采集规格。
   * @param generation 摄像头采集版本，用于忽略已停止采集的回调。
   * @returns 异步返回已创建的摄像头原始帧输出组件的 Promise。
   */
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
      device.cameraPosition,
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

  /**
   * 将摄像头失败原因包装为媒体采集错误。
   *
   * @param message 日志内容、错误说明或收到的信令文本。
   * @returns 描述摄像头采集失败的 SDK 错误。
   */
  private cameraError(message: string): XmaxError {
    return new XmaxError(XmaxErrorCode.MEDIA_ERROR, message);
  }

  /**
   * 将相机帧交给统一外部视频推送链路。
   *
   * @param frame 需要处理或交付的媒体帧。
   * @param generation 摄像头采集版本，用于忽略已停止采集的回调。
   * @returns 无返回值。
   */
  private handleFrame(frame: VideoFrame, generation: number): void {
    if (!this.acceptsFrames || generation !== this.captureGeneration) {
      return;
    }

    try {
      const format: RealtimeVideoFormat | null | undefined = this.frameOutput?.currentVideoFormat;
      if (format !== undefined && format !== null) {
        // 转屏前已经排队的帧不能重新覆盖新规格，也不能用新编码尺寸推送。
        if (frame.format.width !== format.width || frame.format.height !== format.height) {
          return;
        }
        if (this.activeTrack !== null) {
          this.synchronizeVideoFormat(this.activeTrack, format);
        }
      }
      this.streamController.pushLocalVideoFrame(frame);
      this.hasCapturedFrame = true;
      this.notifyPreviewReadyIfNeeded();
    } catch (error) {
      this.errorListener(XmaxError.from(error));
    }
  }

  /**
   * 同步摄像头轨道格式，并通知渲染与生成配置更新。
   *
   * @param track SDK 返回的视频轨道句柄。
   * @param format 需要使用的视频格式。
   * @returns 无返回值。
   */
  private synchronizeVideoFormat(track: RealtimeVideoTrack, format: RealtimeVideoFormat): void {
    const previous: RealtimeVideoFormat | undefined = track.videoFormat;
    if (previous?.width === format.width && previous.height === format.height && previous.fps === format.fps) {
      return;
    }
    this.streamController.setVideoEncoderConfig(format);
    this.formatListener(format);
    updateRealtimeVideoTrackFormat(track, format);
    VideoRenderRegistry.notifyVideoFormatChanged(track);
  }

  /**
   * 尝试在切换失败后恢复原摄像头。
   *
   * @param videoFormat 媒体输出或传输所需的视频规格。
   * @param position 使用的摄像头位置。
   * @returns 操作完成时兑现的 Promise。
   */
  private async restoreCameraAfterFailedSwitch(
    videoFormat: RealtimeVideoFormat,
    position: CameraPosition
  ): Promise<void> {
    try {
      this.rtcManager.configureLocalVideoMirror(position);
      this.acceptsFrames = true;
      await this.startCamera(videoFormat, position);
    } catch (rollbackError) {
      this.prepareForStop();
      const track: RealtimeVideoTrack | null = this.activeTrack;
      this.activeTrack = null;
      if (track !== null) {
        VideoRenderRegistry.unregister(track);
      }
      await this.releaseCamera();
      XmaxLogger.error(
        `${XmaxLogger.localized("恢复 CameraKit 相机失败 (Failed to Restore CameraKit Capture)\n└─ 原因：", "恢复 CameraKit 相机失败 (Failed to Restore CameraKit Capture)\n└─ Reason: ")}${XmaxError.from(rollbackError).message}`,
        'Camera'
      );
    }
  }

  /**
   * 按停止会话、释放输出、关闭输入的顺序释放 CameraKit。
   *
   * @returns 操作完成时兑现的 Promise。
   */
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
        this.logResourceError(XmaxLogger.localized("停止 CameraKit 会话", "Stop CameraKit Session"), error);
      }
      try {
        await session.release();
      } catch (error) {
        this.logResourceError(XmaxLogger.localized("释放 CameraKit 会话", "Release CameraKit Session"), error);
      }
    }
    if (output !== null) {
      await output.release();
    }
    if (input !== null) {
      try {
        await input.close();
      } catch (error) {
        this.logResourceError(XmaxLogger.localized("关闭 CameraKit 输入", "Close CameraKit Input"), error);
      }
    }
  }

  /**
   * 选择指定方向的相机设备。
   *
   * @param position 使用的摄像头位置。
   * @returns 匹配指定前后位置的可用摄像头；不存在时抛出采集错误。
   */
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

  /**
   * 优先从 1920×1080 向下尝试 16:9；不支持 30 fps 时回退到 4:3。
   *
   * @param device 所选摄像头设备。
   * @returns 所选摄像头可用的原始帧采集规格列表。
   */
  private captureProfiles(device: camera.CameraDevice): Array<camera.Profile> {
    const capability: camera.CameraOutputCapability = this.platformManager
      .getSupportedOutputCapability(device, camera.SceneMode.NORMAL_VIDEO);
    const profiles: Array<camera.Profile> = capability.previewProfiles.filter(
      (profile: camera.Profile): boolean => {
        const width: number = Math.max(profile.size.width, profile.size.height);
        const height: number = Math.min(profile.size.width, profile.size.height);
        return profile.format === camera.CameraFormat.CAMERA_FORMAT_YUV_420_SP &&
          (this.isWideCaptureProfile(profile) || width * 3 === height * 4) &&
          width <= MAXIMUM_CAPTURE_WIDTH && height <= MAXIMUM_CAPTURE_HEIGHT;
      });
    profiles.sort((left: camera.Profile, right: camera.Profile): number => {
      const leftWide: boolean = this.isWideCaptureProfile(left);
      const rightWide: boolean = this.isWideCaptureProfile(right);
      if (leftWide !== rightWide) {
        return leftWide ? -1 : 1;
      }
      return right.size.width * right.size.height - left.size.width * left.size.height;
    });
    if (profiles.length === 0) {
      throw this.cameraError('Camera does not support a compatible 16:9 or 4:3 YUV preview output');
    }
    return profiles;
  }

  /**
   * 判断摄像头采集规格是否为横向画幅。
   *
   * @param profile 摄像头采集规格。
   * @returns 采集宽度大于高度时返回 true。
   */
  private isWideCaptureProfile(profile: camera.Profile): boolean {
    const width: number = Math.max(profile.size.width, profile.size.height);
    const height: number = Math.min(profile.size.width, profile.size.height);
    return width * 9 === height * 16;
  }

  /**
   * 校验视频格式并将尺寸调整为模型支持的输入规格。
   *
   * @param videoFormat 媒体输出或传输所需的视频规格。
   * @returns 计算或更新后的视频格式。
   */
  private resolveVideoFormat(videoFormat: RealtimeVideoFormat): RealtimeVideoFormat {
    videoFormat.validate();
    const targetSize: ImageSize = this.mediaService.resolveMediaSize(
      new ImageSize(videoFormat.width, videoFormat.height), RealtimeMediaSource.CAMERA
    );
    return videoFormat.resized(targetSize.width, targetSize.height);
  }

  /**
   * 清除摄像头预览的采集、绑定和通知标记。
   *
   * @returns 无返回值。
   */
  private resetPreviewReadiness(): void {
    this.hasCapturedFrame = false;
    this.hasReportedPreviewReady = false;
  }

  /**
   * 在采集和预览绑定均完成后仅通知一次预览就绪。
   *
   * @returns 无返回值。
   */
  private notifyPreviewReadyIfNeeded(): void {
    const listener: CameraPreviewReadyHandler | null = this.previewReadyListener;
    if (listener === null || !this.hasCapturedFrame || !this.hasBoundPreview ||
      this.hasReportedPreviewReady) {
      return;
    }
    this.hasReportedPreviewReady = true;
    try {
      listener();
    } catch (error) {
      this.logResourceError(XmaxLogger.localized("执行摄像头预览就绪监听器", "Invoke Camera Preview Ready Listener"), error);
    }
  }

  /**
   * 记录摄像头资源操作失败的名称和原因。
   *
   * @param action 正在执行的资源操作名称或操作函数。
   * @param error 当前操作失败或终止的原因。
   * @returns 无返回值。
   */
  private logResourceError(action: string, error: Object): void {
    const reason: string = error instanceof Error ? error.message : String(error);
    XmaxLogger.error(`${action}${XmaxLogger.localized("失败\n└─ 原因：", " Failed\n└─ Reason: ")}${reason}`, 'Camera');
  }
}
