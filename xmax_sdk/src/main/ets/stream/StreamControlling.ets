//
//  StreamControlling.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeGenerationParameters } from '../service/realtime/RealtimeGenerationOptions';
import { UplinkVideoStatisticsListener, DownlinkVideoStatisticsListener } from '../foundation/rtc/VideoStatistics';
import { QualityConfiguration, QualityChange, AdaptiveQualityListener } from './quality/QualityConfiguration';
import { RealtimeNetworkQuality } from '../service/realtime/RealtimeNetworkQuality';
import { ImageSize } from '../service/media/ImageSize';
import { AudioFrame } from '../foundation/media/audio/AudioFrame';
import { VideoFrame } from '../foundation/media/video/VideoFrame';
import { RealtimeContext } from '../service/realtime/RealtimeContext';
import { RealtimeNetworkQualityListener } from '../service/realtime/RealtimeNetworkQuality';
import { RealtimePerformanceAlarmListener } from '../service/realtime/RealtimePerformanceAlarm';
import { RealtimePoint } from '../service/realtime/RealtimePoint';
import { RealtimeSessionConnection } from '../service/realtime/RealtimeSessionConnection';
import { RealtimeVideoFormat } from '../service/realtime/RealtimeVideoFormat';

/** The stream layer interface used by Core and business components. */
export interface StreamControlling {

  /** Sets the uplink video statistics listener; null removes it. */
  setUplinkVideoStatisticsListener(
    listener: UplinkVideoStatisticsListener | null
  ): void;

  /** Sets the result stream video statistics listener; null removes it. */
  setDownlinkVideoStatisticsListener(
    listener: DownlinkVideoStatisticsListener | null
  ): void;

  /** The fixed media baseline and current transmission levels. */
  readonly qualityConfiguration: QualityConfiguration | undefined;

  /**
   * Initializes uplink/downlink adaptation from the media baseline and valid quality history.
   *
   * @param baseline The baseline preserving media aspect ratio and explicit encoding settings.
   * @param model The model name separating quality history by model.
   *
   * @returns The initialized uplink/downlink quality configuration.
   */
  prepareQuality(
    baseline: RealtimeVideoFormat,
    model: string
  ): QualityConfiguration;

  /**
   * Replaces the media baseline while retaining quality levels and resetting sample windows.
   *
   * @param baseline The baseline preserving media aspect ratio and explicit encoding settings.
   *
   * @returns The updated configuration, or undefined before preparation.
   */
  rebaseQuality(
    baseline: RealtimeVideoFormat
  ): QualityConfiguration | undefined;

  /**
   * Sets the adaptive quality handler; null removes it.
   *
   * @param listener The event handler, or null to remove it.
   */
  setAdaptiveQualityListener(
    listener: AdaptiveQualityListener | null
  ): void;

  /**
   * Resolves quality recommendations from consecutive samples without changing current levels.
   *
   * @param quality The uplink, downlink, or combined network quality sample.
   * @param sampledAt The monotonic network sample time, in seconds.
   *
   * @returns The candidate levels, with undefined for directions not requiring adjustment.
   */
  proposeQuality(
    quality: RealtimeNetworkQuality,
    sampledAt: number
  ): QualityChange;

  /**
   * Records a quality submission, updating levels and history only on success.
   *
   * @param downlink Whether this is downlink; false selects uplink.
   * @param level The quality level, from 1 to 5; lower values mean higher quality.
   * @param success Whether the configuration was submitted successfully.
   */
  completeQuality(
    downlink: boolean,
    level: number,
    success: boolean
  ): void;

  /** Clears consecutive samples while retaining quality levels. */
  resetQualitySamples(): void;

  /**
   * Submits task result dimensions and bitrate without waiting for server application.
   *
   * @param taskId The current generation task identifier.
   * @param targetSize The optional result stream target dimensions.
   */
  changeTargetSize(
    taskId: string,
    targetSize: ImageSize
  ): void;

  /** The remote volume in 0 to 1 at RTC percentage precision. */
  readonly remoteAudioVolume: number;

  /**
   * Sets remote volume in 0 to 1, caching it before subscription.
   *
   * @param volume A finite volume in 0 to 1; zero mutes, one uses original volume, and the value
   * before local stream creation is one.
   */
  setRemoteAudioVolume(
    volume: number
  ): void;

  /** @returns The pending or active task identifier, or an empty string without a task. */
  readonly currentGenerationTaskId: string;

  /**
   * Configures the realtime video encoder.
   *
   * @param videoFormat The RTC encoding width, height, and frame rate.
   */
  setVideoEncoderConfig(
    videoFormat: RealtimeVideoFormat
  ): void;

  /**
   * Sets the network quality listener.
   *
   * @param listener The network quality handler, or null to remove it.
   */
  setNetworkQualityListener(
    listener: RealtimeNetworkQualityListener | null
  ): void;

  /**
   * Sets the device performance listener.
   *
   * @param listener The device performance handler, or null to remove it.
   */
  setPerformanceAlarmListener(
    listener: RealtimePerformanceAlarmListener | null
  ): void;

  /**
   * Joins the RTC room and publishes local media.
   *
   * The Promise fulfills after room joining and local publication.
   *
   * @param connection The room, user, token, and target bot information.
   * @param includeLocalAudio Whether to publish local audio with video.
   * @param ensureActive The callback checking connection validity across asynchronous boundaries.
   */
  connect(
    connection: RealtimeSessionConnection,
    includeLocalAudio: boolean,
    ensureActive: () => void
  ): Promise<void>;

  /**
   * Clears stream state and leaves the room, returning safely without an active room.
   *
   * The Promise fulfills after stream cleanup.
   */
  disconnect(): Promise<void>;

  /**
   * Updates local audio publication.
   *
   * @param enabled Whether to publish local audio.
   */
  setLocalAudioEnabled(
    enabled: boolean
  ): void;

  /**
   * Submits a local external video frame.
   *
   * @param frame The local video frame ready for RTC.
   */
  pushLocalVideoFrame(
    frame: VideoFrame
  ): void;

  /**
   * Submits a local external audio frame.
   *
   * @param frame The local PCM frame ready for RTC.
   */
  pushLocalAudioFrame(
    frame: AudioFrame
  ): void;

  /**
   * Creates a generation task, sends its start signal, and waits for a matching result stream.
   *
   * The Promise fulfills when a matching result stream is found.
   *
   * @param taskId The current generation task identifier.
   * @param videoFormat The current local media format.
   * @param context The generation task's conditions.
   * @param faceRestoration Whether to enable face restoration.
   * @param targetSize The optional result stream target dimensions.
   * @param paddingContain Whether to preserve media aspect ratio with server-side padding.
   * @param extraParams The static generation parameters passed internally by the SDK.
   */
  beginGeneration(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext,
    faceRestoration?: boolean,
    targetSize?: ImageSize,
    paddingContain?: boolean,
    extraParams?: RealtimeGenerationParameters
  ): Promise<void>;

  /** Activates matched result audio after first-frame readiness. */
  activateRemoteAudio(): void;

  /**
   * Sends updated generation conditions.
   *
   * @param taskId The current generation task identifier.
   * @param videoFormat The current local media format.
   * @param context The updated generation conditions.
   * @param faceRestoration Whether to enable face restoration.
   * @param targetSize The optional result stream target dimensions.
   * @param paddingContain Whether to preserve media aspect ratio with server-side padding.
   * @param extraParams The static generation parameters passed internally by the SDK.
   */
  updateGeneration(
    taskId: string,
    videoFormat: RealtimeVideoFormat,
    context: RealtimeContext,
    faceRestoration?: boolean,
    targetSize?: ImageSize,
    paddingContain?: boolean,
    extraParams?: RealtimeGenerationParameters
  ): void;

  /**
   * Stops a generation task and clears its result stream.
   *
   * @param taskId The task to stop; an empty string selects the current task.
   */
  stopGeneration(
    taskId: string
  ): void;

  /**
   * Sends interaction trajectories to a generation task.
   *
   * @param taskId The task receiving interaction trajectories.
   * @param points The model input trajectory points to send.
   */
  sendTracks(
    taskId: string,
    points: RealtimePoint[]
  ): void;
}
