//
//  RtcManaging.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeVideoFrame } from '../../service/realtime/RealtimeVideoFrame';
import { image } from '@kit.ImageKit';
import { AudioFrame } from '../media/audio/AudioFrame';
import { CameraPosition } from '../media/camera/CameraPosition';
import { VideoFrame } from '../media/video/VideoFrame';
import { VideoContentMode } from '../media/video/VideoContentMode';
import { RemoteStream } from './RemoteStream';
import { RoomJoinConfiguration } from './RoomJoinConfiguration';
import { RtcEventListener } from './RtcEventListener';
import { RtcQualityListener } from './RtcQualityListener';
import { VideoEncodingConfiguration } from './VideoEncodingConfiguration';

/**
 * Receives the stream whose first remote frame has been rendered.
 *
 * @param stream The remote stream that produced the frame.
 */
export type RtcRemoteVideoRenderedListener = (
  stream: RemoteStream
) => void;

/**
 * Receives decoded remote frames and an on-demand pixel copier.
 *
 * copyFrame is valid only within the RTC callback and copies pixels on demand.
 *
 * @param stream The remote stream that produced the frame.
 * @param copyFrame The on-demand native frame copier, valid only during the callback.
 */
export type RtcRemoteVideoFrameListener = (
  stream: RemoteStream,
  copyFrame: () => RealtimeVideoFrame
) => void;

/** An interface for RTC engines, rooms, media transport, and rendering. */
export interface RtcManaging {

  /**
   * Initializes the RTC engine.
   *
   * The Promise fulfills after initialization.
   */
  initialize(): Promise<void>;

  /**
   * Destroys the RTC engine and releases resources.
   *
   * The Promise fulfills after resources are released.
   */
  destroy(): Promise<void>;

  /**
   * Applies video encoder configuration.
   *
   * @param configuration The video encoder configuration.
   */
  configureVideoEncoding(
    configuration: VideoEncodingConfiguration
  ): void;

  /** Selects external video frame input. */
  useExternalVideoSource(): void;

  /**
   * Selects internal audio and starts microphone capture; microphone permission must already be
   * granted.
   */
  startMicrophoneCapture(): void;

  /** Stops RTC microphone capture. */
  stopMicrophoneCapture(): void;

  /** Starts external RTC audio input. */
  startExternalAudioSource(): void;

  /** Stops external RTC audio input. */
  stopExternalAudioSource(): void;

  /**
   * Applies local video mirroring.
   *
   * @param position The camera position.
   */
  configureLocalVideoMirror(
    position: CameraPosition
  ): void;

  /**
   * Submits an external video frame.
   *
   * @param frame The video frame.
   * @param seiData The metadata sent with the video frame.
   */
  pushExternalVideoFrame(
    frame: VideoFrame,
    seiData?: Uint8Array
  ): void;

  /**
   * Submits an external audio frame.
   *
   * @param frame The 10 ms PCM frame.
   */
  pushExternalAudioFrame(
    frame: AudioFrame
  ): void;

  /**
   * Joins an RTC room.
   *
   * The Promise fulfills after joining the room.
   *
   * @param configuration The room join configuration.
   */
  joinRoom(
    configuration: RoomJoinConfiguration
  ): Promise<void>;

  /**
   * Leaves the current RTC room.
   *
   * The Promise fulfills after leaving the room.
   */
  leaveRoom(): Promise<void>;

  /** Publishes local video. */
  publishLocalVideo(): void;

  /** Unpublishes local video. */
  unpublishLocalVideo(): void;

  /** Publishes local audio. */
  publishLocalAudio(): void;

  /** Unpublishes local audio. */
  unpublishLocalAudio(): void;

  /**
   * Updates a remote video subscription.
   *
   * @param userId The remote user identifier.
   * @param subscribe Whether to subscribe to video.
   */
  subscribeRemoteVideo(
    userId: string,
    subscribe: boolean
  ): void;

  /**
   * Updates a remote audio subscription.
   *
   * @param userId The remote user identifier.
   * @param subscribe Whether to subscribe to audio.
   */
  subscribeRemoteAudio(
    userId: string,
    subscribe: boolean
  ): void;

  /**
   * Sets a remote user's audio playback volume.
   *
   * @param userId The remote user identifier.
   * @param volume The RTC volume; 100 represents original volume.
   */
  setRemoteAudioVolume(
    userId: string,
    volume: number
  ): void;

  /**
   * Binds local video to a rendering view.
   *
   * @param viewId The rendering view identifier.
   * @param contentMode The video content mode.
   */
  bindLocalVideo(
    viewId: string,
    contentMode: VideoContentMode
  ): void;

  /** Detaches local video from its rendering view. */
  unbindLocalVideo(): void;

  /**
   * Binds remote video to a rendering view.
   *
   * @param stream The remote stream information.
   * @param viewId The rendering view identifier.
   * @param contentMode The video content mode.
   */
  bindRemoteVideo(
    stream: RemoteStream,
    viewId: string,
    contentMode: VideoContentMode
  ): void;

  /**
   * Detaches remote video from its rendering view.
   *
   * @param stream The remote stream information.
   */
  unbindRemoteVideo(
    stream: RemoteStream
  ): void;

  /**
   * Captures an RTC snapshot. The caller releases the returned PixelMap.
   *
   * @param stream The remote stream identified by room and user.
   *
   * @returns The caller-owned snapshot PixelMap; the Promise rejects on failure or timeout.
   */
  takeRemoteSnapshot(
    stream: RemoteStream
  ): Promise<image.PixelMap>;

  /**
   * Returns the RTC rendering library name.
   *
   * @returns The RTC rendering library name.
   */
  renderLibraryName(): string;

  /**
   * Observes the first remote frame rendered to a view.
   *
   * @param listener The event handler, or null to remove it.
   */
  setRemoteVideoRenderedListener(
    listener: RtcRemoteVideoRenderedListener | null
  ): void;

  /**
   * Returns whether the stream rendered a first frame during this publication, supporting view
   * reattachment.
   *
   * @param stream The remote stream identified by room and user.
   *
   * @returns True if the stream rendered its first frame during the current publication.
   */
  hasRenderedRemoteVideo(
    stream: RemoteStream
  ): boolean;

  /**
   * Observes decoded, postprocessed remote frames independently of Surface attachment.
   *
   * @param listener The event handler, or null to remove it.
   */
  setRemoteVideoFrameListener(
    listener: RtcRemoteVideoFrameListener | null
  ): void;

  /**
   * Enables frame callbacks on demand; disable after first-frame confirmation to avoid continued
   * pixel delivery to ArkTS.
   *
   * @param stream The remote stream identified by room and user.
   * @param enabled Whether to enable this capability.
   */
  observeRemoteVideoFrames(
    stream: RemoteStream,
    enabled: boolean
  ): void;

  /**
   * Sends a message to the current RTC room.
   *
   * @param message The message content.
   */
  sendRoomMessage(
    message: string
  ): void;

  /**
   * Sets the RTC event listener.
   *
   * @param listener The RTC event listener, or null to remove it.
   */
  setEventListener(
    listener: RtcEventListener | null
  ): void;

  /**
   * Sets the RTC quality event listener.
   *
   * @param listener The RTC quality listener, or null to remove it.
   */
  setQualityListener(
    listener: RtcQualityListener | null
  ): void;
}
