//
//  native_video_file_decoder.cpp
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#include "native_video_file_decoder.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include <poll.h>
#include <unistd.h>

#include "hilog/log.h"
#include "multimedia/player_framework/native_avbuffer.h"
#include "multimedia/player_framework/native_avcodec_base.h"
#include "multimedia/player_framework/native_avcodec_videodecoder.h"
#include "multimedia/player_framework/native_avdemuxer.h"
#include "multimedia/player_framework/native_avformat.h"
#include "multimedia/player_framework/native_avsource.h"
#include "multimedia/video_processing_engine/video_processing.h"
#include "multimedia/video_processing_engine/video_processing_types.h"
#include "native_buffer/native_buffer.h"
#include "native_image/native_image.h"
#include "native_window/external_window.h"

namespace {

/** An NV12 video packet with layout, timestamp, and end or error notifications. */
struct DecodedFramePacket {

  // NV12 pixel data and layout

  /** The owned media bytes. */
  std::vector<uint8_t> data;

  /** The image or frame width. */
  int32_t width = 0;

  /** The image or frame height. */
  int32_t height = 0;

  /** The plane row stride, in bytes. */
  int32_t stride = 0;

  // Playback time and end or error notifications

  /** The frame timestamp, in microseconds. */
  int64_t timestampUs = 0;

  /** Whether the packet marks media completion. */
  bool endOfStream = false;

  /** The media processing failure description, if any. */
  std::string error;
};

/** A pending decoded Surface buffer, synchronization fence, and timestamp. */
struct SurfaceBufferPacket {

  // Surface buffer ownership

  /** The native window buffer owned until returned to its Surface. */
  OHNativeWindowBuffer *windowBuffer = nullptr;

  // Read/write synchronization and playback time

  /** The synchronization fence descriptor owned by this buffer packet. */
  int fenceFd = -1;

  /** The frame timestamp, in microseconds. */
  int64_t timestampUs = 0;
};

/**
 * Checks whether a rotation is a supported quarter-turn multiple.
 *
 * @param rotation The rotation, in degrees: 0, 90, 180, or 270.
 * @return True for 0, 90, 180, or 270 degrees.
 */
bool IsSupportedRotation(int32_t rotation) {
  return rotation == 0 || rotation == 90 || rotation == 180 || rotation == 270;
}

/**
 * Copies and rotates NV12 planes into tightly packed pixel data.
 *
 * @param sourceLuma The source Y plane address.
 * @param sourceLumaStride The source luma row stride, in bytes.
 * @param sourceChroma The source interleaved chroma plane address.
 * @param sourceChromaStride The source chroma row stride, in bytes.
 * @param width The frame width, in pixels.
 * @param height The frame height, in pixels.
 * @param rotation The rotation, in degrees: 0, 90, 180, or 270.
 * @param output Receives the converted or extracted value.
 */
void CopyOrRotateNv12(const uint8_t *sourceLuma,
    int32_t sourceLumaStride,
    const uint8_t *sourceChroma,
    int32_t sourceChromaStride,
    int32_t width,
    int32_t height,
    int32_t rotation,
    std::vector<uint8_t> *output) {
  const bool swapsDimensions = rotation == 90 || rotation == 270;
  const int32_t targetWidth = swapsDimensions ? height : width;
  const int32_t targetHeight = swapsDimensions ? width : height;
  const size_t targetLumaLength =
      static_cast<size_t>(targetWidth) * static_cast<size_t>(targetHeight);
  output->resize(targetLumaLength + targetLumaLength / 2);

  uint8_t *targetLuma = output->data();
  if (rotation == 0) {
    const size_t lumaLength = static_cast<size_t>(width) * height;
    if (sourceLumaStride == width && sourceChromaStride == width) {
      std::memcpy(output->data(), sourceLuma, lumaLength);
      std::memcpy(output->data() + lumaLength, sourceChroma, lumaLength / 2);
      return;
    }
    for (int32_t y = 0; y < height; ++y) {
      std::memcpy(targetLuma + static_cast<size_t>(y) * width,
          sourceLuma + static_cast<size_t>(y) * sourceLumaStride,
          width);
    }
    uint8_t *targetChroma = output->data() + targetLumaLength;
    for (int32_t y = 0; y < height / 2; ++y) {
      std::memcpy(targetChroma + static_cast<size_t>(y) * width,
          sourceChroma + static_cast<size_t>(y) * sourceChromaStride,
          width);
    }
    return;
  }

  constexpr int32_t LUMA_TILE_SIZE = 32;
  for (int32_t blockY = 0; blockY < height; blockY += LUMA_TILE_SIZE) {
    for (int32_t blockX = 0; blockX < width; blockX += LUMA_TILE_SIZE) {
      const int32_t endY = std::min(blockY + LUMA_TILE_SIZE, height);
      const int32_t endX = std::min(blockX + LUMA_TILE_SIZE, width);
      for (int32_t y = blockY; y < endY; ++y) {
        for (int32_t x = blockX; x < endX; ++x) {
          int32_t targetX = 0;
          int32_t targetY = 0;
          if (rotation == 90) {
            targetX = height - 1 - y;
            targetY = x;
          } else if (rotation == 180) {
            targetX = width - 1 - x;
            targetY = height - 1 - y;
          } else {
            targetX = y;
            targetY = width - 1 - x;
          }
          targetLuma[static_cast<size_t>(targetY) * targetWidth + targetX] =
              sourceLuma[static_cast<size_t>(y) * sourceLumaStride + x];
        }
      }
    }
  }

  uint8_t *targetChroma = output->data() + targetLumaLength;
  const int32_t sourceChromaWidth = width / 2;
  const int32_t sourceChromaHeight = height / 2;
  const int32_t targetChromaStride = targetWidth;
  constexpr int32_t CHROMA_TILE_SIZE = 16;
  for (int32_t blockY = 0; blockY < sourceChromaHeight; blockY += CHROMA_TILE_SIZE) {
    for (int32_t blockX = 0; blockX < sourceChromaWidth; blockX += CHROMA_TILE_SIZE) {
      const int32_t endY = std::min(blockY + CHROMA_TILE_SIZE, sourceChromaHeight);
      const int32_t endX = std::min(blockX + CHROMA_TILE_SIZE, sourceChromaWidth);
      for (int32_t y = blockY; y < endY; ++y) {
        for (int32_t x = blockX; x < endX; ++x) {
          int32_t targetX = 0;
          int32_t targetY = 0;
          if (rotation == 90) {
            targetX = sourceChromaHeight - 1 - y;
            targetY = x;
          } else if (rotation == 180) {
            targetX = sourceChromaWidth - 1 - x;
            targetY = sourceChromaHeight - 1 - y;
          } else {
            targetX = y;
            targetY = sourceChromaWidth - 1 - x;
          }
          const size_t sourceOffset = static_cast<size_t>(y) * sourceChromaStride + x * 2;
          const size_t targetOffset =
              static_cast<size_t>(targetY) * targetChromaStride + targetX * 2;
          targetChroma[targetOffset] = sourceChroma[sourceOffset];
          targetChroma[targetOffset + 1] = sourceChroma[sourceOffset + 1];
        }
      }
    }
  }
}

/**
 * Maps a target plane coordinate into source bounds.
 *
 * @param targetIndex The target plane sample index.
 * @param sourceSize The source plane dimension, in samples.
 * @param targetSize The target plane dimension, in samples.
 * @return The corresponding source sample index.
 */
int32_t ScaledIndex(int32_t targetIndex, int32_t sourceSize, int32_t targetSize) {
  return std::min(
      static_cast<int32_t>((static_cast<int64_t>(targetIndex) * sourceSize) / targetSize),
      sourceSize - 1);
}

/**
 * Scales a pixel plane with one-byte or two-byte samples.
 *
 * @param source The source plane address.
 * @param sourceStride The source plane row stride, in bytes.
 * @param sourceWidth The source image width, in pixels.
 * @param sourceHeight The source image height, in pixels.
 * @param target The target plane address.
 * @param targetStride The target plane row stride, in bytes.
 * @param targetWidth The target image or plane width.
 * @param targetHeight The target image or plane height.
 * @param bytesPerSample The bytes per sample: 1 or 2.
 */
void ScalePlane(const uint8_t *source,
    int32_t sourceStride,
    int32_t sourceWidth,
    int32_t sourceHeight,
    uint8_t *target,
    int32_t targetStride,
    int32_t targetWidth,
    int32_t targetHeight,
    int32_t bytesPerSample) {
  std::vector<int32_t> sourceX(targetWidth);
  for (int32_t x = 0; x < targetWidth; ++x) {
    sourceX[x] = ScaledIndex(x, sourceWidth, targetWidth);
  }

  for (int32_t y = 0; y < targetHeight; ++y) {
    const int32_t sourceY = ScaledIndex(y, sourceHeight, targetHeight);
    const uint8_t *sourceRow = source + static_cast<size_t>(sourceY) * sourceStride;
    uint8_t *targetRow = target + static_cast<size_t>(y) * targetStride;
    for (int32_t x = 0; x < targetWidth; ++x) {
      const uint8_t *sourceSample = sourceRow + static_cast<size_t>(sourceX[x]) * bytesPerSample;
      uint8_t *targetSample = targetRow + static_cast<size_t>(x) * bytesPerSample;
      targetSample[0] = sourceSample[0];
      if (bytesPerSample == 2) {
        targetSample[1] = sourceSample[1];
      }
    }
  }
}

/**
 * Scales NV12 into tightly packed target planes.
 *
 * @param sourceLuma The source Y plane address.
 * @param sourceLumaStride The source luma row stride, in bytes.
 * @param sourceChroma The source interleaved chroma plane address.
 * @param sourceChromaStride The source chroma row stride, in bytes.
 * @param sourceWidth The source image width, in pixels.
 * @param sourceHeight The source image height, in pixels.
 * @param targetWidth The target image or plane width.
 * @param targetHeight The target image or plane height.
 * @param output Receives the converted or extracted value.
 */
void ScaleNv12(const uint8_t *sourceLuma,
    int32_t sourceLumaStride,
    const uint8_t *sourceChroma,
    int32_t sourceChromaStride,
    int32_t sourceWidth,
    int32_t sourceHeight,
    int32_t targetWidth,
    int32_t targetHeight,
    std::vector<uint8_t> *output) {
  if (sourceWidth == targetWidth && sourceHeight == targetHeight) {
    CopyOrRotateNv12(sourceLuma,
        sourceLumaStride,
        sourceChroma,
        sourceChromaStride,
        sourceWidth,
        sourceHeight,
        0,
        output);
    return;
  }

  const size_t lumaLength = static_cast<size_t>(targetWidth) * targetHeight;
  output->resize(lumaLength + lumaLength / 2);
  ScalePlane(sourceLuma,
      sourceLumaStride,
      sourceWidth,
      sourceHeight,
      output->data(),
      targetWidth,
      targetWidth,
      targetHeight,
      1);
  ScalePlane(sourceChroma,
      sourceChromaStride,
      sourceWidth / 2,
      sourceHeight / 2,
      output->data() + lumaLength,
      targetWidth,
      targetWidth / 2,
      targetHeight / 2,
      2);
}

/**
 * Scales and rotates an NV12 image to the output dimensions.
 *
 * @param sourceLuma The source Y plane address.
 * @param sourceLumaStride The source luma row stride, in bytes.
 * @param sourceChroma The source interleaved chroma plane address.
 * @param sourceChromaStride The source chroma row stride, in bytes.
 * @param sourceWidth The source image width, in pixels.
 * @param sourceHeight The source image height, in pixels.
 * @param rotation The rotation, in degrees: 0, 90, 180, or 270.
 * @param targetWidth The target image or plane width.
 * @param targetHeight The target image or plane height.
 * @param output Receives the converted or extracted value.
 */
void ScaleAndRotateNv12(const uint8_t *sourceLuma,
    int32_t sourceLumaStride,
    const uint8_t *sourceChroma,
    int32_t sourceChromaStride,
    int32_t sourceWidth,
    int32_t sourceHeight,
    int32_t rotation,
    int32_t targetWidth,
    int32_t targetHeight,
    std::vector<uint8_t> *output) {
  const bool swapsDimensions = rotation == 90 || rotation == 270;
  const int32_t scaledWidth = swapsDimensions ? targetHeight : targetWidth;
  const int32_t scaledHeight = swapsDimensions ? targetWidth : targetHeight;
  std::vector<uint8_t> scaledData;
  ScaleNv12(sourceLuma,
      sourceLumaStride,
      sourceChroma,
      sourceChromaStride,
      sourceWidth,
      sourceHeight,
      scaledWidth,
      scaledHeight,
      &scaledData);
  if (rotation == 0) {
    *output = std::move(scaledData);
    return;
  }
  const size_t scaledLumaLength = static_cast<size_t>(scaledWidth) * scaledHeight;
  CopyOrRotateNv12(scaledData.data(),
      scaledWidth,
      scaledData.data() + scaledLumaLength,
      scaledWidth,
      scaledWidth,
      scaledHeight,
      rotation,
      output);
}

/** Decodes local video through Surface or buffer output into paced NV12 frames. */
class NativeVideoFileDecoder {
public:
  /** Creates a video file decoder. */
  NativeVideoFileDecoder() = default;

  /** Stops media output and releases owned native resources and caches. */
  ~NativeVideoFileDecoder() {
    Stop();
  }

  /** Only JS binding and fd ownership are established on the calling thread. */

  /**
   * Duplicates the file descriptor and binds the ArkTS listener for background initialization.
   *
   * @param env The current ArkTS N-API environment.
   * @param listener The ArkTS receiver for frames, end notifications, and errors.
   * @param sourceFd The caller-owned file descriptor, duplicated by the decoder for independent
   * ownership.
   * @param error Receives the failure description.
   * @return True if file and listener binding succeeds; false with an error otherwise.
   */
  bool Bind(napi_env env, napi_value listener, int32_t sourceFd, std::string *error) {
    fd_ = dup(sourceFd);
    if (fd_ < 0) {
      *error = "复制视频文件描述符失败";
      return false;
    }
    napi_value resourceName = nullptr;
    if (napi_create_string_utf8(env,
            "XmaxNativeVideoFileDecoder",
            NAPI_AUTO_LENGTH,
            &resourceName) != napi_ok ||
        napi_create_threadsafe_function(env,
            listener,
            nullptr,
            resourceName,
            4,
            1,
            nullptr,
            nullptr,
            nullptr,
            CallListener,
            &listener_) != napi_ok) {
      *error = "创建视频解码回调失败";
      return false;
    }
    return true;
  }

  /** Codec, demuxer and Surface setup run in a native async worker, without JS APIs. */

  /**
   * Creates native media resources for the requested output format.
   *
   * @param sourceSize The source file length, in bytes.
   * @param playbackAnchorUs The monotonic playback anchor for the media origin, in microseconds.
   * @param mediaStartUs The source media timeline origin, in microseconds.
   * @param rotation The rotation, in degrees: 0, 90, 180, or 270.
   * @param targetWidth The target image or plane width.
   * @param targetHeight The target image or plane height.
   * @param frameIntervalUs The target video output interval, in microseconds.
   * @param cycleDurationUs The duration of one playback cycle, in microseconds.
   * @param error Receives the failure description.
   * @return True on successful initialization; false with an error description otherwise.
   */
  bool Initialize(int64_t sourceSize,
      int64_t playbackAnchorUs,
      int64_t mediaStartUs,
      int32_t rotation,
      int32_t targetWidth,
      int32_t targetHeight,
      int64_t frameIntervalUs,
      int64_t cycleDurationUs,
      std::string *error) {
    playbackAnchorUs_ = playbackAnchorUs;
    mediaStartUs_ = mediaStartUs;
    rotation_ = rotation;
    targetWidth_ = targetWidth;
    targetHeight_ = targetHeight;
    frameIntervalUs_ = frameIntervalUs;
    cycleDurationUs_ = cycleDurationUs;

    source_ = OH_AVSource_CreateWithFD(fd_, 0, sourceSize);
    if (source_ == nullptr) {
      *error = "创建视频数据源失败";
      return false;
    }

    OH_AVFormat *sourceFormat = OH_AVSource_GetSourceFormat(source_);
    int32_t trackCount = 0;
    if (sourceFormat == nullptr ||
        !OH_AVFormat_GetIntValue(sourceFormat, OH_MD_KEY_TRACK_COUNT, &trackCount) ||
        trackCount <= 0) {
      if (sourceFormat != nullptr) {
        OH_AVFormat_Destroy(sourceFormat);
      }
      *error = "读取视频轨道数量失败";
      return false;
    }
    OH_AVFormat_Destroy(sourceFormat);

    for (int32_t index = 0; index < trackCount; ++index) {
      OH_AVFormat *candidate = OH_AVSource_GetTrackFormat(source_, index);
      int32_t trackType = -1;
      if (candidate != nullptr &&
          OH_AVFormat_GetIntValue(candidate, OH_MD_KEY_TRACK_TYPE, &trackType) &&
          trackType == MEDIA_TYPE_VID) {
        trackIndex_ = static_cast<uint32_t>(index);
        trackFormat_ = candidate;
        break;
      }
      if (candidate != nullptr) {
        OH_AVFormat_Destroy(candidate);
      }
    }
    if (trackFormat_ == nullptr) {
      *error = "视频文件中没有可解码的视频轨道";
      return false;
    }

    const char *mime = nullptr;
    if (!OH_AVFormat_GetStringValue(trackFormat_, OH_MD_KEY_CODEC_MIME, &mime) || mime == nullptr ||
        !OH_AVFormat_GetIntValue(trackFormat_, OH_MD_KEY_WIDTH, &width_) ||
        !OH_AVFormat_GetIntValue(trackFormat_, OH_MD_KEY_HEIGHT, &height_) || width_ <= 0 ||
        height_ <= 0) {
      *error = "读取视频轨道格式失败";
      return false;
    }
    stride_ = width_;
    sliceHeight_ = height_;
    pixelFormat_ = AV_PIXEL_FORMAT_NV12;
    int32_t isHdrVivid = 0;
    isHdrVivid_ =
        OH_AVFormat_GetIntValue(trackFormat_, OH_MD_KEY_VIDEO_IS_HDR_VIVID, &isHdrVivid) &&
        isHdrVivid == 1;
    OH_AVFormat_SetIntValue(trackFormat_, OH_MD_KEY_PIXEL_FORMAT, AV_PIXEL_FORMAT_NV12);
    if (isHdrVivid_) {
      OH_AVFormat_SetIntValue(trackFormat_,
          OH_MD_KEY_VIDEO_DECODER_OUTPUT_COLOR_SPACE,
          OH_COLORSPACE_BT709_LIMIT);
    }

    demuxer_ = OH_AVDemuxer_CreateWithSource(source_);
    if (demuxer_ == nullptr || OH_AVDemuxer_SelectTrackByID(demuxer_, trackIndex_) != AV_ERR_OK) {
      *error = "创建视频解封装器失败";
      return false;
    }

    if (!PrepareOutput(mime, error)) {
      return false;
    }

    // Start codec resources now, but do not consume media until the caller has
    // installed the handle and aligned the shared audio/video playback clock.
    paused_.store(true);
    running_.store(true);
    if (useSurfaceOutput_) {
      surfaceWorkerRunning_.store(true);
      surfaceWorker_ = std::thread(&NativeVideoFileDecoder::SurfaceWorkerLoop, this);
    }
    if (OH_VideoDecoder_Start(decoder_) != AV_ERR_OK) {
      *error = "启动视频连续解码失败";
      return false;
    }
    if (useSurfaceOutput_) {
      {
        std::lock_guard<std::mutex> lock(surfaceProcessingStateMutex_);
        videoProcessorStopped_ = false;
      }
      const VideoProcessing_ErrorCode processingResult = OH_VideoProcessing_Start(videoProcessor_);
      if (processingResult != VIDEO_PROCESSING_SUCCESS) {
        {
          std::lock_guard<std::mutex> lock(surfaceProcessingStateMutex_);
          videoProcessorStopped_ = true;
        }
        *error = "启动视频缩放失败：" + std::to_string(processingResult);
        return false;
      }
      videoProcessorStarted_ = true;
    }
    return true;
  }

  /** Pauses media output and wakes pacing waits so workers observe the pause. */
  void Pause() {
    if (!running_.load()) {
      return;
    }
    paused_.store(true);
    pacingCondition_.notify_all();
  }

  /**
   * Resumes output with the playback anchor shifted by the pause duration.
   *
   * @param pausedDurationUs The pause duration, in microseconds.
   */
  void Resume(int64_t pausedDurationUs) {
    if (!running_.load()) {
      return;
    }
    if (pausedDurationUs > 0) {
      playbackAnchorUs_.fetch_add(pausedDurationUs);
    }
    paused_.store(false);
    pacingCondition_.notify_all();
  }

  /** Stops output and workers, then releases the file, media resources, and callback references. */
  void Stop() {
    const bool wasRunning = running_.exchange(false);
    paused_.store(false);
    pacingCondition_.notify_all();

    { std::lock_guard<std::mutex> lock(demuxerMutex_); }

    if (decoder_ != nullptr) {
      if (wasRunning) {
        OH_VideoDecoder_Stop(decoder_);
      }
      StopSurfaceWorker();
      StopVideoProcessor();
      OH_VideoDecoder_Destroy(decoder_);
      decoder_ = nullptr;
    } else if (surfaceWorker_.joinable()) {
      StopSurfaceWorker();
    }
    if (listener_ != nullptr) {
      napi_release_threadsafe_function(listener_, napi_tsfn_abort);
      listener_ = nullptr;
    }
    if (demuxer_ != nullptr) {
      OH_AVDemuxer_Destroy(demuxer_);
      demuxer_ = nullptr;
    }
    if (trackFormat_ != nullptr) {
      OH_AVFormat_Destroy(trackFormat_);
      trackFormat_ = nullptr;
    }
    if (source_ != nullptr) {
      OH_AVSource_Destroy(source_);
      source_ = nullptr;
    }
    if (fd_ >= 0) {
      close(fd_);
      fd_ = -1;
    }
    ReleaseOutputSurface();
  }

private:
  /**
   * Selects buffer or Surface output and prepares the video decoder.
   *
   * @param mime The source track MIME type.
   * @param error Receives the failure description.
   * @return True if output setup succeeds; false with an error otherwise.
   */
  bool PrepareOutput(const char *mime, std::string *error) {
    // HDR requires Surface output for tone mapping. SDR only needs the extra
    // processing stage when both axes can be downscaled before CPU readback.
    useSurfaceOutput_ = ShouldUseSurfaceOutput();
    if (useSurfaceOutput_ && !InitializeOutputSurface(error)) {
      if (isHdrVivid_) {
        return false;
      }
      OH_LOG_Print(LOG_APP,
          LOG_WARN,
          0xA000,
          "XmaxSDK",
          "[Xmax][VideoDecoder] Surface scaling unavailable; using buffer output: %{public}s",
          error->c_str());
      useSurfaceOutput_ = false;
      error->clear();
    }
    if (PrepareDecoder(mime, error)) {
      return true;
    }
    if (!useSurfaceOutput_ || isHdrVivid_) {
      return false;
    }
    // Never switch a configured codec in place: recreate it in buffer mode.
    OH_LOG_Print(LOG_APP,
        LOG_WARN,
        0xA000,
        "XmaxSDK",
        "[Xmax][VideoDecoder] Surface decoder unavailable; using buffer output: %{public}s",
        error->c_str());
    if (decoder_ != nullptr) {
      OH_VideoDecoder_Destroy(decoder_);
      decoder_ = nullptr;
    }
    ReleaseOutputSurface();
    useSurfaceOutput_ = false;
    error->clear();
    return PrepareDecoder(mime, error);
  }

  /**
   * Determines whether the current video format requires Surface output.
   *
   * @return True if Surface output should be used.
   */
  bool ShouldUseSurfaceOutput() const {
    const bool swapsDimensions = rotation_ == 90 || rotation_ == 270;
    const int32_t outputWidth = swapsDimensions ? targetHeight_ : targetWidth_;
    const int32_t outputHeight = swapsDimensions ? targetWidth_ : targetHeight_;
    return isHdrVivid_ ||
        (width_ >= outputWidth && height_ >= outputHeight &&
            (width_ > outputWidth || height_ > outputHeight));
  }

  /**
   * Creates and configures the system decoder for the source codec.
   *
   * @param mime The source track MIME type.
   * @param error Receives the failure description.
   * @return True if decoder setup succeeds; false with an error otherwise.
   */
  bool PrepareDecoder(const char *mime, std::string *error) {
    decoder_ = OH_VideoDecoder_CreateByMime(mime);
    if (decoder_ == nullptr) {
      *error = "当前设备不支持所选视频编码";
      return false;
    }
    const OH_AVCodecCallback callbacks{OnError,
        OnStreamChanged,
        OnNeedInputBuffer,
        OnNewOutputBuffer};
    if (OH_VideoDecoder_RegisterCallback(decoder_, callbacks, this) != AV_ERR_OK ||
        OH_VideoDecoder_Configure(decoder_, trackFormat_) != AV_ERR_OK) {
      *error = "配置 NV12 视频连续解码失败";
      return false;
    }
    if (useSurfaceOutput_ &&
        OH_VideoDecoder_SetSurface(decoder_, surfaceProcessorInputWindow_) != AV_ERR_OK) {
      *error = "绑定视频缩放 Surface 失败";
      return false;
    }
    if (OH_VideoDecoder_Prepare(decoder_) != AV_ERR_OK) {
      *error = "准备 NV12 视频连续解码失败";
      return false;
    }
    return true;
  }

  /** Stops the Surface consumer and wakes its wait loop. */
  void StopSurfaceWorker() {
    {
      // Use the wait predicate's mutex so stop cannot notify between the
      // worker checking an empty queue and actually entering its wait.
      std::lock_guard<std::mutex> queueLock(surfaceQueueMutex_);
      surfaceWorkerRunning_.store(false);
    }
    surfaceCondition_.notify_all();
    if (surfaceWorker_.joinable()) {
      surfaceWorker_.join();
    }
  }

  /**
   * Creates video processing and Surface resources for native decoded frames.
   *
   * @param error Receives the failure description.
   * @return True if output Surface initialization succeeds; false with an error otherwise.
   */
  bool InitializeOutputSurface(std::string *error) {
    const bool swapsDimensions = rotation_ == 90 || rotation_ == 270;
    const int32_t surfaceWidth = swapsDimensions ? targetHeight_ : targetWidth_;
    const int32_t surfaceHeight = swapsDimensions ? targetWidth_ : targetHeight_;
    surfaceOutputSurface_ = OH_ConsumerSurface_Create();
    if (surfaceOutputSurface_ == nullptr) {
      *error = "创建视频输出 Surface 失败";
      return false;
    }
    if (OH_ConsumerSurface_SetDefaultUsage(surfaceOutputSurface_,
            NATIVEBUFFER_USAGE_CPU_READ | NATIVEBUFFER_USAGE_CPU_READ_OFTEN) != 0 ||
        OH_ConsumerSurface_SetDefaultSize(surfaceOutputSurface_, surfaceWidth, surfaceHeight) !=
            0) {
      *error = "配置视频输出 Surface 失败";
      ReleaseOutputSurface();
      return false;
    }
    surfaceOutputWindow_ = OH_NativeImage_AcquireNativeWindow(surfaceOutputSurface_);
    if (surfaceOutputWindow_ == nullptr ||
        OH_NativeWindow_NativeWindowHandleOpt(surfaceOutputWindow_,
            SET_FORMAT,
            NATIVEBUFFER_PIXEL_FMT_YCBCR_420_SP) != 0 ||
        (isHdrVivid_ &&
            OH_NativeWindow_SetColorSpace(surfaceOutputWindow_, OH_COLORSPACE_BT709_LIMIT) != 0)) {
      *error = "配置视频输出格式失败";
      ReleaseOutputSurface();
      return false;
    }
    VideoProcessing_ErrorCode processingResult =
        OH_VideoProcessing_Create(&videoProcessor_, VIDEO_PROCESSING_TYPE_DETAIL_ENHANCER);
    if (processingResult != VIDEO_PROCESSING_SUCCESS || videoProcessor_ == nullptr) {
      *error = "创建视频缩放器失败：" + std::to_string(processingResult);
      ReleaseOutputSurface();
      return false;
    }
    OH_AVFormat *processingParameter = OH_AVFormat_Create();
    if (processingParameter == nullptr ||
        !OH_AVFormat_SetIntValue(processingParameter,
            VIDEO_DETAIL_ENHANCER_PARAMETER_KEY_QUALITY_LEVEL,
            VIDEO_DETAIL_ENHANCER_QUALITY_LEVEL_NONE)) {
      if (processingParameter != nullptr) {
        OH_AVFormat_Destroy(processingParameter);
      }
      *error = "配置视频缩放参数失败";
      ReleaseOutputSurface();
      return false;
    }
    processingResult = OH_VideoProcessing_SetParameter(videoProcessor_, processingParameter);
    OH_AVFormat_Destroy(processingParameter);
    if (processingResult != VIDEO_PROCESSING_SUCCESS ||
        OH_VideoProcessing_GetSurface(videoProcessor_, &surfaceProcessorInputWindow_) !=
            VIDEO_PROCESSING_SUCCESS ||
        surfaceProcessorInputWindow_ == nullptr ||
        OH_NativeWindow_NativeWindowHandleOpt(surfaceProcessorInputWindow_,
            SET_FORMAT,
            NATIVEBUFFER_PIXEL_FMT_YCBCR_420_SP) != 0 ||
        (isHdrVivid_ &&
            OH_NativeWindow_SetColorSpace(surfaceProcessorInputWindow_,
                OH_COLORSPACE_BT709_LIMIT) != 0) ||
        OH_VideoProcessing_SetSurface(videoProcessor_, surfaceOutputWindow_) !=
            VIDEO_PROCESSING_SUCCESS) {
      *error = "连接视频缩放 Surface 失败：" + std::to_string(processingResult);
      ReleaseOutputSurface();
      return false;
    }

    processingResult = OH_VideoProcessingCallback_Create(&surfaceProcessingCallback_);
    if (processingResult != VIDEO_PROCESSING_SUCCESS || surfaceProcessingCallback_ == nullptr ||
        OH_VideoProcessingCallback_BindOnError(surfaceProcessingCallback_,
            OnSurfaceProcessingError) != VIDEO_PROCESSING_SUCCESS ||
        OH_VideoProcessingCallback_BindOnState(surfaceProcessingCallback_,
            OnSurfaceProcessingState) != VIDEO_PROCESSING_SUCCESS ||
        OH_VideoProcessingCallback_BindOnNewOutputBuffer(surfaceProcessingCallback_,
            OnSurfaceProcessingOutputBuffer) != VIDEO_PROCESSING_SUCCESS ||
        OH_VideoProcessing_RegisterCallback(videoProcessor_, surfaceProcessingCallback_, this) !=
            VIDEO_PROCESSING_SUCCESS) {
      *error = "注册视频缩放回调失败：" + std::to_string(processingResult);
      ReleaseOutputSurface();
      return false;
    }
    return true;
  }

  /** Stops the video processor and waits for its stopped-state notification. */
  void StopVideoProcessor() {
    if (!videoProcessorStarted_ || videoProcessor_ == nullptr) {
      return;
    }
    const VideoProcessing_ErrorCode stopResult = OH_VideoProcessing_Stop(videoProcessor_);
    if (stopResult == VIDEO_PROCESSING_SUCCESS) {
      std::unique_lock<std::mutex> lock(surfaceProcessingStateMutex_);
      surfaceProcessingStateCondition_.wait(lock, [this] { return videoProcessorStopped_; });
    }
    videoProcessorStarted_ = false;
  }

  /** Returns pending Surface buffers and releases processing, window, and image resources. */
  void ReleaseOutputSurface() {
    StopVideoProcessor();
    std::lock_guard<std::mutex> surfaceLock(surfaceMutex_);
    if (videoProcessor_ != nullptr) {
      OH_VideoProcessing_Destroy(videoProcessor_);
      videoProcessor_ = nullptr;
    }
    if (surfaceProcessingCallback_ != nullptr) {
      OH_VideoProcessingCallback_Destroy(surfaceProcessingCallback_);
      surfaceProcessingCallback_ = nullptr;
    }
    if (surfaceProcessorInputWindow_ != nullptr) {
      OH_NativeWindow_DestroyNativeWindow(surfaceProcessorInputWindow_);
      surfaceProcessorInputWindow_ = nullptr;
    }
    if (surfaceOutputSurface_ != nullptr) {
      surfaceOutputWindow_ = nullptr;
      OH_NativeImage_Destroy(&surfaceOutputSurface_);
    }
    std::lock_guard<std::mutex> lock(surfaceTimestampMutex_);
    pendingSurfaceTimestamps_.clear();
    surfaceFramesInFlight_ = 0;
    surfaceEndOfStreamPending_ = false;
  }

  /**
   * Registers a video processor output index as a consumable Surface frame.
   *
   * @param index The system buffer index to submit or release.
   * @param context The native decoder bound when registering the processor callback.
   */
  static void OnSurfaceProcessingOutputBuffer(OH_VideoProcessing *, uint32_t index, void *context) {
    auto *decoder = static_cast<NativeVideoFileDecoder *>(context);
    if (decoder != nullptr) {
      decoder->EnqueueSurfaceFrame(index);
    }
  }

  /**
   * Converts a processor error into a decoding failure notification.
   *
   * @param error The native video processor error code.
   * @param context The native decoder bound when registering the processor callback.
   */
  static void OnSurfaceProcessingError(OH_VideoProcessing *,
      VideoProcessing_ErrorCode error,
      void *context) {
    auto *decoder = static_cast<NativeVideoFileDecoder *>(context);
    if (decoder != nullptr) {
      decoder->ReportError("视频缩放失败：" + std::to_string(error));
    }
  }

  /**
   * Records processor state and wakes threads waiting for it to stop.
   *
   * @param state The system video processor state.
   * @param context The native decoder bound when registering the processor callback.
   */
  static void OnSurfaceProcessingState(OH_VideoProcessing *,
      VideoProcessing_State state,
      void *context) {
    auto *decoder = static_cast<NativeVideoFileDecoder *>(context);
    if (decoder == nullptr || state != VIDEO_PROCESSING_STATE_STOPPED) {
      return;
    }
    {
      std::lock_guard<std::mutex> lock(decoder->surfaceProcessingStateMutex_);
      decoder->videoProcessorStopped_ = true;
    }
    decoder->surfaceProcessingStateCondition_.notify_all();
  }

  /**
   * Returns a processor output index to the Surface and wakes the frame consumer.
   *
   * @param index The system buffer index to submit or release.
   */
  void EnqueueSurfaceFrame(uint32_t index) {
    // Explicit output callbacks disable VPE's automatic rendering. The worker
    // must serialize rendering and NativeImage buffer release: doing them on
    // different threads can invert the VPE and NativeImage internal locks.
    {
      std::lock_guard<std::mutex> lock(surfaceQueueMutex_);
      if (!surfaceWorkerRunning_.load()) {
        return;
      }
      surfacePendingOutputBuffers_.push_back(index);
    }
    surfaceCondition_.notify_one();
  }

  /**
   * Acquires a pending Surface buffer and associates its media timestamp.
   *
   * @param packet The packet to consume, deliver, or release.
   * @return True if a buffer was acquired; false if no frame exists or processing stopped.
   */
  bool AcquireSurfaceFrame(SurfaceBufferPacket &packet) {
    std::lock_guard<std::mutex> surfaceLock(surfaceMutex_);
    if (surfaceOutputSurface_ == nullptr) {
      return false;
    }
    OHNativeWindowBuffer *windowBuffer = nullptr;
    int fenceFd = -1;
    if (OH_NativeImage_AcquireNativeWindowBuffer(surfaceOutputSurface_, &windowBuffer, &fenceFd) !=
            0 ||
        windowBuffer == nullptr) {
      if (fenceFd >= 0) {
        close(fenceFd);
      }
      ReportError("读取视频 Surface 帧失败");
      return false;
    }
    if (OH_NativeWindow_NativeObjectReference(windowBuffer) != 0) {
      OH_NativeImage_ReleaseNativeWindowBuffer(surfaceOutputSurface_, windowBuffer, fenceFd);
      ReportError("持有视频 Surface 帧失败");
      return false;
    }
    int64_t timestampUs = 0;
    bool hasTimestamp = false;
    {
      std::lock_guard<std::mutex> lock(surfaceTimestampMutex_);
      if (!pendingSurfaceTimestamps_.empty()) {
        timestampUs = pendingSurfaceTimestamps_.front();
        pendingSurfaceTimestamps_.pop_front();
        ++surfaceFramesInFlight_;
        hasTimestamp = true;
      }
    }
    if (!hasTimestamp) {
      OH_NativeWindow_NativeObjectUnreference(windowBuffer);
      OH_NativeImage_ReleaseNativeWindowBuffer(surfaceOutputSurface_, windowBuffer, fenceFd);
      ReportError("视频 Surface 帧缺少时间戳");
      return false;
    }
    packet = {windowBuffer, fenceFd, timestampUs};
    return true;
  }

  /**
   * Returns a Surface buffer and its fence while holding the Surface access lock.
   *
   * @param packet The packet to consume, deliver, or release.
   */
  void ReleaseSurfaceBufferLocked(const SurfaceBufferPacket &packet) {
    if (packet.windowBuffer == nullptr) {
      if (packet.fenceFd >= 0) {
        close(packet.fenceFd);
      }
      return;
    }
    OH_NativeWindow_NativeObjectUnreference(packet.windowBuffer);
    if (surfaceOutputSurface_ != nullptr) {
      OH_NativeImage_ReleaseNativeWindowBuffer(surfaceOutputSurface_,
          packet.windowBuffer,
          packet.fenceFd);
    } else if (packet.fenceFd >= 0) {
      close(packet.fenceFd);
    }
  }

  /**
   * Consumes the end marker once input and all Surface frames have completed.
   *
   * @return True if the cycle's completion notification can be sent.
   */
  bool ConsumeSurfaceEndOfStreamIfReadyLocked() {
    if (!running_.load() || !surfaceEndOfStreamPending_ || !pendingSurfaceTimestamps_.empty() ||
        surfaceFramesInFlight_ != 0) {
      return false;
    }
    surfaceEndOfStreamPending_ = false;
    return true;
  }

  /** Decrements in-flight Surface work and notifies completion when all frames finish. */
  void CompleteSurfaceFrame() {
    bool dispatchEndOfStream = false;
    {
      std::lock_guard<std::mutex> lock(surfaceTimestampMutex_);
      if (surfaceFramesInFlight_ > 0) {
        --surfaceFramesInFlight_;
      }
      dispatchEndOfStream = ConsumeSurfaceEndOfStreamIfReadyLocked();
    }
    if (dispatchEndOfStream) {
      DispatchEndOfStream();
    }
  }

  /** Delivers file decoding completion to ArkTS. */
  void DispatchEndOfStream() {
    auto *packet = new DecodedFramePacket();
    packet->endOfStream = true;
    Dispatch(packet);
  }

  /** Consumes Surface frames on a dedicated thread, converting and pacing delivery. */
  void SurfaceWorkerLoop() {
    while (true) {
      SurfaceBufferPacket packet;
      uint32_t outputIndex = 0;
      bool dropFrame = false;
      {
        std::unique_lock<std::mutex> lock(surfaceQueueMutex_);
        surfaceCondition_.wait(lock, [this] {
          return !surfaceWorkerRunning_.load() || !surfacePendingOutputBuffers_.empty();
        });
        if (!surfaceWorkerRunning_.load()) {
          // These buffers still belong to VPE and are reclaimed by its Stop.
          surfacePendingOutputBuffers_.clear();
          return;
        }
        outputIndex = surfacePendingOutputBuffers_.front();
        surfacePendingOutputBuffers_.pop_front();
        dropFrame = !surfacePendingOutputBuffers_.empty();
      }
      if (OH_VideoProcessing_RenderOutputBuffer(videoProcessor_, outputIndex) !=
          VIDEO_PROCESSING_SUCCESS) {
        ReportError("输出视频 Surface 帧失败");
        continue;
      }
      if (!AcquireSurfaceFrame(packet)) {
        continue;
      }
      if (dropFrame) {
        std::lock_guard<std::mutex> surfaceLock(surfaceMutex_);
        ReleaseSurfaceBufferLocked(packet);
      } else {
        HandleSurfaceFrame(packet);
      }
      CompleteSurfaceFrame();
    }
  }

  /**
   * Waits for the fence, maps and converts a Surface buffer, then returns native resources.
   *
   * @param packet The packet to consume, deliver, or release.
   */
  void HandleSurfaceFrame(const SurfaceBufferPacket &packet) {
    OHNativeWindowBuffer *windowBuffer = packet.windowBuffer;
    int fenceFd = packet.fenceFd;
    OH_NativeImage *outputSurface = surfaceOutputSurface_;
    const auto releaseWindowBuffer = [this, outputSurface, windowBuffer](int releaseFenceFd) {
      std::lock_guard<std::mutex> surfaceLock(surfaceMutex_);
      OH_NativeWindow_NativeObjectUnreference(windowBuffer);
      OH_NativeImage_ReleaseNativeWindowBuffer(outputSurface, windowBuffer, releaseFenceFd);
    };
    if (!running_.load() || outputSurface == nullptr) {
      if (outputSurface != nullptr) {
        releaseWindowBuffer(fenceFd);
      } else {
        if (fenceFd >= 0) {
          close(fenceFd);
        }
        OH_NativeWindow_NativeObjectUnreference(windowBuffer);
      }
      return;
    }
    if (fenceFd >= 0) {
      pollfd descriptor{fenceFd, POLLIN, 0};
      int waitResult = 0;
      for (int32_t attempt = 0; attempt < 60 && running_.load(); ++attempt) {
        waitResult = poll(&descriptor, 1, 50);
        if (waitResult > 0) {
          break;
        }
      }
      close(fenceFd);
      if (!running_.load()) {
        releaseWindowBuffer(-1);
        return;
      }
      if (waitResult <= 0) {
        releaseWindowBuffer(-1);
        ReportError("等待视频 Surface 帧超时");
        return;
      }
    }
    OH_NativeBuffer *nativeBuffer = nullptr;
    void *address = nullptr;
    OH_NativeBuffer_Planes planes{};
    OH_NativeBuffer_Config config{};
    const bool mapped = OH_NativeBuffer_FromNativeWindowBuffer(windowBuffer, &nativeBuffer) == 0 &&
        nativeBuffer != nullptr &&
        OH_NativeBuffer_MapPlanes(nativeBuffer, &address, &planes) == 0 && address != nullptr;
    if (nativeBuffer != nullptr) {
      OH_NativeBuffer_GetConfig(nativeBuffer, &config);
    }
    if (!mapped || planes.planeCount < 2 || config.format != NATIVEBUFFER_PIXEL_FMT_YCBCR_420_SP ||
        config.width <= 0 || config.height <= 0 || config.stride < config.width) {
      if (mapped) {
        OH_NativeBuffer_Unmap(nativeBuffer);
      }
      releaseWindowBuffer(-1);
      ReportError("访问视频 NV12 帧失败");
      return;
    }
    const auto *bytes = static_cast<const uint8_t *>(address);
    CopyOrRotateNv12(bytes + planes.planes[0].offset,
        config.stride,
        bytes + planes.planes[1].offset,
        config.stride,
        config.width,
        config.height,
        0,
        &surfaceSourceData_);
    OH_NativeBuffer_Unmap(nativeBuffer);
    releaseWindowBuffer(-1);

    const bool swapsDimensions = rotation_ == 90 || rotation_ == 270;
    const int32_t scaledWidth = swapsDimensions ? targetHeight_ : targetWidth_;
    const int32_t scaledHeight = swapsDimensions ? targetWidth_ : targetHeight_;
    const size_t sourceLumaLength = static_cast<size_t>(config.width) * config.height;
    // Usually VPE has already produced the requested size. Only fall back to
    // CPU scaling if the device returns a different actual buffer size.
    std::vector<uint8_t> *scaledData = &surfaceSourceData_;
    if (config.width != scaledWidth || config.height != scaledHeight) {
      ScaleNv12(surfaceSourceData_.data(),
          config.width,
          surfaceSourceData_.data() + sourceLumaLength,
          config.width,
          config.width,
          config.height,
          scaledWidth,
          scaledHeight,
          &surfaceScaledData_);
      scaledData = &surfaceScaledData_;
    }

    std::vector<uint8_t> frameData;
    if (rotation_ == 0) {
      frameData = std::move(*scaledData);
    } else {
      const size_t scaledLumaLength = static_cast<size_t>(scaledWidth) * scaledHeight;
      CopyOrRotateNv12(scaledData->data(),
          scaledWidth,
          scaledData->data() + scaledLumaLength,
          scaledWidth,
          scaledWidth,
          scaledHeight,
          rotation_,
          &frameData);
    }

    auto *outputPacket = new DecodedFramePacket();
    outputPacket->width = targetWidth_;
    outputPacket->height = targetHeight_;
    outputPacket->stride = outputPacket->width;
    outputPacket->timestampUs = packet.timestampUs;
    outputPacket->data = std::move(frameData);
    Dispatch(outputPacket);
  }

  /**
   * Converts a system decoder error into a media failure notification.
   *
   * @param errorCode The system decoder error code.
   * @param userData The native decoder bound when registering the callback.
   */
  static void OnError(OH_AVCodec *, int32_t errorCode, void *userData) {
    auto *decoder = static_cast<NativeVideoFileDecoder *>(userData);
    if (decoder != nullptr) {
      decoder->ReportError("视频解码器错误：" + std::to_string(errorCode));
    }
  }

  /**
   * Updates the output format used to read and convert subsequent frames.
   *
   * @param format The format reported by the system decoder.
   * @param userData The native decoder bound when registering the callback.
   */
  static void OnStreamChanged(OH_AVCodec *, OH_AVFormat *format, void *userData) {
    auto *decoder = static_cast<NativeVideoFileDecoder *>(userData);
    if (decoder == nullptr || format == nullptr) {
      return;
    }
    std::lock_guard<std::mutex> lock(decoder->formatMutex_);
    int32_t value = 0;
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_PIC_WIDTH, &value) ||
        OH_AVFormat_GetIntValue(format, OH_MD_KEY_WIDTH, &value)) {
      decoder->width_ = value;
    }
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_PIC_HEIGHT, &value) ||
        OH_AVFormat_GetIntValue(format, OH_MD_KEY_HEIGHT, &value)) {
      decoder->height_ = value;
    }
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_STRIDE, &value)) {
      decoder->stride_ = value;
    }
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_VIDEO_SLICE_HEIGHT, &value)) {
      decoder->sliceHeight_ = value;
    }
    if (OH_AVFormat_GetIntValue(format, OH_MD_KEY_PIXEL_FORMAT, &value)) {
      decoder->pixelFormat_ = value;
    }
  }

  /**
   * Reads compressed track data into the requested decoder input buffer.
   *
   * @param codec The system decoder requesting or delivering buffers.
   * @param index The system buffer index to submit or release.
   * @param buffer The media buffer supplied by the system decoder.
   * @param userData The native decoder bound when registering the callback.
   */
  static void OnNeedInputBuffer(OH_AVCodec *codec,
      uint32_t index,
      OH_AVBuffer *buffer,
      void *userData) {
    auto *decoder = static_cast<NativeVideoFileDecoder *>(userData);
    if (decoder == nullptr || !decoder->running_.load() || buffer == nullptr) {
      return;
    }
    if (!decoder->WaitUntilPlaying()) {
      return;
    }

    OH_AVErrCode readResult = AV_ERR_OK;
    OH_AVErrCode pushResult = AV_ERR_OK;
    OH_AVErrCode attributeResult = AV_ERR_OK;
    int64_t loopIndex = 0;
    {
      std::lock_guard<std::mutex> lock(decoder->demuxerMutex_);
      if (!decoder->running_.load() || decoder->inputEnded_) {
        return;
      }
      readResult = OH_AVDemuxer_ReadSampleBuffer(decoder->demuxer_, decoder->trackIndex_, buffer);
      if (readResult == AV_ERR_OK) {
        OH_AVCodecBufferAttr attr{};
        attributeResult = OH_AVBuffer_GetBufferAttr(buffer, &attr);
        bool endOfStream =
            attributeResult == AV_ERR_OK && (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0;
        if (decoder->isHdrVivid_ && endOfStream && decoder->cycleDurationUs_ > 0 &&
            OH_AVDemuxer_SeekToTime(decoder->demuxer_, 0, SEEK_MODE_PREVIOUS_SYNC) == AV_ERR_OK) {
          readResult =
              OH_AVDemuxer_ReadSampleBuffer(decoder->demuxer_, decoder->trackIndex_, buffer);
          if (readResult == AV_ERR_OK) {
            attributeResult = OH_AVBuffer_GetBufferAttr(buffer, &attr);
            endOfStream =
                attributeResult == AV_ERR_OK && (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0;
            if (attributeResult == AV_ERR_OK && !endOfStream) {
              ++decoder->inputLoopIndex_;
            }
          }
        }
        if (readResult == AV_ERR_OK) {
          loopIndex = decoder->inputLoopIndex_;
          if (decoder->isHdrVivid_ && attributeResult == AV_ERR_OK && !endOfStream &&
              loopIndex > 0) {
            attr.pts += loopIndex * decoder->cycleDurationUs_;
            attributeResult = OH_AVBuffer_SetBufferAttr(buffer, &attr);
          }
          pushResult = OH_VideoDecoder_PushInputBuffer(codec, index);
          if (pushResult == AV_ERR_OK) {
            decoder->inputEnded_ = endOfStream;
          }
        }
      }
    }
    if (readResult != AV_ERR_OK) {
      decoder->ReportError("读取视频压缩帧失败：" + std::to_string(readResult));
      return;
    }
    if (attributeResult != AV_ERR_OK) {
      decoder->ReportError("更新 HDR Vivid 循环帧时间戳失败：" + std::to_string(attributeResult));
      return;
    }
    if (pushResult != AV_ERR_OK) {
      decoder->ReportError("提交视频压缩帧失败：" + std::to_string(pushResult));
    }
  }

  /**
   * Processes a decoded buffer and releases its output index afterward.
   *
   * @param codec The system decoder requesting or delivering buffers.
   * @param index The system buffer index to submit or release.
   * @param buffer The media buffer supplied by the system decoder.
   * @param userData The native decoder bound when registering the callback.
   */
  static void OnNewOutputBuffer(OH_AVCodec *codec,
      uint32_t index,
      OH_AVBuffer *buffer,
      void *userData) {
    auto *decoder = static_cast<NativeVideoFileDecoder *>(userData);
    if (decoder == nullptr) {
      if (codec != nullptr) {
        OH_VideoDecoder_FreeOutputBuffer(codec, index);
      }
      return;
    }
    if (decoder->useSurfaceOutput_) {
      decoder->HandleSurfaceOutputBuffer(codec, index, buffer);
      return;
    }
    if (buffer == nullptr) {
      OH_VideoDecoder_FreeOutputBuffer(codec, index);
      return;
    }
    decoder->HandleOutputBuffer(buffer);
    OH_VideoDecoder_FreeOutputBuffer(codec, index);
  }

  /**
   * Submits decoded output to Surface processing with frame time and end markers.
   *
   * @param codec The system decoder requesting or delivering buffers.
   * @param index The system buffer index to submit or release.
   * @param buffer The media buffer supplied by the system decoder.
   */
  void HandleSurfaceOutputBuffer(OH_AVCodec *codec, uint32_t index, OH_AVBuffer *buffer) {
    if (!running_.load() || codec == nullptr || buffer == nullptr) {
      if (codec != nullptr) {
        OH_VideoDecoder_FreeOutputBuffer(codec, index);
      }
      return;
    }
    OH_AVCodecBufferAttr attr{};
    if (OH_AVBuffer_GetBufferAttr(buffer, &attr) != AV_ERR_OK) {
      OH_VideoDecoder_FreeOutputBuffer(codec, index);
      ReportError("读取视频解码帧属性失败");
      return;
    }
    if ((attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0) {
      OH_VideoDecoder_FreeOutputBuffer(codec, index);
      bool dispatchEndOfStream = false;
      {
        std::lock_guard<std::mutex> lock(surfaceTimestampMutex_);
        surfaceEndOfStreamPending_ = true;
        dispatchEndOfStream = ConsumeSurfaceEndOfStreamIfReadyLocked();
      }
      if (dispatchEndOfStream) {
        DispatchEndOfStream();
      }
      return;
    }
    if (!ShouldOutputFrame(attr.pts)) {
      OH_VideoDecoder_FreeOutputBuffer(codec, index);
      return;
    }

    Pace(attr.pts);
    if (!running_.load()) {
      OH_VideoDecoder_FreeOutputBuffer(codec, index);
      return;
    }
    const int64_t timestampUs = PlaybackTimestampUs(attr.pts);
    {
      std::lock_guard<std::mutex> lock(surfaceTimestampMutex_);
      pendingSurfaceTimestamps_.push_back(timestampUs);
    }
    if (OH_VideoDecoder_RenderOutputBuffer(codec, index) != AV_ERR_OK) {
      {
        std::lock_guard<std::mutex> lock(surfaceTimestampMutex_);
        if (!pendingSurfaceTimestamps_.empty() && pendingSurfaceTimestamps_.back() == timestampUs) {
          pendingSurfaceTimestamps_.pop_back();
        }
      }
      ReportError("渲染视频 Surface 帧失败");
    }
  }

  /**
   * Reads decoded data and timestamps, then converts and delivers paced media frames.
   *
   * @param buffer The media buffer supplied by the system decoder.
   */
  void HandleOutputBuffer(OH_AVBuffer *buffer) {
    if (!running_.load()) {
      return;
    }
    OH_AVCodecBufferAttr attr{};
    if (OH_AVBuffer_GetBufferAttr(buffer, &attr) != AV_ERR_OK) {
      ReportError("读取解码视频帧属性失败");
      return;
    }
    if ((attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0) {
      auto *packet = new DecodedFramePacket();
      packet->endOfStream = true;
      Dispatch(packet);
      return;
    }
    if (attr.size <= 0 || attr.offset < 0) {
      return;
    }
    if (!ShouldOutputFrame(attr.pts)) {
      return;
    }

    int32_t width = 0;
    int32_t height = 0;
    int32_t stride = 0;
    int32_t sliceHeight = 0;
    int32_t pixelFormat = 0;
    {
      std::lock_guard<std::mutex> lock(formatMutex_);
      width = width_;
      height = height_;
      stride = stride_;
      sliceHeight = sliceHeight_;
      pixelFormat = pixelFormat_;
    }
    if (pixelFormat != AV_PIXEL_FORMAT_NV12 || width <= 0 || height <= 0) {
      ReportError("视频解码器未输出 NV12 帧");
      return;
    }
    if (stride < width) {
      ReportError("NV12 视频解码帧宽跨距无效");
      return;
    }
    if (sliceHeight < height) {
      sliceHeight = height;
    }
    const size_t sourceLength =
        static_cast<size_t>(stride) * static_cast<size_t>(sliceHeight + height / 2);
    if (sourceLength > static_cast<size_t>(attr.size)) {
      ReportError("NV12 视频解码帧布局无效");
      return;
    }

    uint8_t *address = OH_AVBuffer_GetAddr(buffer);
    const int32_t capacity = OH_AVBuffer_GetCapacity(buffer);
    if (address == nullptr || capacity < 0 ||
        static_cast<int64_t>(attr.offset) + static_cast<int64_t>(sourceLength) > capacity) {
      ReportError("访问 NV12 视频解码帧失败");
      return;
    }

    Pace(attr.pts);
    if (!running_.load()) {
      return;
    }
    std::vector<uint8_t> frameData;
    ScaleAndRotateNv12(address + attr.offset,
        stride,
        address + attr.offset + static_cast<size_t>(stride) * sliceHeight,
        stride,
        width,
        height,
        rotation_,
        targetWidth_,
        targetHeight_,
        &frameData);

    auto *packet = new DecodedFramePacket();
    packet->width = targetWidth_;
    packet->height = targetHeight_;
    packet->stride = packet->width;
    packet->timestampUs = PlaybackTimestampUs(attr.pts);
    packet->data = std::move(frameData);
    Dispatch(packet);
  }

  /**
   * Waits for playback time while responding to pause and stop requests.
   *
   * @param timestampUs The output media timestamp, in microseconds.
   */
  void Pace(int64_t timestampUs) {
    std::unique_lock<std::mutex> lock(pacingMutex_);
    while (running_.load()) {
      pacingCondition_.wait(lock, [this] { return !running_.load() || !paused_.load(); });
      if (!running_.load()) {
        return;
      }
      const auto deadline = std::chrono::steady_clock::time_point(
          std::chrono::microseconds(PlaybackTimestampUs(timestampUs)));
      if (!pacingCondition_.wait_until(lock, deadline, [this] {
            return !running_.load() || paused_.load();
          })) {
        return;
      }
    }
  }

  /**
   * Waits until playback resumes or stops.
   *
   * @return True while running and permitted to play; false after stopping.
   */
  bool WaitUntilPlaying() {
    std::unique_lock<std::mutex> lock(pacingMutex_);
    pacingCondition_.wait(lock, [this] { return !running_.load() || !paused_.load(); });
    return running_.load();
  }

  /**
   * Filters video output by the target interval to avoid duplicate or excessive timestamps.
   *
   * @param mediaTimestampUs The source media timestamp, in microseconds.
   * @return True if the media timestamp should be output.
   */
  bool ShouldOutputFrame(int64_t mediaTimestampUs) {
    if (lastOutputMediaTimestampUs_ >= 0 &&
        mediaTimestampUs - lastOutputMediaTimestampUs_ < frameIntervalUs_ * 3 / 4) {
      return false;
    }
    lastOutputMediaTimestampUs_ = mediaTimestampUs;
    return true;
  }

  /**
   * Maps media time to monotonic playback time with pause compensation.
   *
   * @param mediaTimestampUs The source media timestamp, in microseconds.
   * @return The playback timestamp, in microseconds.
   */
  int64_t PlaybackTimestampUs(int64_t mediaTimestampUs) const {
    return playbackAnchorUs_.load() + std::max<int64_t>(mediaTimestampUs - mediaStartUs_, 0);
  }

  /**
   * Reports a media processing error once.
   *
   * @param message The failure description to deliver or log.
   */
  void ReportError(const std::string &message) {
    if (reportedError_.exchange(true)) {
      return;
    }
    auto *packet = new DecodedFramePacket();
    packet->error = message;
    Dispatch(packet);
  }

  /**
   * Queues a packet for ArkTS delivery, releasing it if submission fails.
   *
   * @param packet The packet to consume, deliver, or release.
   */
  void Dispatch(DecodedFramePacket *packet) {
    if (listener_ == nullptr ||
        napi_call_threadsafe_function(listener_, packet, napi_tsfn_blocking) != napi_ok) {
      delete packet;
    }
  }

  /**
   * Releases a native video packet when its ArkTS external buffer is collected.
   *
   * @param hint The packet associated with the external frame buffer.
   */
  static void FinalizeFrameData(napi_env, void *, void *hint) {
    delete static_cast<std::vector<uint8_t> *>(hint);
  }

  /**
   * Delivers media or status on the ArkTS thread and transfers or releases packet ownership.
   *
   * @param env The current ArkTS N-API environment.
   * @param callback The function to invoke on the ArkTS thread.
   * @param data The associated packet or asynchronous work context.
   */
  static void CallListener(napi_env env, napi_value callback, void *, void *data) {
    auto *packet = static_cast<DecodedFramePacket *>(data);
    if (packet == nullptr) {
      return;
    }
    if (env == nullptr || callback == nullptr) {
      delete packet;
      return;
    }

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    napi_value arguments[7] =
        {undefined, undefined, undefined, undefined, undefined, undefined, undefined};
    if (!packet->data.empty()) {
      auto *frameData = new std::vector<uint8_t>(std::move(packet->data));
      if (napi_create_external_arraybuffer(env,
              frameData->data(),
              frameData->size(),
              FinalizeFrameData,
              frameData,
              &arguments[0]) != napi_ok) {
        delete frameData;
        delete packet;
        return;
      }
    }
    napi_create_int32(env, packet->width, &arguments[1]);
    napi_create_int32(env, packet->height, &arguments[2]);
    napi_create_int32(env, packet->stride, &arguments[3]);
    napi_create_double(env, static_cast<double>(packet->timestampUs), &arguments[4]);
    napi_get_boolean(env, packet->endOfStream, &arguments[5]);
    if (!packet->error.empty()) {
      napi_create_string_utf8(env, packet->error.c_str(), NAPI_AUTO_LENGTH, &arguments[6]);
    }

    napi_value result = nullptr;
    napi_call_function(env,
        undefined,
        callback,
        sizeof(arguments) / sizeof(arguments[0]),
        arguments,
        &result);
    delete packet;
  }

  // File, demuxer, and video decoder resources

  /** The duplicated file descriptor owned by the decoder. */
  int32_t fd_ = -1;

  /** The owned native media source. */
  OH_AVSource *source_ = nullptr;

  /** The demuxer reading compressed track samples. */
  OH_AVDemuxer *demuxer_ = nullptr;

  /** The native file decoder for the current playback cycle. */
  OH_AVCodec *decoder_ = nullptr;

  /** The selected media track format. */
  OH_AVFormat *trackFormat_ = nullptr;

  /** The selected media track index. */
  uint32_t trackIndex_ = 0;

  // ArkTS frame and status delivery

  /** The currently installed event handler. */
  napi_threadsafe_function listener_ = nullptr;

  // Run, pause, and error notification state
  std::atomic<bool> running_{false};
  std::atomic<bool> paused_{false};
  std::atomic<bool> reportedError_{false};

  // Input reading and demuxer synchronization

  /** The lock serializing demuxer reads and seeks. */
  std::mutex demuxerMutex_;

  /** Whether compressed input has reached its end. */
  bool inputEnded_ = false;

  // Decoder format and pixel layout synchronization

  /** The lock protecting decoder output format and layout. */
  std::mutex formatMutex_;

  /** The image or frame width. */
  int32_t width_ = 0;

  /** The image or frame height. */
  int32_t height_ = 0;

  /** The plane row stride, in bytes. */
  int32_t stride_ = 0;

  /** The decoder buffer height including alignment padding. */
  int32_t sliceHeight_ = 0;

  /** The pixel layout used by the frame buffer. */
  int32_t pixelFormat_ = 0;

  // Surface output selection

  /** Whether the selected video track uses HDR Vivid. */
  bool isHdrVivid_ = false;

  /** Whether decoding uses Surface output rather than byte buffers. */
  bool useSurfaceOutput_ = false;

  // Video processor and input window

  /** The processor converting decoded Surface frames for output. */
  OH_VideoProcessing *videoProcessor_ = nullptr;

  /** The video processor callback registration resource. */
  VideoProcessing_Callback *surfaceProcessingCallback_ = nullptr;

  /** The input window receiving decoded frames for processing. */
  OHNativeWindow *surfaceProcessorInputWindow_ = nullptr;

  /** Whether the video processor has started. */
  bool videoProcessorStarted_ = false;

  /** Whether the processor's stopped-state event has arrived. */
  bool videoProcessorStopped_ = true;

  // Video processor stop synchronization

  /** The lock protecting processor stop state. */
  std::mutex surfaceProcessingStateMutex_;

  /** The condition waiting for processor state changes. */
  std::condition_variable surfaceProcessingStateCondition_;

  // Output Surface and native window

  /** The processed output Surface resource. */
  OH_NativeImage *surfaceOutputSurface_ = nullptr;

  /** The native window receiving processed output buffers. */
  OHNativeWindow *surfaceOutputWindow_ = nullptr;

  // Surface resource and frame queue synchronization

  /** The lock protecting native Surface access and resource release. */
  std::mutex surfaceMutex_;

  /** The lock protecting pending Surface buffers. */
  std::mutex surfaceQueueMutex_;

  /** The condition waking the Surface consumer. */
  std::condition_variable surfaceCondition_;

  // Pending output buffers

  /** The processed output indices awaiting Surface consumption. */
  std::deque<uint32_t> surfacePendingOutputBuffers_;

  // Surface consumer thread
  std::atomic<bool> surfaceWorkerRunning_{false};

  /** The worker consuming processed Surface frames. */
  std::thread surfaceWorker_;

  // Frame timestamp and completion synchronization

  /** The lock protecting timestamp and completion accounting. */
  std::mutex surfaceTimestampMutex_;

  /** The media timestamps awaiting processed Surface output. */
  std::deque<int64_t> pendingSurfaceTimestamps_;

  /** The Surface frames still being processed before completion. */
  size_t surfaceFramesInFlight_ = 0;

  /** Whether end-of-stream awaits completion of pending Surface work. */
  bool surfaceEndOfStreamPending_ = false;

  // Surface pixel conversion cache

  /** The reusable pixels copied from a decoded Surface buffer. */
  std::vector<uint8_t> surfaceSourceData_;

  /** The reusable scaled Surface pixel buffer. */
  std::vector<uint8_t> surfaceScaledData_;

  // Pause and playback pacing synchronization

  /** The lock protecting playback pacing waits. */
  std::mutex pacingMutex_;

  /** The condition waking playback pacing on pause, resume, or stop. */
  std::condition_variable pacingCondition_;

  // Media timeline and output sampling format
  std::atomic<int64_t> playbackAnchorUs_{0};

  /** The source media timeline origin, in microseconds. */
  int64_t mediaStartUs_ = 0;

  /** The clockwise video rotation. */
  int32_t rotation_ = 0;

  /** The target frame width, in pixels. */
  int32_t targetWidth_ = 0;

  /** The target frame height, in pixels. */
  int32_t targetHeight_ = 0;

  /** The target output frame interval, in microseconds. */
  int64_t frameIntervalUs_ = 0;

  /** The duration of one playback cycle, in microseconds. */
  int64_t cycleDurationUs_ = 0;

  // File cycle and output frame deduplication

  /** The decoder input cycle used for timestamp continuity. */
  int64_t inputLoopIndex_ = 0;

  /** The last output media timestamp, in microseconds. */
  int64_t lastOutputMediaTimestampUs_ = -1;
};

/**
 * Reads the native file decoder bound to an ArkTS object.
 *
 * @param env The current ArkTS N-API environment.
 * @param info The ArkTS invocation arguments and receiver.
 * @param receiver Optionally receives the ArkTS method receiver.
 * @return The decoder, or a null pointer with an ArkTS exception on invalid invocation.
 */
NativeVideoFileDecoder *UnwrapDecoder(napi_env env,
    napi_callback_info info,
    napi_value *receiver = nullptr) {
  size_t argumentCount = 0;
  napi_value thisValue = nullptr;
  if (napi_get_cb_info(env, info, &argumentCount, nullptr, &thisValue, nullptr) != napi_ok) {
    return nullptr;
  }
  NativeVideoFileDecoder *decoder = nullptr;
  if (napi_unwrap(env, thisValue, reinterpret_cast<void **>(&decoder)) != napi_ok) {
    return nullptr;
  }
  if (receiver != nullptr) {
    *receiver = thisValue;
  }
  return decoder;
}

/**
 * Forwards an ArkTS pause request to the native file decoder.
 *
 * @param env The current ArkTS N-API environment.
 * @param info The ArkTS invocation arguments and receiver.
 * @return ArkTS undefined。
 */
napi_value PauseDecoder(napi_env env, napi_callback_info info) {
  NativeVideoFileDecoder *decoder = UnwrapDecoder(env, info);
  if (decoder == nullptr) {
    napi_throw_error(env, nullptr, "Video decoder is unavailable");
    return nullptr;
  }
  decoder->Pause();
  napi_value result = nullptr;
  napi_get_undefined(env, &result);
  return result;
}

/**
 * Reads the pause duration and resumes native decoding.
 *
 * @param env The current ArkTS N-API environment.
 * @param info The ArkTS invocation arguments and receiver.
 * @return ArkTS undefined; invalid arguments produce an exception.
 */
napi_value ResumeDecoder(napi_env env, napi_callback_info info) {
  size_t argumentCount = 1;
  napi_value argument = nullptr;
  napi_value receiver = nullptr;
  if (napi_get_cb_info(env, info, &argumentCount, &argument, &receiver, nullptr) != napi_ok ||
      argumentCount != 1) {
    napi_throw_type_error(env, nullptr, "Expected paused duration");
    return nullptr;
  }
  NativeVideoFileDecoder *decoder = nullptr;
  double pausedDurationUs = 0;
  if (napi_unwrap(env, receiver, reinterpret_cast<void **>(&decoder)) != napi_ok ||
      decoder == nullptr || napi_get_value_double(env, argument, &pausedDurationUs) != napi_ok ||
      pausedDurationUs < 0) {
    napi_throw_type_error(env, nullptr, "Video decoder resume arguments are invalid");
    return nullptr;
  }
  decoder->Resume(static_cast<int64_t>(pausedDurationUs));
  napi_value result = nullptr;
  napi_get_undefined(env, &result);
  return result;
}

/** Native decoder release work with its Promise and instance reference. */
struct ReleaseDecoderContext {

  // Asynchronous work and release notification

  /** The N-API asynchronous work handle. */
  napi_async_work work = nullptr;

  /** The N-API handle completing the ArkTS Promise. */
  napi_deferred deferred = nullptr;

  // ArkTS wrapper and native instance ownership

  /** The ArkTS object reference retaining the decoder during asynchronous work. */
  napi_ref decoderReference = nullptr;

  /** The native file decoder for the current playback cycle. */
  NativeVideoFileDecoder *decoder = nullptr;
};

/**
 * Rejects a pending ArkTS Promise with the native decoding failure.
 *
 * @param env The current ArkTS N-API environment.
 * @param deferred The ArkTS Promise to fulfill or reject.
 * @param reason The readable Promise rejection reason.
 */
void RejectDecoderPromise(napi_env env, napi_deferred deferred, const char *reason) {
  napi_value message = nullptr;
  napi_value error = nullptr;
  napi_create_string_utf8(env, reason, NAPI_AUTO_LENGTH, &message);
  napi_create_error(env, nullptr, message, &error);
  napi_reject_deferred(env, deferred, error);
}

/**
 * Stops video decoding on a worker without blocking the ArkTS event loop.
 *
 * @param data The associated packet or asynchronous work context.
 */
void ExecuteReleaseDecoder(napi_env, void *data) {
  auto *context = static_cast<ReleaseDecoderContext *>(data);
  if (context != nullptr && context->decoder != nullptr) {
    context->decoder->Stop();
  }
}

/**
 * Completes release on the ArkTS thread and clears work and instance references.
 *
 * @param env The current ArkTS N-API environment.
 * @param status The N-API work completion status.
 * @param data The associated packet or asynchronous work context.
 */
void CompleteReleaseDecoder(napi_env env, napi_status status, void *data) {
  auto *context = static_cast<ReleaseDecoderContext *>(data);
  if (context == nullptr) {
    return;
  }
  napi_value result = nullptr;
  if (status == napi_ok) {
    napi_get_undefined(env, &result);
    napi_resolve_deferred(env, context->deferred, result);
  } else {
    RejectDecoderPromise(env,
        context->deferred,
        "Failed to release the video decoder asynchronously");
  }
  if (context->decoderReference != nullptr) {
    napi_delete_reference(env, context->decoderReference);
  }
  if (context->work != nullptr) {
    napi_delete_async_work(env, context->work);
  }
  delete context;
}

/**
 * Deletes the native decoder and releases media resources when its ArkTS wrapper is collected.
 *
 * @param data The associated packet or asynchronous work context.
 */
void FinalizeDecoder(napi_env, void *data, void *) {
  delete static_cast<NativeVideoFileDecoder *>(data);
}

/**
 * Releases the native file decoder bound to an ArkTS object.
 *
 * @param env The current ArkTS N-API environment.
 * @param info The ArkTS invocation arguments and receiver.
 * @return The ArkTS Promise fulfilled after resource release.
 */
napi_value ReleaseDecoder(napi_env env, napi_callback_info info) {
  napi_value receiver = nullptr;
  NativeVideoFileDecoder *decoder = UnwrapDecoder(env, info, &receiver);
  if (decoder == nullptr || receiver == nullptr) {
    napi_throw_error(env, nullptr, "Video decoder is unavailable");
    return nullptr;
  }

  napi_value promise = nullptr;
  auto *context = new ReleaseDecoderContext();
  context->decoder = decoder;
  if (napi_create_reference(env, receiver, 1, &context->decoderReference) != napi_ok ||
      napi_create_promise(env, &context->deferred, &promise) != napi_ok) {
    if (context->decoderReference != nullptr) {
      napi_delete_reference(env, context->decoderReference);
    }
    delete context;
    napi_throw_error(env, nullptr, "Failed to prepare video decoder release");
    return nullptr;
  }

  napi_value resourceName = nullptr;
  if (napi_create_string_utf8(env,
          "XmaxReleaseNativeVideoFileDecoder",
          NAPI_AUTO_LENGTH,
          &resourceName) != napi_ok ||
      napi_create_async_work(env,
          nullptr,
          resourceName,
          ExecuteReleaseDecoder,
          CompleteReleaseDecoder,
          context,
          &context->work) != napi_ok ||
      napi_queue_async_work(env, context->work) != napi_ok) {
    if (context->work != nullptr) {
      napi_delete_async_work(env, context->work);
    }
    RejectDecoderPromise(env, context->deferred, "Failed to queue video decoder release");
    napi_delete_reference(env, context->decoderReference);
    delete context;
    return promise;
  }
  return promise;
}

/** Native decoder initialization arguments, result, and ArkTS notification resources. */
struct CreateDecoderContext {

  // Asynchronous work and creation notification

  /** The N-API asynchronous work handle. */
  napi_async_work work = nullptr;

  /** The N-API handle completing the ArkTS Promise. */
  napi_deferred deferred = nullptr;

  // ArkTS wrapper and native instance ownership

  /** The ArkTS reference retained for native asynchronous work. */
  napi_ref reference = nullptr;

  /** The native file decoder for the current playback cycle. */
  NativeVideoFileDecoder *decoder = nullptr;

  // Source file and playback time configuration

  /** The frame dimensions carried by the request. */
  int64_t size = 0;

  /** The monotonic playback anchor, in microseconds. */
  int64_t anchorUs = 0;

  /** The source media timeline origin, in microseconds. */
  int64_t mediaStartUs = 0;

  // Target video format and frame interval

  /** The clockwise video rotation. */
  int32_t rotation = 0;

  /** The image or frame width. */
  int32_t width = 0;

  /** The image or frame height. */
  int32_t height = 0;

  /** The target output frame interval, in microseconds. */
  int64_t frameIntervalUs = 0;

  /** The duration of one playback cycle, in microseconds. */
  int64_t cycleDurationUs = 0;

  // Background initialization error

  /** The media processing failure description, if any. */
  std::string error;
};

/**
 * Initializes the system decoder on a worker and retains its result or error.
 *
 * @param data The associated packet or asynchronous work context.
 */
void ExecuteCreateDecoder(napi_env, void *data) {
  auto *context = static_cast<CreateDecoderContext *>(data);
  if (!context->decoder->Initialize(context->size,
          context->anchorUs,
          context->mediaStartUs,
          context->rotation,
          context->width,
          context->height,
          context->frameIntervalUs,
          context->cycleDurationUs,
          &context->error)) {
    // Failed initialization may own codec/Surface resources: release them here,
    // not in the completion callback on the UI thread.
    context->decoder->Stop();
  }
}

/**
 * Completes decoder creation on the ArkTS thread and releases the work context.
 *
 * @param env The current ArkTS N-API environment.
 * @param status The N-API work completion status.
 * @param data The associated packet or asynchronous work context.
 */
void CompleteCreateDecoder(napi_env env, napi_status status, void *data) {
  auto *context = static_cast<CreateDecoderContext *>(data);
  if (status != napi_ok || !context->error.empty()) {
    RejectDecoderPromise(env,
        context->deferred,
        context->error.empty() ? "Failed to initialize the video decoder asynchronously"
                               : context->error.c_str());
  } else {
    napi_value result = nullptr;
    napi_get_reference_value(env, context->reference, &result);
    napi_resolve_deferred(env, context->deferred, result);
  }
  napi_delete_reference(env, context->reference);
  napi_delete_async_work(env, context->work);
  delete context;
}

/**
 * Validates file and playback parameters and returns asynchronous decoder initialization.
 *
 * @param env The current ArkTS N-API environment.
 * @param info The ArkTS invocation arguments and receiver.
 * @return The Promise for an initially paused decoder; initialization failures reject it.
 */
napi_value CreateVideoFileDecoder(napi_env env, napi_callback_info info) {
  size_t argumentCount = 10;
  napi_value arguments[10] =
      {nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr};
  if (napi_get_cb_info(env, info, &argumentCount, arguments, nullptr, nullptr) != napi_ok ||
      argumentCount != 10) {
    napi_throw_type_error(env,
        nullptr,
        "Expected fd, size, playback timing, output format and frame listener");
    return nullptr;
  }

  int32_t fd = -1;
  double sizeValue = 0;
  double playbackAnchorUs = 0;
  double mediaStartUs = 0;
  int32_t rotation = 0;
  int32_t targetWidth = 0;
  int32_t targetHeight = 0;
  double frameIntervalUs = 0;
  double cycleDurationUs = 0;
  napi_valuetype listenerType = napi_undefined;
  if (napi_get_value_int32(env, arguments[0], &fd) != napi_ok ||
      napi_get_value_double(env, arguments[1], &sizeValue) != napi_ok ||
      napi_get_value_double(env, arguments[2], &playbackAnchorUs) != napi_ok ||
      napi_get_value_double(env, arguments[3], &mediaStartUs) != napi_ok ||
      napi_get_value_int32(env, arguments[4], &rotation) != napi_ok ||
      napi_get_value_int32(env, arguments[5], &targetWidth) != napi_ok ||
      napi_get_value_int32(env, arguments[6], &targetHeight) != napi_ok ||
      napi_get_value_double(env, arguments[7], &frameIntervalUs) != napi_ok ||
      napi_get_value_double(env, arguments[8], &cycleDurationUs) != napi_ok || fd < 0 ||
      sizeValue <= 0 || playbackAnchorUs <= 0 || targetWidth <= 0 || targetHeight <= 0 ||
      targetWidth % 2 != 0 || targetHeight % 2 != 0 || frameIntervalUs <= 0 ||
      cycleDurationUs <= 0 || !IsSupportedRotation(rotation) ||
      napi_typeof(env, arguments[9], &listenerType) != napi_ok || listenerType != napi_function) {
    napi_throw_type_error(env, nullptr, "Video file decoder arguments are invalid");
    return nullptr;
  }

  auto *decoder = new NativeVideoFileDecoder();
  std::string error;
  if (!decoder->Bind(env, arguments[9], fd, &error)) {
    delete decoder;
    napi_throw_error(env, nullptr, error.c_str());
    return nullptr;
  }

  napi_value result = nullptr;
  if (napi_create_object(env, &result) != napi_ok) {
    delete decoder;
    napi_throw_error(env, nullptr, "Failed to create video decoder handle");
    return nullptr;
  }
  napi_property_descriptor descriptors[] = {
      {"pause", nullptr, PauseDecoder, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"resume", nullptr, ResumeDecoder, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"release", nullptr, ReleaseDecoder, nullptr, nullptr, nullptr, napi_default, nullptr}};
  if (napi_define_properties(env,
          result,
          sizeof(descriptors) / sizeof(descriptors[0]),
          descriptors) != napi_ok ||
      napi_wrap(env, result, decoder, FinalizeDecoder, nullptr, nullptr) != napi_ok) {
    delete decoder;
    napi_throw_error(env, nullptr, "Failed to bind video decoder handle");
    return nullptr;
  }

  auto *context = new CreateDecoderContext();
  context->decoder = decoder;
  context->size = static_cast<int64_t>(sizeValue);
  context->anchorUs = static_cast<int64_t>(playbackAnchorUs);
  context->mediaStartUs = static_cast<int64_t>(mediaStartUs);
  context->rotation = rotation;
  context->width = targetWidth;
  context->height = targetHeight;
  context->frameIntervalUs = static_cast<int64_t>(frameIntervalUs);
  context->cycleDurationUs = static_cast<int64_t>(cycleDurationUs);
  napi_value promise = nullptr;
  napi_value resourceName = nullptr;
  if (napi_create_promise(env, &context->deferred, &promise) != napi_ok) {
    decoder->Stop();
    delete context;
    napi_throw_error(env, nullptr, "Failed to create video initialization promise");
    return nullptr;
  }
  if (napi_create_reference(env, result, 1, &context->reference) != napi_ok ||
      napi_create_string_utf8(env,
          "XmaxCreateNativeVideoFileDecoder",
          NAPI_AUTO_LENGTH,
          &resourceName) != napi_ok ||
      napi_create_async_work(env,
          nullptr,
          resourceName,
          ExecuteCreateDecoder,
          CompleteCreateDecoder,
          context,
          &context->work) != napi_ok ||
      napi_queue_async_work(env, context->work) != napi_ok) {
    // The worker has not run: only the lightweight binding/fd exist here.
    decoder->Stop();
    RejectDecoderPromise(env, context->deferred, "Failed to queue video initialization");
    if (context->reference != nullptr)
      napi_delete_reference(env, context->reference);
    if (context->work != nullptr)
      napi_delete_async_work(env, context->work);
    delete context;
  }
  return promise;
}
} // namespace

namespace xmax {

/**
 * Exports asynchronous native video decoder creation.
 *
 * @param env The current ArkTS N-API environment.
 * @param exports The module object receiving SDK native exports.
 */
void DefineNativeVideoFileDecoder(napi_env env, napi_value exports) {
  napi_property_descriptor descriptor = {"createVideoFileDecoder",
      nullptr,
      CreateVideoFileDecoder,
      nullptr,
      nullptr,
      nullptr,
      napi_default,
      nullptr};
  napi_define_properties(env, exports, 1, &descriptor);
}
} // namespace xmax
