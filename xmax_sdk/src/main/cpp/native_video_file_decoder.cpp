//
//  native_video_file_decoder.cpp
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
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
/**
 * 携带 NV12 视频帧、图像布局、时间戳和结束或错误通知。
 */
struct DecodedFramePacket {

  /** NV12 像素数据与布局 */
  std::vector<uint8_t> data;
  int32_t width = 0;
  int32_t height = 0;
  int32_t stride = 0;

  /** 播放时间与结束、错误通知 */
  int64_t timestampUs = 0;
  bool endOfStream = false;
  std::string error;
};

/**
 * 记录待消费的解码 Surface 缓冲区、同步栅栏和时间戳。
 */
struct SurfaceBufferPacket {

  /** Surface 缓冲区所有权 */
  OHNativeWindowBuffer* windowBuffer = nullptr;

  /** 读写同步与播放时间 */
  int fenceFd = -1;
  int64_t timestampUs = 0;
};

/**
 * 检查旋转角度是否为受支持的四分之一周整数倍。
 *
 * @param rotation 旋转角度，支持 0、90、180 或 270。
 * @returns 角度为 0、90、180 或 270 时返回 true。
 */
bool IsSupportedRotation(int32_t rotation) {
  return rotation == 0 || rotation == 90 ||
      rotation == 180 || rotation == 270;
}

/**
 * 按指定旋转方向复制 NV12 平面，并输出紧凑排列的像素数据。
 *
 * @param sourceLuma 源图像 Y 亮度平面首地址。
 * @param sourceLumaStride 源亮度平面每行的字节跨度。
 * @param sourceChroma 源图像交错色度平面首地址。
 * @param sourceChromaStride 源色度平面每行的字节跨度。
 * @param width 画面宽度，单位像素。
 * @param height 画面高度，单位像素。
 * @param rotation 旋转角度，支持 0、90、180 或 270。
 * @param output 写入转换结果或提取值的目标地址。
 * @returns 无返回值。
 */
void CopyOrRotateNv12(
    const uint8_t* sourceLuma,
    int32_t sourceLumaStride,
    const uint8_t* sourceChroma,
    int32_t sourceChromaStride,
    int32_t width,
    int32_t height,
    int32_t rotation,
    std::vector<uint8_t>* output) {
  const bool swapsDimensions = rotation == 90 || rotation == 270;
  const int32_t targetWidth = swapsDimensions ? height : width;
  const int32_t targetHeight = swapsDimensions ? width : height;
  const size_t targetLumaLength =
      static_cast<size_t>(targetWidth) * static_cast<size_t>(targetHeight);
  output->resize(targetLumaLength + targetLumaLength / 2);

  uint8_t* targetLuma = output->data();
  if (rotation == 0) {
    const size_t lumaLength =
        static_cast<size_t>(width) * height;
    if (sourceLumaStride == width && sourceChromaStride == width) {
      std::memcpy(output->data(), sourceLuma, lumaLength);
      std::memcpy(
          output->data() + lumaLength,
          sourceChroma,
          lumaLength / 2);
      return;
    }
    for (int32_t y = 0; y < height; ++y) {
      std::memcpy(
          targetLuma + static_cast<size_t>(y) * width,
          sourceLuma + static_cast<size_t>(y) * sourceLumaStride,
          width);
    }
    uint8_t* targetChroma = output->data() + targetLumaLength;
    for (int32_t y = 0; y < height / 2; ++y) {
      std::memcpy(
          targetChroma + static_cast<size_t>(y) * width,
          sourceChroma + static_cast<size_t>(y) * sourceChromaStride,
          width);
    }
    return;
  }

  constexpr int32_t LUMA_TILE_SIZE = 32;
  for (int32_t blockY = 0; blockY < height;
       blockY += LUMA_TILE_SIZE) {
    for (int32_t blockX = 0; blockX < width;
         blockX += LUMA_TILE_SIZE) {
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
          targetLuma[
              static_cast<size_t>(targetY) * targetWidth + targetX] =
              sourceLuma[
                  static_cast<size_t>(y) * sourceLumaStride + x];
        }
      }
    }
  }

  uint8_t* targetChroma = output->data() + targetLumaLength;
  const int32_t sourceChromaWidth = width / 2;
  const int32_t sourceChromaHeight = height / 2;
  const int32_t targetChromaStride = targetWidth;
  constexpr int32_t CHROMA_TILE_SIZE = 16;
  for (int32_t blockY = 0; blockY < sourceChromaHeight;
       blockY += CHROMA_TILE_SIZE) {
    for (int32_t blockX = 0; blockX < sourceChromaWidth;
         blockX += CHROMA_TILE_SIZE) {
      const int32_t endY = std::min(
          blockY + CHROMA_TILE_SIZE, sourceChromaHeight);
      const int32_t endX = std::min(
          blockX + CHROMA_TILE_SIZE, sourceChromaWidth);
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
          const size_t sourceOffset =
              static_cast<size_t>(y) * sourceChromaStride + x * 2;
          const size_t targetOffset =
              static_cast<size_t>(targetY) * targetChromaStride +
              targetX * 2;
          targetChroma[targetOffset] = sourceChroma[sourceOffset];
          targetChroma[targetOffset + 1] =
              sourceChroma[sourceOffset + 1];
        }
      }
    }
  }
}

/**
 * 将目标平面坐标映射到源平面坐标，确保不越过源边界。
 *
 * @param targetIndex 目标平面中的采样索引。
 * @param sourceSize 源平面对应维度的采样数。
 * @param targetSize 目标平面对应维度的采样数。
 * @returns 对应的源平面采样索引。
 */
int32_t ScaledIndex(
    int32_t targetIndex,
    int32_t sourceSize,
    int32_t targetSize) {
  return std::min(
      static_cast<int32_t>(
          (static_cast<int64_t>(targetIndex) * sourceSize) /
          targetSize),
      sourceSize - 1);
}

/**
 * 按目标平面尺寸缩放源像素平面，支持单字节和双字节采样。
 *
 * @param source 源平面首地址。
 * @param sourceStride 源平面每行的字节跨度。
 * @param sourceWidth 源图像宽度，单位像素。
 * @param sourceHeight 源图像高度，单位像素。
 * @param target 目标平面首地址。
 * @param targetStride 目标平面每行的字节跨度。
 * @param targetWidth 目标图像或平面宽度。
 * @param targetHeight 目标图像或平面高度。
 * @param bytesPerSample 单个采样占用的字节数，支持 1 或 2。
 * @returns 无返回值。
 */
void ScalePlane(
    const uint8_t* source,
    int32_t sourceStride,
    int32_t sourceWidth,
    int32_t sourceHeight,
    uint8_t* target,
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
    const uint8_t* sourceRow =
        source + static_cast<size_t>(sourceY) * sourceStride;
    uint8_t* targetRow =
        target + static_cast<size_t>(y) * targetStride;
    for (int32_t x = 0; x < targetWidth; ++x) {
      const uint8_t* sourceSample =
          sourceRow + static_cast<size_t>(sourceX[x]) * bytesPerSample;
      uint8_t* targetSample =
          targetRow + static_cast<size_t>(x) * bytesPerSample;
      targetSample[0] = sourceSample[0];
      if (bytesPerSample == 2) {
        targetSample[1] = sourceSample[1];
      }
    }
  }
}

/**
 * 将源 NV12 图像缩放为指定目标尺寸，保持紧凑平面布局。
 *
 * @param sourceLuma 源图像 Y 亮度平面首地址。
 * @param sourceLumaStride 源亮度平面每行的字节跨度。
 * @param sourceChroma 源图像交错色度平面首地址。
 * @param sourceChromaStride 源色度平面每行的字节跨度。
 * @param sourceWidth 源图像宽度，单位像素。
 * @param sourceHeight 源图像高度，单位像素。
 * @param targetWidth 目标图像或平面宽度。
 * @param targetHeight 目标图像或平面高度。
 * @param output 写入转换结果或提取值的目标地址。
 * @returns 无返回值。
 */
void ScaleNv12(
    const uint8_t* sourceLuma,
    int32_t sourceLumaStride,
    const uint8_t* sourceChroma,
    int32_t sourceChromaStride,
    int32_t sourceWidth,
    int32_t sourceHeight,
    int32_t targetWidth,
    int32_t targetHeight,
    std::vector<uint8_t>* output) {
  if (sourceWidth == targetWidth && sourceHeight == targetHeight) {
    CopyOrRotateNv12(
        sourceLuma,
        sourceLumaStride,
        sourceChroma,
        sourceChromaStride,
        sourceWidth,
        sourceHeight,
        0,
        output);
    return;
  }

  const size_t lumaLength =
      static_cast<size_t>(targetWidth) * targetHeight;
  output->resize(lumaLength + lumaLength / 2);
  ScalePlane(
      sourceLuma,
      sourceLumaStride,
      sourceWidth,
      sourceHeight,
      output->data(),
      targetWidth,
      targetWidth,
      targetHeight,
      1);
  ScalePlane(
      sourceChroma,
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
 * 将 NV12 图像缩放并旋转为指定输出尺寸。
 *
 * @param sourceLuma 源图像 Y 亮度平面首地址。
 * @param sourceLumaStride 源亮度平面每行的字节跨度。
 * @param sourceChroma 源图像交错色度平面首地址。
 * @param sourceChromaStride 源色度平面每行的字节跨度。
 * @param sourceWidth 源图像宽度，单位像素。
 * @param sourceHeight 源图像高度，单位像素。
 * @param rotation 旋转角度，支持 0、90、180 或 270。
 * @param targetWidth 目标图像或平面宽度。
 * @param targetHeight 目标图像或平面高度。
 * @param output 写入转换结果或提取值的目标地址。
 * @returns 无返回值。
 */
void ScaleAndRotateNv12(
    const uint8_t* sourceLuma,
    int32_t sourceLumaStride,
    const uint8_t* sourceChroma,
    int32_t sourceChromaStride,
    int32_t sourceWidth,
    int32_t sourceHeight,
    int32_t rotation,
    int32_t targetWidth,
    int32_t targetHeight,
    std::vector<uint8_t>* output) {
  const bool swapsDimensions = rotation == 90 || rotation == 270;
  const int32_t scaledWidth =
      swapsDimensions ? targetHeight : targetWidth;
  const int32_t scaledHeight =
      swapsDimensions ? targetWidth : targetHeight;
  std::vector<uint8_t> scaledData;
  ScaleNv12(
      sourceLuma,
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
  const size_t scaledLumaLength =
      static_cast<size_t>(scaledWidth) * scaledHeight;
  CopyOrRotateNv12(
      scaledData.data(),
      scaledWidth,
      scaledData.data() + scaledLumaLength,
      scaledWidth,
      scaledWidth,
      scaledHeight,
      rotation,
      output);
}

/**
 * 连续解码本地视频，处理 Surface 或字节缓冲输出并按媒体时间轴交付 NV12 帧。
 */
class NativeVideoFileDecoder {
 public:
  /**
   * 创建视频文件解码器。
   *
   * @returns 无返回值；完成实例初始化。
   */
  NativeVideoFileDecoder() = default;

  /**
   * 停止媒体输出并释放实例持有的原生资源与缓存。
   *
   * @returns 无返回值。
   */
  ~NativeVideoFileDecoder() {
    Stop();
  }

  /** Only JS binding and fd ownership are established on the calling thread. */
  /**
   * 复制文件描述符并绑定 ArkTS 监听器，供后台解码初始化使用。
   *
   * @param env 当前 ArkTS N-API 执行环境。
   * @param listener 用于交付媒体帧、结束或错误通知的 ArkTS 函数。
   * @param sourceFd 由调用方打开的文件描述符；解码器会复制描述符以独立管理生命周期。
   * @param error 写入失败原因的字符串指针。
   * @returns 文件与监听器绑定成功时返回 true，否则返回 false 并写入错误。
   */
  bool Bind(napi_env env, napi_value listener, int32_t sourceFd, std::string* error) {
    fd_ = dup(sourceFd);
    if (fd_ < 0) {
      *error = "复制视频文件描述符失败";
      return false;
    }
    napi_value resourceName = nullptr;
    if (napi_create_string_utf8(env, "XmaxNativeVideoFileDecoder", NAPI_AUTO_LENGTH,
            &resourceName) != napi_ok ||
        napi_create_threadsafe_function(env, listener, nullptr, resourceName, 4, 1,
            nullptr, nullptr, nullptr, CallListener, &listener_) != napi_ok) {
      *error = "创建视频解码回调失败";
      return false;
    }
    return true;
  }

  /** Codec, demuxer and Surface setup run in a native async worker, without JS APIs. */
  /**
   * 创建并配置原生媒体资源，准备按目标规格输出媒体数据。
   *
   * @param sourceSize 源文件的字节长度。
   * @param playbackAnchorUs 媒体起点对应的单调播放锚点，单位微秒。
   * @param mediaStartUs 源媒体时间轴起点，单位微秒。
   * @param rotation 旋转角度，支持 0、90、180 或 270。
   * @param targetWidth 目标图像或平面宽度。
   * @param targetHeight 目标图像或平面高度。
   * @param frameIntervalUs 目标视频帧输出间隔，单位微秒。
   * @param cycleDurationUs 一轮媒体播放时长，单位微秒。
   * @param error 写入失败原因的字符串指针。
   * @returns 初始化成功时返回 true；失败返回 false 并写入错误说明。
   */
  bool Initialize(
      int64_t sourceSize,
      int64_t playbackAnchorUs,
      int64_t mediaStartUs,
      int32_t rotation,
      int32_t targetWidth,
      int32_t targetHeight,
      int64_t frameIntervalUs,
      int64_t cycleDurationUs,
      std::string* error) {
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

    OH_AVFormat* sourceFormat = OH_AVSource_GetSourceFormat(source_);
    int32_t trackCount = 0;
    if (sourceFormat == nullptr ||
        !OH_AVFormat_GetIntValue(
            sourceFormat, OH_MD_KEY_TRACK_COUNT, &trackCount) ||
        trackCount <= 0) {
      if (sourceFormat != nullptr) {
        OH_AVFormat_Destroy(sourceFormat);
      }
      *error = "读取视频轨道数量失败";
      return false;
    }
    OH_AVFormat_Destroy(sourceFormat);

    for (int32_t index = 0; index < trackCount; ++index) {
      OH_AVFormat* candidate = OH_AVSource_GetTrackFormat(source_, index);
      int32_t trackType = -1;
      if (candidate != nullptr &&
          OH_AVFormat_GetIntValue(
              candidate, OH_MD_KEY_TRACK_TYPE, &trackType) &&
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

    const char* mime = nullptr;
    if (!OH_AVFormat_GetStringValue(
            trackFormat_, OH_MD_KEY_CODEC_MIME, &mime) ||
        mime == nullptr ||
        !OH_AVFormat_GetIntValue(
            trackFormat_, OH_MD_KEY_WIDTH, &width_) ||
        !OH_AVFormat_GetIntValue(
            trackFormat_, OH_MD_KEY_HEIGHT, &height_) ||
        width_ <= 0 || height_ <= 0) {
      *error = "读取视频轨道格式失败";
      return false;
    }
    stride_ = width_;
    sliceHeight_ = height_;
    pixelFormat_ = AV_PIXEL_FORMAT_NV12;
    int32_t isHdrVivid = 0;
    isHdrVivid_ =
        OH_AVFormat_GetIntValue(
            trackFormat_, OH_MD_KEY_VIDEO_IS_HDR_VIVID, &isHdrVivid) &&
        isHdrVivid == 1;
    OH_AVFormat_SetIntValue(
        trackFormat_, OH_MD_KEY_PIXEL_FORMAT, AV_PIXEL_FORMAT_NV12);
    if (isHdrVivid_) {
      OH_AVFormat_SetIntValue(
          trackFormat_,
          OH_MD_KEY_VIDEO_DECODER_OUTPUT_COLOR_SPACE,
          OH_COLORSPACE_BT709_LIMIT);
    }

    demuxer_ = OH_AVDemuxer_CreateWithSource(source_);
    if (demuxer_ == nullptr ||
        OH_AVDemuxer_SelectTrackByID(
            demuxer_, trackIndex_) != AV_ERR_OK) {
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
      surfaceWorker_ =
          std::thread(&NativeVideoFileDecoder::SurfaceWorkerLoop, this);
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
      const VideoProcessing_ErrorCode processingResult =
          OH_VideoProcessing_Start(videoProcessor_);
      if (processingResult != VIDEO_PROCESSING_SUCCESS) {
        {
          std::lock_guard<std::mutex> lock(surfaceProcessingStateMutex_);
          videoProcessorStopped_ = true;
        }
        *error = "启动视频缩放失败：" +
            std::to_string(processingResult);
        return false;
      }
      videoProcessorStarted_ = true;
    }
    return true;
  }

  /**
   * 暂停连续媒体输出并唤醒节奏等待，使工作线程响应暂停状态。
   *
   * @returns 无返回值。
   */
  void Pause() {
    if (!running_.load()) {
      return;
    }
    paused_.store(true);
    pacingCondition_.notify_all();
  }

  /**
   * 按暂停时长平移播放锚点，恢复连续媒体输出。
   *
   * @param pausedDurationUs 本次暂停持续时间，单位微秒。
   * @returns 无返回值。
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

  /**
   * 停止媒体输出与相关线程，并释放文件、系统媒体资源和回调引用。
   *
   * @returns 无返回值。
   */
  void Stop() {
    const bool wasRunning = running_.exchange(false);
    paused_.store(false);
    pacingCondition_.notify_all();

    {
      std::lock_guard<std::mutex> lock(demuxerMutex_);
    }

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
   * 根据解码格式选择字节缓冲或 Surface 输出，并准备视频解码器。
   *
   * @param mime 源轨道的媒体编码 MIME 类型。
   * @param error 写入失败原因的字符串指针。
   * @returns 输出链路准备成功时返回 true，否则返回 false 并写入错误。
   */
  bool PrepareOutput(const char* mime, std::string* error) {
    // HDR requires Surface output for tone mapping. SDR only needs the extra
    // processing stage when both axes can be downscaled before CPU readback.
    useSurfaceOutput_ = ShouldUseSurfaceOutput();
    if (useSurfaceOutput_ && !InitializeOutputSurface(error)) {
      if (isHdrVivid_) {
        return false;
      }
      OH_LOG_Print(LOG_APP, LOG_WARN, 0xA000, "XmaxSDK",
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
    OH_LOG_Print(LOG_APP, LOG_WARN, 0xA000, "XmaxSDK",
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
   * 判断当前视频格式是否需要使用 Surface 解码输出。
   *
   * @returns 应使用 Surface 输出时返回 true。
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
   * 按源编码类型创建并配置系统视频解码器。
   *
   * @param mime 源轨道的媒体编码 MIME 类型。
   * @param error 写入失败原因的字符串指针。
   * @returns 系统解码器准备成功时返回 true，否则返回 false 并写入错误。
   */
  bool PrepareDecoder(const char* mime, std::string* error) {
    decoder_ = OH_VideoDecoder_CreateByMime(mime);
    if (decoder_ == nullptr) {
      *error = "当前设备不支持所选视频编码";
      return false;
    }
    const OH_AVCodecCallback callbacks{
        OnError, OnStreamChanged, OnNeedInputBuffer, OnNewOutputBuffer
    };
    if (OH_VideoDecoder_RegisterCallback(decoder_, callbacks, this) != AV_ERR_OK ||
        OH_VideoDecoder_Configure(decoder_, trackFormat_) != AV_ERR_OK) {
      *error = "配置 NV12 视频连续解码失败";
      return false;
    }
    if (useSurfaceOutput_ && OH_VideoDecoder_SetSurface(
            decoder_, surfaceProcessorInputWindow_) != AV_ERR_OK) {
      *error = "绑定视频缩放 Surface 失败";
      return false;
    }
    if (OH_VideoDecoder_Prepare(decoder_) != AV_ERR_OK) {
      *error = "准备 NV12 视频连续解码失败";
      return false;
    }
    return true;
  }

  /**
   * 停止 Surface 消费线程并唤醒等待中的工作循环。
   *
   * @returns 无返回值。
   */
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
   * 创建视频处理与 Surface 输出资源，供解码器交付原生帧。
   *
   * @param error 写入失败原因的字符串指针。
   * @returns 输出 Surface 初始化成功时返回 true，否则返回 false 并写入错误。
   */
  bool InitializeOutputSurface(std::string* error) {
    const bool swapsDimensions = rotation_ == 90 || rotation_ == 270;
    const int32_t surfaceWidth = swapsDimensions ? targetHeight_ : targetWidth_;
    const int32_t surfaceHeight = swapsDimensions ? targetWidth_ : targetHeight_;
    surfaceOutputSurface_ = OH_ConsumerSurface_Create();
    if (surfaceOutputSurface_ == nullptr) {
      *error = "创建视频输出 Surface 失败";
      return false;
    }
    if (OH_ConsumerSurface_SetDefaultUsage(
        surfaceOutputSurface_,
        NATIVEBUFFER_USAGE_CPU_READ |
            NATIVEBUFFER_USAGE_CPU_READ_OFTEN) != 0 ||
        OH_ConsumerSurface_SetDefaultSize(
            surfaceOutputSurface_, surfaceWidth, surfaceHeight) != 0) {
      *error = "配置视频输出 Surface 失败";
      ReleaseOutputSurface();
      return false;
    }
    surfaceOutputWindow_ = OH_NativeImage_AcquireNativeWindow(
        surfaceOutputSurface_);
    if (surfaceOutputWindow_ == nullptr ||
        OH_NativeWindow_NativeWindowHandleOpt(
            surfaceOutputWindow_,
            SET_FORMAT,
            NATIVEBUFFER_PIXEL_FMT_YCBCR_420_SP) != 0 ||
        (isHdrVivid_ && OH_NativeWindow_SetColorSpace(
            surfaceOutputWindow_, OH_COLORSPACE_BT709_LIMIT) != 0)) {
      *error = "配置视频输出格式失败";
      ReleaseOutputSurface();
      return false;
    }
    VideoProcessing_ErrorCode processingResult =
        OH_VideoProcessing_Create(
            &videoProcessor_,
            VIDEO_PROCESSING_TYPE_DETAIL_ENHANCER);
    if (processingResult != VIDEO_PROCESSING_SUCCESS ||
        videoProcessor_ == nullptr) {
      *error = "创建视频缩放器失败：" +
          std::to_string(processingResult);
      ReleaseOutputSurface();
      return false;
    }
    OH_AVFormat* processingParameter = OH_AVFormat_Create();
    if (processingParameter == nullptr ||
        !OH_AVFormat_SetIntValue(
            processingParameter,
            VIDEO_DETAIL_ENHANCER_PARAMETER_KEY_QUALITY_LEVEL,
            VIDEO_DETAIL_ENHANCER_QUALITY_LEVEL_NONE)) {
      if (processingParameter != nullptr) {
        OH_AVFormat_Destroy(processingParameter);
      }
      *error = "配置视频缩放参数失败";
      ReleaseOutputSurface();
      return false;
    }
    processingResult = OH_VideoProcessing_SetParameter(
        videoProcessor_, processingParameter);
    OH_AVFormat_Destroy(processingParameter);
    if (processingResult != VIDEO_PROCESSING_SUCCESS ||
        OH_VideoProcessing_GetSurface(
            videoProcessor_, &surfaceProcessorInputWindow_) !=
            VIDEO_PROCESSING_SUCCESS ||
        surfaceProcessorInputWindow_ == nullptr ||
        OH_NativeWindow_NativeWindowHandleOpt(
            surfaceProcessorInputWindow_,
            SET_FORMAT,
            NATIVEBUFFER_PIXEL_FMT_YCBCR_420_SP) != 0 ||
        (isHdrVivid_ && OH_NativeWindow_SetColorSpace(
            surfaceProcessorInputWindow_, OH_COLORSPACE_BT709_LIMIT) != 0) ||
        OH_VideoProcessing_SetSurface(
            videoProcessor_, surfaceOutputWindow_) !=
            VIDEO_PROCESSING_SUCCESS) {
      *error = "连接视频缩放 Surface 失败：" +
          std::to_string(processingResult);
      ReleaseOutputSurface();
      return false;
    }

    processingResult =
        OH_VideoProcessingCallback_Create(&surfaceProcessingCallback_);
    if (processingResult != VIDEO_PROCESSING_SUCCESS ||
        surfaceProcessingCallback_ == nullptr ||
        OH_VideoProcessingCallback_BindOnError(
            surfaceProcessingCallback_, OnSurfaceProcessingError) !=
            VIDEO_PROCESSING_SUCCESS ||
        OH_VideoProcessingCallback_BindOnState(
            surfaceProcessingCallback_, OnSurfaceProcessingState) !=
            VIDEO_PROCESSING_SUCCESS ||
        OH_VideoProcessingCallback_BindOnNewOutputBuffer(
            surfaceProcessingCallback_, OnSurfaceProcessingOutputBuffer) !=
            VIDEO_PROCESSING_SUCCESS ||
        OH_VideoProcessing_RegisterCallback(
            videoProcessor_, surfaceProcessingCallback_, this) !=
            VIDEO_PROCESSING_SUCCESS) {
      *error = "注册视频缩放回调失败：" +
          std::to_string(processingResult);
      ReleaseOutputSurface();
      return false;
    }
    return true;
  }

  /**
   * 停止视频处理器并等待其停止状态通知。
   *
   * @returns 无返回值。
   */
  void StopVideoProcessor() {
    if (!videoProcessorStarted_ || videoProcessor_ == nullptr) {
      return;
    }
    const VideoProcessing_ErrorCode stopResult =
        OH_VideoProcessing_Stop(videoProcessor_);
    if (stopResult == VIDEO_PROCESSING_SUCCESS) {
      std::unique_lock<std::mutex> lock(surfaceProcessingStateMutex_);
      surfaceProcessingStateCondition_.wait(
          lock, [this] { return videoProcessorStopped_; });
    }
    videoProcessorStarted_ = false;
  }

  /**
   * 归还待消费 Surface 缓冲区并释放视频处理器、窗口及图像资源。
   *
   * @returns 无返回值。
   */
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
   * 接收视频处理器的输出索引，并登记可消费的 Surface 帧。
   *
   * @param index 需要提交或归还的系统缓冲区索引。
   * @param context 注册视频处理回调时绑定的原生解码器实例。
   * @returns 无返回值。
   */
  static void OnSurfaceProcessingOutputBuffer(
      OH_VideoProcessing*, uint32_t index, void* context) {
    auto* decoder = static_cast<NativeVideoFileDecoder*>(context);
    if (decoder != nullptr) {
      decoder->EnqueueSurfaceFrame(index);
    }
  }

  /**
   * 将视频处理器错误转为解码失败通知。
   *
   * @param error 原生视频处理器错误码。
   * @param context 注册视频处理回调时绑定的原生解码器实例。
   * @returns 无返回值。
   */
  static void OnSurfaceProcessingError(
      OH_VideoProcessing*,
      VideoProcessing_ErrorCode error,
      void* context) {
    auto* decoder = static_cast<NativeVideoFileDecoder*>(context);
    if (decoder != nullptr) {
      decoder->ReportError(
          "视频缩放失败：" + std::to_string(error));
    }
  }

  /**
   * 保存视频处理器运行状态并唤醒等待停止的线程。
   *
   * @param state 系统视频处理器的运行状态。
   * @param context 注册视频处理回调时绑定的原生解码器实例。
   * @returns 无返回值。
   */
  static void OnSurfaceProcessingState(
      OH_VideoProcessing*,
      VideoProcessing_State state,
      void* context) {
    auto* decoder = static_cast<NativeVideoFileDecoder*>(context);
    if (decoder == nullptr ||
        state != VIDEO_PROCESSING_STATE_STOPPED) {
      return;
    }
    {
      std::lock_guard<std::mutex> lock(
          decoder->surfaceProcessingStateMutex_);
      decoder->videoProcessorStopped_ = true;
    }
    decoder->surfaceProcessingStateCondition_.notify_all();
  }

  /**
   * 将视频处理器输出索引交回 Surface，并唤醒帧消费线程。
   *
   * @param index 需要提交或归还的系统缓冲区索引。
   * @returns 无返回值。
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
   * 取得待消费的 Surface 缓冲区并关联媒体时间戳。
   *
   * @param packet 需要消费、交付或释放的媒体数据包。
   * @returns 取得可处理缓冲区时返回 true；无帧或已停止时返回 false。
   */
  bool AcquireSurfaceFrame(SurfaceBufferPacket& packet) {
    std::lock_guard<std::mutex> surfaceLock(surfaceMutex_);
    if (surfaceOutputSurface_ == nullptr) {
      return false;
    }
    OHNativeWindowBuffer* windowBuffer = nullptr;
    int fenceFd = -1;
    if (OH_NativeImage_AcquireNativeWindowBuffer(
            surfaceOutputSurface_, &windowBuffer, &fenceFd) != 0 ||
        windowBuffer == nullptr) {
      if (fenceFd >= 0) {
        close(fenceFd);
      }
      ReportError("读取视频 Surface 帧失败");
      return false;
    }
    if (OH_NativeWindow_NativeObjectReference(windowBuffer) != 0) {
      OH_NativeImage_ReleaseNativeWindowBuffer(
          surfaceOutputSurface_, windowBuffer, fenceFd);
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
      OH_NativeImage_ReleaseNativeWindowBuffer(
          surfaceOutputSurface_, windowBuffer, fenceFd);
      ReportError("视频 Surface 帧缺少时间戳");
      return false;
    }
    packet = {windowBuffer, fenceFd, timestampUs};
    return true;
  }

  /**
   * 在持有 Surface 访问锁时归还缓冲区及其同步栅栏。
   *
   * @param packet 需要消费、交付或释放的媒体数据包。
   * @returns 无返回值。
   */
  void ReleaseSurfaceBufferLocked(
      const SurfaceBufferPacket& packet) {
    if (packet.windowBuffer == nullptr) {
      if (packet.fenceFd >= 0) {
        close(packet.fenceFd);
      }
      return;
    }
    OH_NativeWindow_NativeObjectUnreference(packet.windowBuffer);
    if (surfaceOutputSurface_ != nullptr) {
      OH_NativeImage_ReleaseNativeWindowBuffer(
          surfaceOutputSurface_, packet.windowBuffer, packet.fenceFd);
    } else if (packet.fenceFd >= 0) {
      close(packet.fenceFd);
    }
  }

  /**
   * 在已结束输入且所有 Surface 帧处理完毕时消费结束标记。
   *
   * @returns 可以发送本轮结束通知时返回 true。
   */
  bool ConsumeSurfaceEndOfStreamIfReadyLocked() {
    if (!running_.load() || !surfaceEndOfStreamPending_ ||
        !pendingSurfaceTimestamps_.empty() ||
        surfaceFramesInFlight_ != 0) {
      return false;
    }
    surfaceEndOfStreamPending_ = false;
    return true;
  }

  /**
   * 减少正在处理的 Surface 帧计数，并在全部完成后交付结束通知。
   *
   * @returns 无返回值。
   */
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

  /**
   * 向 ArkTS 交付文件解码输出结束通知。
   *
   * @returns 无返回值。
   */
  void DispatchEndOfStream() {
    auto* packet = new DecodedFramePacket();
    packet->endOfStream = true;
    Dispatch(packet);
  }

  /**
   * 在独立线程等待并消费 Surface 帧，将图像转换后按播放节奏交付。
   *
   * @returns 无返回值。
   */
  void SurfaceWorkerLoop() {
    while (true) {
      SurfaceBufferPacket packet;
      uint32_t outputIndex = 0;
      bool dropFrame = false;
      {
        std::unique_lock<std::mutex> lock(surfaceQueueMutex_);
        surfaceCondition_.wait(lock, [this] {
          return !surfaceWorkerRunning_.load() ||
              !surfacePendingOutputBuffers_.empty();
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
      if (OH_VideoProcessing_RenderOutputBuffer(
              videoProcessor_, outputIndex) != VIDEO_PROCESSING_SUCCESS) {
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
   * 等待同步栅栏并映射 Surface 缓冲，转换目标 NV12 帧后归还原生资源。
   *
   * @param packet 需要消费、交付或释放的媒体数据包。
   * @returns 无返回值。
   */
  void HandleSurfaceFrame(const SurfaceBufferPacket& packet) {
    OHNativeWindowBuffer* windowBuffer = packet.windowBuffer;
    int fenceFd = packet.fenceFd;
    OH_NativeImage* outputSurface = surfaceOutputSurface_;
    const auto releaseWindowBuffer =
        [this, outputSurface, windowBuffer](int releaseFenceFd) {
      std::lock_guard<std::mutex> surfaceLock(surfaceMutex_);
      OH_NativeWindow_NativeObjectUnreference(windowBuffer);
      OH_NativeImage_ReleaseNativeWindowBuffer(
          outputSurface, windowBuffer, releaseFenceFd);
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
      for (int32_t attempt = 0;
           attempt < 60 && running_.load(); ++attempt) {
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
    OH_NativeBuffer* nativeBuffer = nullptr;
    void* address = nullptr;
    OH_NativeBuffer_Planes planes{};
    OH_NativeBuffer_Config config{};
    const bool mapped =
        OH_NativeBuffer_FromNativeWindowBuffer(
            windowBuffer, &nativeBuffer) == 0 &&
        nativeBuffer != nullptr &&
        OH_NativeBuffer_MapPlanes(
            nativeBuffer, &address, &planes) == 0 &&
        address != nullptr;
    if (nativeBuffer != nullptr) {
      OH_NativeBuffer_GetConfig(nativeBuffer, &config);
    }
    if (!mapped || planes.planeCount < 2 ||
        config.format != NATIVEBUFFER_PIXEL_FMT_YCBCR_420_SP ||
        config.width <= 0 || config.height <= 0 ||
        config.stride < config.width) {
      if (mapped) {
        OH_NativeBuffer_Unmap(nativeBuffer);
      }
      releaseWindowBuffer(-1);
      ReportError("访问视频 NV12 帧失败");
      return;
    }
    const auto* bytes = static_cast<const uint8_t*>(address);
    CopyOrRotateNv12(
        bytes + planes.planes[0].offset,
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
    const int32_t scaledWidth =
        swapsDimensions ? targetHeight_ : targetWidth_;
    const int32_t scaledHeight =
        swapsDimensions ? targetWidth_ : targetHeight_;
    const size_t sourceLumaLength =
        static_cast<size_t>(config.width) * config.height;
    // Usually VPE has already produced the requested size. Only fall back to
    // CPU scaling if the device returns a different actual buffer size.
    std::vector<uint8_t>* scaledData = &surfaceSourceData_;
    if (config.width != scaledWidth || config.height != scaledHeight) {
      ScaleNv12(
          surfaceSourceData_.data(),
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
      const size_t scaledLumaLength =
          static_cast<size_t>(scaledWidth) * scaledHeight;
      CopyOrRotateNv12(
          scaledData->data(),
          scaledWidth,
          scaledData->data() + scaledLumaLength,
          scaledWidth,
          scaledWidth,
          scaledHeight,
          rotation_,
          &frameData);
    }

    auto* outputPacket = new DecodedFramePacket();
    outputPacket->width = targetWidth_;
    outputPacket->height = targetHeight_;
    outputPacket->stride = outputPacket->width;
    outputPacket->timestampUs = packet.timestampUs;
    outputPacket->data = std::move(frameData);
    Dispatch(outputPacket);
  }

  /**
   * 接收系统解码错误，将错误码转换为媒体失败通知。
   *
   * @param errorCode 系统解码器返回的错误码。
   * @param userData 注册系统回调时绑定的原生解码器实例。
   * @returns 无返回值。
   */
  static void OnError(
      OH_AVCodec*,
      int32_t errorCode,
      void* userData) {
    auto* decoder = static_cast<NativeVideoFileDecoder*>(userData);
    if (decoder != nullptr) {
      decoder->ReportError(
          "视频解码器错误：" + std::to_string(errorCode));
    }
  }

  /**
   * 同步系统解码器报告的输出格式，供后续帧读取和转换使用。
   *
   * @param format 系统解码器报告的媒体格式。
   * @param userData 注册系统回调时绑定的原生解码器实例。
   * @returns 无返回值。
   */
  static void OnStreamChanged(
      OH_AVCodec*,
      OH_AVFormat* format,
      void* userData) {
    auto* decoder = static_cast<NativeVideoFileDecoder*>(userData);
    if (decoder == nullptr || format == nullptr) {
      return;
    }
    std::lock_guard<std::mutex> lock(decoder->formatMutex_);
    int32_t value = 0;
    if (OH_AVFormat_GetIntValue(
            format, OH_MD_KEY_VIDEO_PIC_WIDTH, &value) ||
        OH_AVFormat_GetIntValue(format, OH_MD_KEY_WIDTH, &value)) {
      decoder->width_ = value;
    }
    if (OH_AVFormat_GetIntValue(
            format, OH_MD_KEY_VIDEO_PIC_HEIGHT, &value) ||
        OH_AVFormat_GetIntValue(format, OH_MD_KEY_HEIGHT, &value)) {
      decoder->height_ = value;
    }
    if (OH_AVFormat_GetIntValue(
            format, OH_MD_KEY_VIDEO_STRIDE, &value)) {
      decoder->stride_ = value;
    }
    if (OH_AVFormat_GetIntValue(
            format, OH_MD_KEY_VIDEO_SLICE_HEIGHT, &value)) {
      decoder->sliceHeight_ = value;
    }
    if (OH_AVFormat_GetIntValue(
            format, OH_MD_KEY_PIXEL_FORMAT, &value)) {
      decoder->pixelFormat_ = value;
    }
  }

  /**
   * 从选中媒体轨道读取压缩数据，填入解码器请求的输入缓冲区。
   *
   * @param codec 请求或交付缓冲区的系统解码器。
   * @param index 需要提交或归还的系统缓冲区索引。
   * @param buffer 系统解码器提供的媒体缓冲区。
   * @param userData 注册系统回调时绑定的原生解码器实例。
   * @returns 无返回值。
   */
  static void OnNeedInputBuffer(
      OH_AVCodec* codec,
      uint32_t index,
      OH_AVBuffer* buffer,
      void* userData) {
    auto* decoder = static_cast<NativeVideoFileDecoder*>(userData);
    if (decoder == nullptr || !decoder->running_.load() ||
        buffer == nullptr) {
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
      readResult = OH_AVDemuxer_ReadSampleBuffer(
          decoder->demuxer_, decoder->trackIndex_, buffer);
      if (readResult == AV_ERR_OK) {
        OH_AVCodecBufferAttr attr{};
        attributeResult = OH_AVBuffer_GetBufferAttr(buffer, &attr);
        bool endOfStream = attributeResult == AV_ERR_OK &&
            (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0;
        if (decoder->isHdrVivid_ && endOfStream &&
            decoder->cycleDurationUs_ > 0 &&
            OH_AVDemuxer_SeekToTime(
                decoder->demuxer_,
                0,
                SEEK_MODE_PREVIOUS_SYNC) == AV_ERR_OK) {
          readResult = OH_AVDemuxer_ReadSampleBuffer(
              decoder->demuxer_, decoder->trackIndex_, buffer);
          if (readResult == AV_ERR_OK) {
            attributeResult = OH_AVBuffer_GetBufferAttr(buffer, &attr);
            endOfStream = attributeResult == AV_ERR_OK &&
                (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0;
            if (attributeResult == AV_ERR_OK && !endOfStream) {
              ++decoder->inputLoopIndex_;
            }
          }
        }
        if (readResult == AV_ERR_OK) {
          loopIndex = decoder->inputLoopIndex_;
          if (decoder->isHdrVivid_ && attributeResult == AV_ERR_OK &&
              !endOfStream && loopIndex > 0) {
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
      decoder->ReportError(
          "读取视频压缩帧失败：" + std::to_string(readResult));
      return;
    }
    if (attributeResult != AV_ERR_OK) {
      decoder->ReportError(
          "更新 HDR Vivid 循环帧时间戳失败：" +
          std::to_string(attributeResult));
      return;
    }
    if (pushResult != AV_ERR_OK) {
      decoder->ReportError(
          "提交视频压缩帧失败：" + std::to_string(pushResult));
    }
  }

  /**
   * 处理系统解码器输出的媒体缓冲区，并在完成后归还缓冲区索引。
   *
   * @param codec 请求或交付缓冲区的系统解码器。
   * @param index 需要提交或归还的系统缓冲区索引。
   * @param buffer 系统解码器提供的媒体缓冲区。
   * @param userData 注册系统回调时绑定的原生解码器实例。
   * @returns 无返回值。
   */
  static void OnNewOutputBuffer(
      OH_AVCodec* codec,
      uint32_t index,
      OH_AVBuffer* buffer,
      void* userData) {
    auto* decoder = static_cast<NativeVideoFileDecoder*>(userData);
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
   * 将解码器输出交给 Surface 处理链路，并关联帧时间与文件结束标记。
   *
   * @param codec 请求或交付缓冲区的系统解码器。
   * @param index 需要提交或归还的系统缓冲区索引。
   * @param buffer 系统解码器提供的媒体缓冲区。
   * @returns 无返回值。
   */
  void HandleSurfaceOutputBuffer(
      OH_AVCodec* codec,
      uint32_t index,
      OH_AVBuffer* buffer) {
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
        if (!pendingSurfaceTimestamps_.empty() &&
            pendingSurfaceTimestamps_.back() == timestampUs) {
          pendingSurfaceTimestamps_.pop_back();
        }
      }
      ReportError("渲染视频 Surface 帧失败");
    }
  }

  /**
   * 读取解码缓冲数据及时间戳，转换并按播放时间轴交付媒体帧。
   *
   * @param buffer 系统解码器提供的媒体缓冲区。
   * @returns 无返回值。
   */
  void HandleOutputBuffer(OH_AVBuffer* buffer) {
    if (!running_.load()) {
      return;
    }
    OH_AVCodecBufferAttr attr{};
    if (OH_AVBuffer_GetBufferAttr(buffer, &attr) != AV_ERR_OK) {
      ReportError("读取解码视频帧属性失败");
      return;
    }
    if ((attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0) {
      auto* packet = new DecodedFramePacket();
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
    if (pixelFormat != AV_PIXEL_FORMAT_NV12 ||
        width <= 0 || height <= 0) {
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
    const size_t sourceLength = static_cast<size_t>(stride) *
        static_cast<size_t>(sliceHeight + height / 2);
    if (sourceLength > static_cast<size_t>(attr.size)) {
      ReportError("NV12 视频解码帧布局无效");
      return;
    }

    uint8_t* address = OH_AVBuffer_GetAddr(buffer);
    const int32_t capacity = OH_AVBuffer_GetCapacity(buffer);
    if (address == nullptr || capacity < 0 ||
        static_cast<int64_t>(attr.offset) +
            static_cast<int64_t>(sourceLength) > capacity) {
      ReportError("访问 NV12 视频解码帧失败");
      return;
    }

    Pace(attr.pts);
    if (!running_.load()) {
      return;
    }
    std::vector<uint8_t> frameData;
    ScaleAndRotateNv12(
        address + attr.offset,
        stride,
        address + attr.offset +
            static_cast<size_t>(stride) * sliceHeight,
        stride,
        width,
        height,
        rotation_,
        targetWidth_,
        targetHeight_,
        &frameData);

    auto* packet = new DecodedFramePacket();
    packet->width = targetWidth_;
    packet->height = targetHeight_;
    packet->stride = packet->width;
    packet->timestampUs = PlaybackTimestampUs(attr.pts);
    packet->data = std::move(frameData);
    Dispatch(packet);
  }

  /**
   * 按目标播放时间等待，同时响应暂停和停止请求，避免解码输出快于播放进度。
   *
   * @param timestampUs 媒体输出时间戳，单位微秒。
   * @returns 无返回值。
   */
  void Pace(int64_t timestampUs) {
    std::unique_lock<std::mutex> lock(pacingMutex_);
    while (running_.load()) {
      pacingCondition_.wait(lock, [this] {
        return !running_.load() || !paused_.load();
      });
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
   * 等待媒体恢复播放或停止，供解码回调遵守暂停状态。
   *
   * @returns 仍在运行且允许播放时返回 true，已经停止时返回 false。
   */
  bool WaitUntilPlaying() {
    std::unique_lock<std::mutex> lock(pacingMutex_);
    pacingCondition_.wait(lock, [this] {
      return !running_.load() || !paused_.load();
    });
    return running_.load();
  }

  /**
   * 按目标帧间隔过滤视频帧，避免重复或过密的媒体时间戳。
   *
   * @param mediaTimestampUs 源媒体时间戳，单位微秒。
   * @returns 当前媒体时间戳应输出时返回 true。
   */
  bool ShouldOutputFrame(int64_t mediaTimestampUs) {
    if (lastOutputMediaTimestampUs_ >= 0 &&
        mediaTimestampUs - lastOutputMediaTimestampUs_ <
            frameIntervalUs_ * 3 / 4) {
      return false;
    }
    lastOutputMediaTimestampUs_ = mediaTimestampUs;
    return true;
  }

  /**
   * 将媒体时间戳映射为包含暂停补偿的单调播放时间。
   *
   * @param mediaTimestampUs 源媒体时间戳，单位微秒。
   * @returns 以微秒为单位的播放时间戳。
   */
  int64_t PlaybackTimestampUs(int64_t mediaTimestampUs) const {
    return playbackAnchorUs_.load() + std::max<int64_t>(
        mediaTimestampUs - mediaStartUs_,
        0);
  }

  /**
   * 仅通知一次媒体处理错误，避免重复错误回调。
   *
   * @param message 需要交付或记录的错误原因。
   * @returns 无返回值。
   */
  void ReportError(const std::string& message) {
    if (reportedError_.exchange(true)) {
      return;
    }
    auto* packet = new DecodedFramePacket();
    packet->error = message;
    Dispatch(packet);
  }

  /**
   * 将媒体数据包提交到 ArkTS 线程安全回调队列；提交失败时释放数据包。
   *
   * @param packet 需要消费、交付或释放的媒体数据包。
   * @returns 无返回值。
   */
  void Dispatch(DecodedFramePacket* packet) {
    if (listener_ == nullptr ||
        napi_call_threadsafe_function(
            listener_, packet, napi_tsfn_blocking) != napi_ok) {
      delete packet;
    }
  }

  /**
   * 在 ArkTS 外部帧缓冲区被回收时释放对应原生视频数据包。
   *
   * @param hint 关联到外部帧缓冲区、需要在回收时释放的数据包。
   * @returns 无返回值。
   */
  static void FinalizeFrameData(
      napi_env,
      void*,
      void* hint) {
    delete static_cast<std::vector<uint8_t>*>(hint);
  }

  /**
   * 在 ArkTS 线程交付媒体数据或状态通知，并按交付结果转移或释放数据包。
   *
   * @param env 当前 ArkTS N-API 执行环境。
   * @param callback 需要在 ArkTS 线程调用的函数。
   * @param data 关联的原生数据包或异步任务上下文。
   * @returns 无返回值。
   */
  static void CallListener(
      napi_env env,
      napi_value callback,
      void*,
      void* data) {
    auto* packet = static_cast<DecodedFramePacket*>(data);
    if (packet == nullptr) {
      return;
    }
    if (env == nullptr || callback == nullptr) {
      delete packet;
      return;
    }

    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    napi_value arguments[7] = {
        undefined,
        undefined,
        undefined,
        undefined,
        undefined,
        undefined,
        undefined
    };
    if (!packet->data.empty()) {
      auto* frameData = new std::vector<uint8_t>(
          std::move(packet->data));
      if (napi_create_external_arraybuffer(
              env,
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
    napi_create_double(
        env,
        static_cast<double>(packet->timestampUs),
        &arguments[4]);
    napi_get_boolean(env, packet->endOfStream, &arguments[5]);
    if (!packet->error.empty()) {
      napi_create_string_utf8(
          env,
          packet->error.c_str(),
          NAPI_AUTO_LENGTH,
          &arguments[6]);
    }

    napi_value result = nullptr;
    napi_call_function(
        env,
        undefined,
        callback,
        sizeof(arguments) / sizeof(arguments[0]),
        arguments,
        &result);
    delete packet;
  }

  /** 文件、解封装与视频解码资源 */
  int32_t fd_ = -1;
  OH_AVSource* source_ = nullptr;
  OH_AVDemuxer* demuxer_ = nullptr;
  OH_AVCodec* decoder_ = nullptr;
  OH_AVFormat* trackFormat_ = nullptr;
  uint32_t trackIndex_ = 0;

  /** ArkTS 帧与状态通知 */
  napi_threadsafe_function listener_ = nullptr;

  /** 运行、暂停与错误去重状态 */
  std::atomic<bool> running_{false};
  std::atomic<bool> paused_{false};
  std::atomic<bool> reportedError_{false};

  /** 输入读取与解封装同步 */
  std::mutex demuxerMutex_;
  bool inputEnded_ = false;

  /** 解码格式与像素布局同步 */
  std::mutex formatMutex_;
  int32_t width_ = 0;
  int32_t height_ = 0;
  int32_t stride_ = 0;
  int32_t sliceHeight_ = 0;
  int32_t pixelFormat_ = 0;

  /** Surface 输出选择 */
  bool isHdrVivid_ = false;
  bool useSurfaceOutput_ = false;

  /** 视频处理器与输入窗口 */
  OH_VideoProcessing* videoProcessor_ = nullptr;
  VideoProcessing_Callback* surfaceProcessingCallback_ = nullptr;
  OHNativeWindow* surfaceProcessorInputWindow_ = nullptr;
  bool videoProcessorStarted_ = false;
  bool videoProcessorStopped_ = true;

  /** 视频处理器停止状态同步 */
  std::mutex surfaceProcessingStateMutex_;
  std::condition_variable surfaceProcessingStateCondition_;

  /** 输出 Surface 与原生窗口 */
  OH_NativeImage* surfaceOutputSurface_ = nullptr;
  OHNativeWindow* surfaceOutputWindow_ = nullptr;

  /** Surface 资源与帧队列同步 */
  std::mutex surfaceMutex_;
  std::mutex surfaceQueueMutex_;
  std::condition_variable surfaceCondition_;

  /** 待消费输出缓冲区 */
  std::deque<uint32_t> surfacePendingOutputBuffers_;

  /** Surface 消费线程 */
  std::atomic<bool> surfaceWorkerRunning_{false};
  std::thread surfaceWorker_;

  /** 帧时间戳与结束通知同步 */
  std::mutex surfaceTimestampMutex_;
  std::deque<int64_t> pendingSurfaceTimestamps_;
  size_t surfaceFramesInFlight_ = 0;
  bool surfaceEndOfStreamPending_ = false;

  /** Surface 像素转换缓存 */
  std::vector<uint8_t> surfaceSourceData_;
  std::vector<uint8_t> surfaceScaledData_;

  /** 暂停与播放节奏同步 */
  std::mutex pacingMutex_;
  std::condition_variable pacingCondition_;

  /** 媒体时间轴与输出采样规格 */
  std::atomic<int64_t> playbackAnchorUs_{0};
  int64_t mediaStartUs_ = 0;
  int32_t rotation_ = 0;
  int32_t targetWidth_ = 0;
  int32_t targetHeight_ = 0;
  int64_t frameIntervalUs_ = 0;
  int64_t cycleDurationUs_ = 0;

  /** 文件循环轮次与输出帧去重 */
  int64_t inputLoopIndex_ = 0;
  int64_t lastOutputMediaTimestampUs_ = -1;
};

/**
 * 从 ArkTS 对象中读取其绑定的原生文件解码器。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param info 当前 ArkTS 方法调用的参数与接收对象。
 * @param receiver 写回 ArkTS 方法接收对象的可选指针。
 * @returns 有效解码器指针；调用无效时返回空指针并抛出异常。
 */
NativeVideoFileDecoder* UnwrapDecoder(
    napi_env env,
    napi_callback_info info,
    napi_value* receiver = nullptr) {
  size_t argumentCount = 0;
  napi_value thisValue = nullptr;
  if (napi_get_cb_info(
          env,
          info,
          &argumentCount,
          nullptr,
          &thisValue,
          nullptr) != napi_ok) {
    return nullptr;
  }
  NativeVideoFileDecoder* decoder = nullptr;
  if (napi_unwrap(
          env,
          thisValue,
          reinterpret_cast<void**>(&decoder)) != napi_ok) {
    return nullptr;
  }
  if (receiver != nullptr) {
    *receiver = thisValue;
  }
  return decoder;
}

/**
 * 将 ArkTS 暂停请求转交给原生文件解码器。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param info 当前 ArkTS 方法调用的参数与接收对象。
 * @returns ArkTS undefined。
 */
napi_value PauseDecoder(
    napi_env env,
    napi_callback_info info) {
  NativeVideoFileDecoder* decoder = UnwrapDecoder(env, info);
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
 * 读取暂停时长并恢复原生文件解码输出。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param info 当前 ArkTS 方法调用的参数与接收对象。
 * @returns ArkTS undefined；参数无效时抛出异常。
 */
napi_value ResumeDecoder(
    napi_env env,
    napi_callback_info info) {
  size_t argumentCount = 1;
  napi_value argument = nullptr;
  napi_value receiver = nullptr;
  if (napi_get_cb_info(
          env, info, &argumentCount, &argument, &receiver, nullptr) != napi_ok ||
      argumentCount != 1) {
    napi_throw_type_error(env, nullptr, "Expected paused duration");
    return nullptr;
  }
  NativeVideoFileDecoder* decoder = nullptr;
  double pausedDurationUs = 0;
  if (napi_unwrap(
          env, receiver, reinterpret_cast<void**>(&decoder)) != napi_ok ||
      decoder == nullptr ||
      napi_get_value_double(env, argument, &pausedDurationUs) != napi_ok ||
      pausedDurationUs < 0) {
    napi_throw_type_error(env, nullptr, "Video decoder resume arguments are invalid");
    return nullptr;
  }
  decoder->Resume(static_cast<int64_t>(pausedDurationUs));
  napi_value result = nullptr;
  napi_get_undefined(env, &result);
  return result;
}

/**
 * 保存原生视频解码器异步释放任务及其 Promise 和实例引用。
 */
struct ReleaseDecoderContext {

  /** 异步任务与释放结果通知 */
  napi_async_work work = nullptr;
  napi_deferred deferred = nullptr;

  /** ArkTS 对象与原生实例所有权 */
  napi_ref decoderReference = nullptr;
  NativeVideoFileDecoder* decoder = nullptr;
};

/**
 * 将原生解码失败原因转换为 ArkTS 错误并拒绝待完成的 Promise。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param deferred 需要完成或拒绝的 ArkTS Promise。
 * @param reason 用于拒绝 Promise 的可读失败原因。
 * @returns 无返回值。
 */
void RejectDecoderPromise(
    napi_env env,
    napi_deferred deferred,
    const char* reason) {
  napi_value message = nullptr;
  napi_value error = nullptr;
  napi_create_string_utf8(
      env, reason, NAPI_AUTO_LENGTH, &message);
  napi_create_error(env, nullptr, message, &error);
  napi_reject_deferred(env, deferred, error);
}

/**
 * 在后台线程停止视频解码，避免阻塞 ArkTS 事件循环。
 *
 * @param data 关联的原生数据包或异步任务上下文。
 * @returns 无返回值。
 */
void ExecuteReleaseDecoder(napi_env, void* data) {
  auto* context = static_cast<ReleaseDecoderContext*>(data);
  if (context != nullptr && context->decoder != nullptr) {
    context->decoder->Stop();
  }
}

/**
 * 在 ArkTS 线程完成释放 Promise，并清理异步任务和实例引用。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param status N-API 异步任务的完成状态。
 * @param data 关联的原生数据包或异步任务上下文。
 * @returns 无返回值。
 */
void CompleteReleaseDecoder(
    napi_env env,
    napi_status status,
    void* data) {
  auto* context = static_cast<ReleaseDecoderContext*>(data);
  if (context == nullptr) {
    return;
  }
  napi_value result = nullptr;
  if (status == napi_ok) {
    napi_get_undefined(env, &result);
    napi_resolve_deferred(env, context->deferred, result);
  } else {
    RejectDecoderPromise(
        env,
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
 * 在 ArkTS 解码器对象回收时删除原生实例并释放媒体资源。
 *
 * @param data 关联的原生数据包或异步任务上下文。
 * @returns 无返回值。
 */
void FinalizeDecoder(napi_env, void* data, void*) {
  delete static_cast<NativeVideoFileDecoder*>(data);
}

/**
 * 释放 ArkTS 对象绑定的原生文件解码器。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param info 当前 ArkTS 方法调用的参数与接收对象。
 * @returns 资源释放后兑现的 ArkTS Promise。
 */
napi_value ReleaseDecoder(
    napi_env env,
    napi_callback_info info) {
  napi_value receiver = nullptr;
  NativeVideoFileDecoder* decoder =
      UnwrapDecoder(env, info, &receiver);
  if (decoder == nullptr || receiver == nullptr) {
    napi_throw_error(env, nullptr, "Video decoder is unavailable");
    return nullptr;
  }

  napi_value promise = nullptr;
  auto* context = new ReleaseDecoderContext();
  context->decoder = decoder;
  if (napi_create_reference(
          env, receiver, 1, &context->decoderReference) != napi_ok ||
      napi_create_promise(
          env, &context->deferred, &promise) != napi_ok) {
    if (context->decoderReference != nullptr) {
      napi_delete_reference(env, context->decoderReference);
    }
    delete context;
    napi_throw_error(env, nullptr, "Failed to prepare video decoder release");
    return nullptr;
  }

  napi_value resourceName = nullptr;
  if (napi_create_string_utf8(
          env,
          "XmaxReleaseNativeVideoFileDecoder",
          NAPI_AUTO_LENGTH,
          &resourceName) != napi_ok ||
      napi_create_async_work(
          env,
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
    RejectDecoderPromise(
        env,
        context->deferred,
        "Failed to queue video decoder release");
    napi_delete_reference(env, context->decoderReference);
    delete context;
    return promise;
  }
  return promise;
}

/**
 * 保存视频解码器异步初始化参数、结果和 ArkTS 通知资源。
 */
struct CreateDecoderContext {

  /** 异步任务与创建结果通知 */
  napi_async_work work = nullptr;
  napi_deferred deferred = nullptr;

  /** ArkTS 对象与原生实例所有权 */
  napi_ref reference = nullptr;
  NativeVideoFileDecoder* decoder = nullptr;

  /** 源文件与播放时间配置 */
  int64_t size = 0;
  int64_t anchorUs = 0;
  int64_t mediaStartUs = 0;

  /** 目标视频格式与帧间隔 */
  int32_t rotation = 0;
  int32_t width = 0;
  int32_t height = 0;
  int64_t frameIntervalUs = 0;
  int64_t cycleDurationUs = 0;

  /** 后台初始化错误 */
  std::string error;
};

/**
 * 在后台线程初始化系统视频解码器，保存初始化结果与错误说明。
 *
 * @param data 关联的原生数据包或异步任务上下文。
 * @returns 无返回值。
 */
void ExecuteCreateDecoder(napi_env, void* data) {
  auto* context = static_cast<CreateDecoderContext*>(data);
  if (!context->decoder->Initialize(context->size, context->anchorUs,
          context->mediaStartUs, context->rotation, context->width, context->height,
          context->frameIntervalUs, context->cycleDurationUs, &context->error)) {
    // Failed initialization may own codec/Surface resources: release them here,
    // not in the completion callback on the UI thread.
    context->decoder->Stop();
  }
}

/**
 * 在 ArkTS 线程兑现或拒绝解码器创建 Promise，并清理异步任务上下文。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param status N-API 异步任务的完成状态。
 * @param data 关联的原生数据包或异步任务上下文。
 * @returns 无返回值。
 */
void CompleteCreateDecoder(napi_env env, napi_status status, void* data) {
  auto* context = static_cast<CreateDecoderContext*>(data);
  if (status != napi_ok || !context->error.empty()) {
    RejectDecoderPromise(env, context->deferred, context->error.empty()
        ? "Failed to initialize the video decoder asynchronously" : context->error.c_str());
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
 * 校验文件与播放参数，异步初始化视频解码器并返回创建结果 Promise。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param info 当前 ArkTS 方法调用的参数与接收对象。
 * @returns 兑现为暂停状态视频解码器的 ArkTS Promise；初始化失败时拒绝。
 */
napi_value CreateVideoFileDecoder(
    napi_env env,
    napi_callback_info info) {
  size_t argumentCount = 10;
  napi_value arguments[10] = {
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      nullptr
  };
  if (napi_get_cb_info(
          env,
          info,
          &argumentCount,
          arguments,
          nullptr,
          nullptr) != napi_ok ||
      argumentCount != 10) {
    napi_throw_type_error(
        env,
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
      napi_get_value_double(
          env, arguments[2], &playbackAnchorUs) != napi_ok ||
      napi_get_value_double(
          env, arguments[3], &mediaStartUs) != napi_ok ||
      napi_get_value_int32(env, arguments[4], &rotation) != napi_ok ||
      napi_get_value_int32(env, arguments[5], &targetWidth) != napi_ok ||
      napi_get_value_int32(env, arguments[6], &targetHeight) != napi_ok ||
      napi_get_value_double(
          env, arguments[7], &frameIntervalUs) != napi_ok ||
      napi_get_value_double(
          env, arguments[8], &cycleDurationUs) != napi_ok ||
      fd < 0 || sizeValue <= 0 ||
      playbackAnchorUs <= 0 ||
      targetWidth <= 0 || targetHeight <= 0 ||
      targetWidth % 2 != 0 || targetHeight % 2 != 0 ||
      frameIntervalUs <= 0 || cycleDurationUs <= 0 ||
      !IsSupportedRotation(rotation) ||
      napi_typeof(env, arguments[9], &listenerType) != napi_ok ||
      listenerType != napi_function) {
    napi_throw_type_error(env, nullptr, "Video file decoder arguments are invalid");
    return nullptr;
  }

  auto* decoder = new NativeVideoFileDecoder();
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
      {
          "pause", nullptr, PauseDecoder, nullptr, nullptr, nullptr,
          napi_default, nullptr
      },
      {
          "resume", nullptr, ResumeDecoder, nullptr, nullptr, nullptr,
          napi_default, nullptr
      },
      {
          "release", nullptr, ReleaseDecoder, nullptr, nullptr, nullptr,
          napi_default, nullptr
      }
  };
  if (napi_define_properties(
      env,
      result,
      sizeof(descriptors) / sizeof(descriptors[0]),
      descriptors) != napi_ok || napi_wrap(
      env,
      result,
      decoder,
      FinalizeDecoder,
      nullptr,
      nullptr) != napi_ok) {
    delete decoder;
    napi_throw_error(env, nullptr, "Failed to bind video decoder handle");
    return nullptr;
  }

  auto* context = new CreateDecoderContext();
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
      napi_create_string_utf8(env, "XmaxCreateNativeVideoFileDecoder", NAPI_AUTO_LENGTH,
          &resourceName) != napi_ok ||
      napi_create_async_work(env, nullptr, resourceName, ExecuteCreateDecoder,
          CompleteCreateDecoder, context, &context->work) != napi_ok ||
      napi_queue_async_work(env, context->work) != napi_ok) {
    // The worker has not run: only the lightweight binding/fd exist here.
    decoder->Stop();
    RejectDecoderPromise(env, context->deferred, "Failed to queue video initialization");
    if (context->reference != nullptr) napi_delete_reference(env, context->reference);
    if (context->work != nullptr) napi_delete_async_work(env, context->work);
    delete context;
  }
  return promise;
}
}  /** namespace */

namespace xmax {
/**
 * 向原生模块导出视频文件解码器的异步创建入口。
 *
 * @param env 当前 ArkTS N-API 执行环境。
 * @param exports 需要挂载 SDK 原生入口的模块导出对象。
 * @returns 无返回值。
 */
void DefineNativeVideoFileDecoder(
    napi_env env,
    napi_value exports) {
  napi_property_descriptor descriptor = {
      "createVideoFileDecoder",
      nullptr,
      CreateVideoFileDecoder,
      nullptr,
      nullptr,
      nullptr,
      napi_default,
      nullptr
  };
  napi_define_properties(env, exports, 1, &descriptor);
}
}  /** namespace xmax */
