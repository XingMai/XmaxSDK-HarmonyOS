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
#include <sys/stat.h>
#include <unistd.h>

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
struct DecodedFramePacket {
  std::vector<uint8_t> data;
  int32_t width = 0;
  int32_t height = 0;
  int32_t stride = 0;
  int64_t timestampUs = 0;
  bool endOfStream = false;
  std::string error;
};

struct HdrSurfaceBufferPacket {
  OHNativeWindowBuffer* windowBuffer = nullptr;
  int fenceFd = -1;
};

bool IsSupportedRotation(int32_t rotation) {
  return rotation == 0 || rotation == 90 ||
      rotation == 180 || rotation == 270;
}

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

class NativeVideoFileDecoder {
 public:
  NativeVideoFileDecoder() = default;

  ~NativeVideoFileDecoder() {
    Stop();
  }

  bool Initialize(
      napi_env env,
      napi_value listener,
      int32_t sourceFd,
      int64_t sourceSize,
      int64_t playbackAnchorUs,
      int64_t mediaStartUs,
      int32_t rotation,
      int32_t targetWidth,
      int32_t targetHeight,
      int64_t frameIntervalUs,
      std::string* error) {
    playbackAnchorUs_ = playbackAnchorUs;
    mediaStartUs_ = mediaStartUs;
    rotation_ = rotation;
    targetWidth_ = targetWidth;
    targetHeight_ = targetHeight;
    frameIntervalUs_ = frameIntervalUs;

    fd_ = dup(sourceFd);
    if (fd_ < 0) {
      *error = "复制视频文件描述符失败";
      return false;
    }

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

    decoder_ = OH_VideoDecoder_CreateByMime(mime);
    if (decoder_ == nullptr) {
      *error = "当前设备不支持所选视频编码";
      return false;
    }
    if (isHdrVivid_ && !InitializeHdrOutputSurface(error)) {
      return false;
    }

    napi_value resourceName = nullptr;
    if (napi_create_string_utf8(
            env,
            "XmaxNativeVideoFileDecoder",
            NAPI_AUTO_LENGTH,
            &resourceName) != napi_ok ||
        napi_create_threadsafe_function(
            env,
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

    const OH_AVCodecCallback callbacks{
        OnError,
        OnStreamChanged,
        OnNeedInputBuffer,
        OnNewOutputBuffer
    };
    if (OH_VideoDecoder_RegisterCallback(
            decoder_, callbacks, this) != AV_ERR_OK ||
        OH_VideoDecoder_Configure(decoder_, trackFormat_) != AV_ERR_OK) {
      *error = "配置 NV12 视频连续解码失败";
      return false;
    }
    if (isHdrVivid_ &&
        OH_VideoDecoder_SetSurface(
            decoder_, hdrProcessorInputWindow_) != AV_ERR_OK) {
      *error = "绑定 HDR Vivid SDR 输出 Surface 失败";
      return false;
    }
    if (OH_VideoDecoder_Prepare(decoder_) != AV_ERR_OK) {
      *error = "准备 NV12 视频连续解码失败";
      return false;
    }

    running_.store(true);
    if (isHdrVivid_) {
      hdrSurfaceWorkerRunning_.store(true);
      hdrSurfaceWorker_ =
          std::thread(&NativeVideoFileDecoder::HdrSurfaceWorkerLoop, this);
    }
    if (OH_VideoDecoder_Start(decoder_) != AV_ERR_OK) {
      running_.store(false);
      hdrSurfaceWorkerRunning_.store(false);
      hdrSurfaceCondition_.notify_all();
      if (hdrSurfaceWorker_.joinable()) {
        hdrSurfaceWorker_.join();
      }
      *error = "启动视频连续解码失败";
      return false;
    }
    if (isHdrVivid_) {
      {
        std::lock_guard<std::mutex> lock(hdrProcessingStateMutex_);
        hdrVideoProcessorStopped_ = false;
      }
      const VideoProcessing_ErrorCode processingResult =
          OH_VideoProcessing_Start(hdrVideoProcessor_);
      if (processingResult != VIDEO_PROCESSING_SUCCESS) {
        {
          std::lock_guard<std::mutex> lock(hdrProcessingStateMutex_);
          hdrVideoProcessorStopped_ = true;
        }
        OH_VideoDecoder_Stop(decoder_);
        running_.store(false);
        hdrSurfaceWorkerRunning_.store(false);
        hdrSurfaceCondition_.notify_all();
        if (hdrSurfaceWorker_.joinable()) {
          hdrSurfaceWorker_.join();
        }
        *error = "启动 HDR Vivid 视频缩放失败：" +
            std::to_string(processingResult);
        return false;
      }
      hdrVideoProcessorStarted_ = true;
    }
    return true;
  }

  void Stop() {
    const bool wasRunning = running_.exchange(false);
    pacingCondition_.notify_all();

    {
      std::lock_guard<std::mutex> lock(demuxerMutex_);
    }

    if (decoder_ != nullptr) {
      if (wasRunning) {
        OH_VideoDecoder_Stop(decoder_);
      }
      StopHdrVideoProcessor();
      hdrSurfaceWorkerRunning_.store(false);
      hdrSurfaceCondition_.notify_all();
      if (hdrSurfaceWorker_.joinable()) {
        hdrSurfaceWorker_.join();
      }
      OH_VideoDecoder_Destroy(decoder_);
      decoder_ = nullptr;
    } else if (hdrSurfaceWorker_.joinable()) {
      hdrSurfaceWorkerRunning_.store(false);
      hdrSurfaceCondition_.notify_all();
      hdrSurfaceWorker_.join();
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
    ReleaseHdrOutputSurface();
  }

 private:
  bool InitializeHdrOutputSurface(std::string* error) {
    const bool swapsDimensions = rotation_ == 90 || rotation_ == 270;
    hdrSurfaceWidth_ = swapsDimensions ? targetHeight_ : targetWidth_;
    hdrSurfaceHeight_ = swapsDimensions ? targetWidth_ : targetHeight_;
    hdrOutputSurface_ = OH_ConsumerSurface_Create();
    if (hdrOutputSurface_ == nullptr) {
      *error = "创建 HDR Vivid SDR 输出 Surface 失败";
      return false;
    }
    if (OH_ConsumerSurface_SetDefaultUsage(
        hdrOutputSurface_,
        NATIVEBUFFER_USAGE_CPU_READ |
            NATIVEBUFFER_USAGE_CPU_READ_OFTEN) != 0 ||
        OH_ConsumerSurface_SetDefaultSize(
            hdrOutputSurface_, hdrSurfaceWidth_, hdrSurfaceHeight_) != 0) {
      *error = "配置 HDR Vivid SDR 输出 Surface 失败";
      ReleaseHdrOutputSurface();
      return false;
    }
    hdrOutputWindow_ = OH_NativeImage_AcquireNativeWindow(
        hdrOutputSurface_);
    if (hdrOutputWindow_ == nullptr ||
        OH_NativeWindow_NativeWindowHandleOpt(
            hdrOutputWindow_,
            SET_FORMAT,
            NATIVEBUFFER_PIXEL_FMT_YCBCR_420_SP) != 0 ||
        OH_NativeWindow_SetColorSpace(
            hdrOutputWindow_, OH_COLORSPACE_BT709_LIMIT) != 0) {
      *error = "配置 HDR Vivid SDR 输出格式失败";
      ReleaseHdrOutputSurface();
      return false;
    }
    const OH_OnFrameAvailableListener listener{
        this,
        OnHdrFrameAvailable
    };
    if (OH_NativeImage_SetOnFrameAvailableListener(
            hdrOutputSurface_, listener) != 0) {
      *error = "注册 HDR Vivid SDR 帧回调失败";
      ReleaseHdrOutputSurface();
      return false;
    }

    VideoProcessing_ErrorCode processingResult =
        OH_VideoProcessing_Create(
            &hdrVideoProcessor_,
            VIDEO_PROCESSING_TYPE_DETAIL_ENHANCER);
    if (processingResult != VIDEO_PROCESSING_SUCCESS ||
        hdrVideoProcessor_ == nullptr) {
      *error = "创建 HDR Vivid 视频缩放器失败：" +
          std::to_string(processingResult);
      ReleaseHdrOutputSurface();
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
      *error = "配置 HDR Vivid 视频缩放参数失败";
      ReleaseHdrOutputSurface();
      return false;
    }
    processingResult = OH_VideoProcessing_SetParameter(
        hdrVideoProcessor_, processingParameter);
    OH_AVFormat_Destroy(processingParameter);
    if (processingResult != VIDEO_PROCESSING_SUCCESS ||
        OH_VideoProcessing_GetSurface(
            hdrVideoProcessor_, &hdrProcessorInputWindow_) !=
            VIDEO_PROCESSING_SUCCESS ||
        hdrProcessorInputWindow_ == nullptr ||
        OH_NativeWindow_NativeWindowHandleOpt(
            hdrProcessorInputWindow_,
            SET_FORMAT,
            NATIVEBUFFER_PIXEL_FMT_YCBCR_420_SP) != 0 ||
        OH_NativeWindow_SetColorSpace(
            hdrProcessorInputWindow_, OH_COLORSPACE_BT709_LIMIT) != 0 ||
        OH_VideoProcessing_SetSurface(
            hdrVideoProcessor_, hdrOutputWindow_) !=
            VIDEO_PROCESSING_SUCCESS) {
      *error = "连接 HDR Vivid 视频缩放 Surface 失败：" +
          std::to_string(processingResult);
      ReleaseHdrOutputSurface();
      return false;
    }

    processingResult =
        OH_VideoProcessingCallback_Create(&hdrProcessingCallback_);
    if (processingResult != VIDEO_PROCESSING_SUCCESS ||
        hdrProcessingCallback_ == nullptr ||
        OH_VideoProcessingCallback_BindOnError(
            hdrProcessingCallback_, OnHdrProcessingError) !=
            VIDEO_PROCESSING_SUCCESS ||
        OH_VideoProcessingCallback_BindOnState(
            hdrProcessingCallback_, OnHdrProcessingState) !=
            VIDEO_PROCESSING_SUCCESS ||
        OH_VideoProcessing_RegisterCallback(
            hdrVideoProcessor_, hdrProcessingCallback_, this) !=
            VIDEO_PROCESSING_SUCCESS) {
      *error = "注册 HDR Vivid 视频缩放回调失败：" +
          std::to_string(processingResult);
      ReleaseHdrOutputSurface();
      return false;
    }
    return true;
  }

  void StopHdrVideoProcessor() {
    if (!hdrVideoProcessorStarted_ || hdrVideoProcessor_ == nullptr) {
      return;
    }
    const VideoProcessing_ErrorCode stopResult =
        OH_VideoProcessing_Stop(hdrVideoProcessor_);
    if (stopResult == VIDEO_PROCESSING_SUCCESS) {
      std::unique_lock<std::mutex> lock(hdrProcessingStateMutex_);
      hdrProcessingStateCondition_.wait(
          lock, [this] { return hdrVideoProcessorStopped_; });
    }
    hdrVideoProcessorStarted_ = false;
  }

  void ReleaseHdrOutputSurface() {
    StopHdrVideoProcessor();
    std::lock_guard<std::mutex> surfaceLock(hdrSurfaceMutex_);
    if (hdrVideoProcessor_ != nullptr) {
      OH_VideoProcessing_Destroy(hdrVideoProcessor_);
      hdrVideoProcessor_ = nullptr;
    }
    if (hdrProcessingCallback_ != nullptr) {
      OH_VideoProcessingCallback_Destroy(hdrProcessingCallback_);
      hdrProcessingCallback_ = nullptr;
    }
    if (hdrProcessorInputWindow_ != nullptr) {
      OH_NativeWindow_DestroyNativeWindow(hdrProcessorInputWindow_);
      hdrProcessorInputWindow_ = nullptr;
    }
    if (hdrOutputSurface_ != nullptr) {
      OH_NativeImage_UnsetOnFrameAvailableListener(hdrOutputSurface_);
      hdrOutputWindow_ = nullptr;
      OH_NativeImage_Destroy(&hdrOutputSurface_);
    }
    std::lock_guard<std::mutex> lock(hdrTimestampMutex_);
    pendingHdrTimestamps_.clear();
    hdrEndOfStreamPending_ = false;
  }

  static void OnHdrFrameAvailable(void* context) {
    auto* decoder = static_cast<NativeVideoFileDecoder*>(context);
    if (decoder != nullptr) {
      decoder->EnqueueHdrSurfaceFrame();
    }
  }

  static void OnHdrProcessingError(
      OH_VideoProcessing*,
      VideoProcessing_ErrorCode error,
      void* context) {
    auto* decoder = static_cast<NativeVideoFileDecoder*>(context);
    if (decoder != nullptr) {
      decoder->ReportError(
          "HDR Vivid 视频缩放失败：" + std::to_string(error));
    }
  }

  static void OnHdrProcessingState(
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
          decoder->hdrProcessingStateMutex_);
      decoder->hdrVideoProcessorStopped_ = true;
    }
    decoder->hdrProcessingStateCondition_.notify_all();
  }

  void EnqueueHdrSurfaceFrame() {
    std::lock_guard<std::mutex> surfaceLock(hdrSurfaceMutex_);
    if (!hdrSurfaceWorkerRunning_.load() || hdrOutputSurface_ == nullptr) {
      return;
    }
    OHNativeWindowBuffer* windowBuffer = nullptr;
    int fenceFd = -1;
    if (OH_NativeImage_AcquireNativeWindowBuffer(
            hdrOutputSurface_, &windowBuffer, &fenceFd) != 0 ||
        windowBuffer == nullptr) {
      if (fenceFd >= 0) {
        close(fenceFd);
      }
      ReportError("读取 HDR Vivid SDR Surface 帧失败");
      return;
    }
    if (OH_NativeWindow_NativeObjectReference(windowBuffer) != 0) {
      if (fenceFd >= 0) {
        close(fenceFd);
      }
      OH_NativeImage_ReleaseNativeWindowBuffer(
          hdrOutputSurface_, windowBuffer, -1);
      ReportError("持有 HDR Vivid SDR Surface 帧失败");
      return;
    }
    {
      std::lock_guard<std::mutex> lock(hdrSurfaceQueueMutex_);
      hdrSurfaceQueue_.push_back({windowBuffer, fenceFd});
    }
    hdrSurfaceCondition_.notify_one();
  }

  void HdrSurfaceWorkerLoop() {
    while (true) {
      HdrSurfaceBufferPacket packet;
      {
        std::unique_lock<std::mutex> lock(hdrSurfaceQueueMutex_);
        hdrSurfaceCondition_.wait(lock, [this] {
          return !hdrSurfaceWorkerRunning_.load() ||
              !hdrSurfaceQueue_.empty();
        });
        if (hdrSurfaceQueue_.empty()) {
          if (!hdrSurfaceWorkerRunning_.load()) {
            return;
          }
          continue;
        }
        packet = hdrSurfaceQueue_.front();
        hdrSurfaceQueue_.pop_front();
      }
      HandleHdrSurfaceFrame(packet.windowBuffer, packet.fenceFd);
    }
  }

  void HandleHdrSurfaceFrame(
      OHNativeWindowBuffer* windowBuffer,
      int fenceFd) {
    OH_NativeImage* outputSurface = hdrOutputSurface_;
    const auto releaseWindowBuffer =
        [this, outputSurface, windowBuffer]() {
      std::lock_guard<std::mutex> surfaceLock(hdrSurfaceMutex_);
      OH_NativeWindow_NativeObjectUnreference(windowBuffer);
      OH_NativeImage_ReleaseNativeWindowBuffer(
          outputSurface, windowBuffer, -1);
    };
    if (!running_.load() || outputSurface == nullptr) {
      if (fenceFd >= 0) {
        close(fenceFd);
      }
      if (outputSurface != nullptr) {
        releaseWindowBuffer();
      } else {
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
        releaseWindowBuffer();
        return;
      }
      if (waitResult <= 0) {
        releaseWindowBuffer();
        ReportError("等待 HDR Vivid SDR Surface 帧超时");
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
        config.width <= 0 || config.height <= 0 ||
        config.stride < config.width) {
      if (mapped) {
        OH_NativeBuffer_Unmap(nativeBuffer);
      }
      releaseWindowBuffer();
      ReportError("访问 HDR Vivid SDR NV12 帧失败");
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
        &hdrSourceData_);
    OH_NativeBuffer_Unmap(nativeBuffer);
    releaseWindowBuffer();

    const bool swapsDimensions = rotation_ == 90 || rotation_ == 270;
    const int32_t scaledWidth =
        swapsDimensions ? targetHeight_ : targetWidth_;
    const int32_t scaledHeight =
        swapsDimensions ? targetWidth_ : targetHeight_;
    const size_t sourceLumaLength =
        static_cast<size_t>(config.width) * config.height;
    ScaleNv12(
        hdrSourceData_.data(),
        config.width,
        hdrSourceData_.data() + sourceLumaLength,
        config.width,
        config.width,
        config.height,
        scaledWidth,
        scaledHeight,
        &hdrScaledData_);

    std::vector<uint8_t> frameData;
    if (rotation_ == 0) {
      frameData = hdrScaledData_;
    } else {
      const size_t scaledLumaLength =
          static_cast<size_t>(scaledWidth) * scaledHeight;
      CopyOrRotateNv12(
          hdrScaledData_.data(),
          scaledWidth,
          hdrScaledData_.data() + scaledLumaLength,
          scaledWidth,
          scaledWidth,
          scaledHeight,
          rotation_,
          &frameData);
    }

    int64_t timestampUs = 0;
    bool dispatchEndOfStream = false;
    {
      std::lock_guard<std::mutex> lock(hdrTimestampMutex_);
      if (pendingHdrTimestamps_.empty()) {
        return;
      }
      timestampUs = pendingHdrTimestamps_.front();
      pendingHdrTimestamps_.pop_front();
      dispatchEndOfStream =
          pendingHdrTimestamps_.empty() && hdrEndOfStreamPending_;
      if (dispatchEndOfStream) {
        hdrEndOfStreamPending_ = false;
      }
    }
    auto* packet = new DecodedFramePacket();
    packet->width = targetWidth_;
    packet->height = targetHeight_;
    packet->stride = packet->width;
    packet->timestampUs = timestampUs;
    packet->data = std::move(frameData);
    Dispatch(packet);
    if (dispatchEndOfStream) {
      auto* endPacket = new DecodedFramePacket();
      endPacket->endOfStream = true;
      Dispatch(endPacket);
    }
  }

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

    OH_AVErrCode readResult = AV_ERR_OK;
    OH_AVErrCode pushResult = AV_ERR_OK;
    {
      std::lock_guard<std::mutex> lock(decoder->demuxerMutex_);
      if (!decoder->running_.load() || decoder->inputEnded_) {
        return;
      }
      readResult = OH_AVDemuxer_ReadSampleBuffer(
          decoder->demuxer_, decoder->trackIndex_, buffer);
      if (readResult == AV_ERR_OK) {
        OH_AVCodecBufferAttr attr{};
        const bool endOfStream =
            OH_AVBuffer_GetBufferAttr(buffer, &attr) == AV_ERR_OK &&
            (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0;
        pushResult = OH_VideoDecoder_PushInputBuffer(codec, index);
        if (pushResult == AV_ERR_OK) {
          decoder->inputEnded_ = endOfStream;
        }
      }
    }
    if (readResult != AV_ERR_OK) {
      decoder->ReportError(
          "读取视频压缩帧失败：" + std::to_string(readResult));
      return;
    }
    if (pushResult != AV_ERR_OK) {
      decoder->ReportError(
          "提交视频压缩帧失败：" + std::to_string(pushResult));
    }
  }

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
    if (decoder->isHdrVivid_) {
      decoder->HandleHdrOutputBuffer(codec, index, buffer);
      return;
    }
    if (buffer == nullptr) {
      OH_VideoDecoder_FreeOutputBuffer(codec, index);
      return;
    }
    decoder->HandleOutputBuffer(buffer);
    OH_VideoDecoder_FreeOutputBuffer(codec, index);
  }

  void HandleHdrOutputBuffer(
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
      ReportError("读取 HDR Vivid 解码帧属性失败");
      return;
    }
    if ((attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0) {
      OH_VideoDecoder_FreeOutputBuffer(codec, index);
      bool dispatchEndOfStream = false;
      {
        std::lock_guard<std::mutex> lock(hdrTimestampMutex_);
        if (pendingHdrTimestamps_.empty()) {
          dispatchEndOfStream = true;
        } else {
          hdrEndOfStreamPending_ = true;
        }
      }
      if (dispatchEndOfStream) {
        auto* packet = new DecodedFramePacket();
        packet->endOfStream = true;
        Dispatch(packet);
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
      std::lock_guard<std::mutex> lock(hdrTimestampMutex_);
      pendingHdrTimestamps_.push_back(timestampUs);
    }
    if (OH_VideoDecoder_RenderOutputBuffer(codec, index) != AV_ERR_OK) {
      {
        std::lock_guard<std::mutex> lock(hdrTimestampMutex_);
        if (!pendingHdrTimestamps_.empty() &&
            pendingHdrTimestamps_.back() == timestampUs) {
          pendingHdrTimestamps_.pop_back();
        }
      }
      ReportError("渲染 HDR Vivid SDR Surface 帧失败");
    }
  }

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

  void Pace(int64_t timestampUs) {
    const auto deadline = std::chrono::steady_clock::time_point(
        std::chrono::microseconds(
            PlaybackTimestampUs(timestampUs)));

    std::unique_lock<std::mutex> lock(pacingMutex_);
    pacingCondition_.wait_until(lock, deadline, [this] {
      return !running_.load();
    });
  }

  bool ShouldOutputFrame(int64_t mediaTimestampUs) {
    if (lastOutputMediaTimestampUs_ >= 0 &&
        mediaTimestampUs - lastOutputMediaTimestampUs_ <
            frameIntervalUs_ * 3 / 4) {
      return false;
    }
    lastOutputMediaTimestampUs_ = mediaTimestampUs;
    return true;
  }

  int64_t PlaybackTimestampUs(int64_t mediaTimestampUs) const {
    return playbackAnchorUs_ + std::max<int64_t>(
        mediaTimestampUs - mediaStartUs_,
        0);
  }

  void ReportError(const std::string& message) {
    if (reportedError_.exchange(true)) {
      return;
    }
    auto* packet = new DecodedFramePacket();
    packet->error = message;
    Dispatch(packet);
  }

  void Dispatch(DecodedFramePacket* packet) {
    if (listener_ == nullptr ||
        napi_call_threadsafe_function(
            listener_, packet, napi_tsfn_blocking) != napi_ok) {
      delete packet;
    }
  }

  static void FinalizeFrameData(
      napi_env,
      void*,
      void* hint) {
    delete static_cast<std::vector<uint8_t>*>(hint);
  }

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

  int32_t fd_ = -1;
  OH_AVSource* source_ = nullptr;
  OH_AVDemuxer* demuxer_ = nullptr;
  OH_AVCodec* decoder_ = nullptr;
  OH_AVFormat* trackFormat_ = nullptr;
  uint32_t trackIndex_ = 0;
  napi_threadsafe_function listener_ = nullptr;

  std::atomic<bool> running_{false};
  std::atomic<bool> reportedError_{false};
  std::mutex demuxerMutex_;
  bool inputEnded_ = false;
  std::mutex formatMutex_;
  int32_t width_ = 0;
  int32_t height_ = 0;
  int32_t stride_ = 0;
  int32_t sliceHeight_ = 0;
  int32_t pixelFormat_ = 0;
  bool isHdrVivid_ = false;
  int32_t hdrSurfaceWidth_ = 0;
  int32_t hdrSurfaceHeight_ = 0;
  OH_VideoProcessing* hdrVideoProcessor_ = nullptr;
  VideoProcessing_Callback* hdrProcessingCallback_ = nullptr;
  OHNativeWindow* hdrProcessorInputWindow_ = nullptr;
  bool hdrVideoProcessorStarted_ = false;
  bool hdrVideoProcessorStopped_ = true;
  std::mutex hdrProcessingStateMutex_;
  std::condition_variable hdrProcessingStateCondition_;
  OH_NativeImage* hdrOutputSurface_ = nullptr;
  OHNativeWindow* hdrOutputWindow_ = nullptr;
  std::mutex hdrSurfaceMutex_;
  std::mutex hdrSurfaceQueueMutex_;
  std::condition_variable hdrSurfaceCondition_;
  std::deque<HdrSurfaceBufferPacket> hdrSurfaceQueue_;
  std::atomic<bool> hdrSurfaceWorkerRunning_{false};
  std::thread hdrSurfaceWorker_;
  std::mutex hdrTimestampMutex_;
  std::deque<int64_t> pendingHdrTimestamps_;
  bool hdrEndOfStreamPending_ = false;
  std::vector<uint8_t> hdrSourceData_;
  std::vector<uint8_t> hdrScaledData_;

  std::mutex pacingMutex_;
  std::condition_variable pacingCondition_;
  int64_t playbackAnchorUs_ = 0;
  int64_t mediaStartUs_ = 0;
  int32_t rotation_ = 0;
  int32_t targetWidth_ = 0;
  int32_t targetHeight_ = 0;
  int64_t frameIntervalUs_ = 0;
  int64_t lastOutputMediaTimestampUs_ = -1;
};

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

struct ReleaseDecoderContext {
  napi_async_work work = nullptr;
  napi_deferred deferred = nullptr;
  napi_ref decoderReference = nullptr;
  NativeVideoFileDecoder* decoder = nullptr;
};

void RejectReleaseDecoder(
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

void ExecuteReleaseDecoder(napi_env, void* data) {
  auto* context = static_cast<ReleaseDecoderContext*>(data);
  if (context != nullptr && context->decoder != nullptr) {
    context->decoder->Stop();
  }
}

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
    RejectReleaseDecoder(
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

void FinalizeDecoder(napi_env, void* data, void*) {
  delete static_cast<NativeVideoFileDecoder*>(data);
}

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
    RejectReleaseDecoder(
        env,
        context->deferred,
        "Failed to queue video decoder release");
    napi_delete_reference(env, context->decoderReference);
    delete context;
    return promise;
  }
  return promise;
}

napi_value CreateVideoFileDecoder(
    napi_env env,
    napi_callback_info info) {
  size_t argumentCount = 9;
  napi_value arguments[9] = {
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
      argumentCount != 9) {
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
      fd < 0 || sizeValue <= 0 ||
      playbackAnchorUs <= 0 ||
      targetWidth <= 0 || targetHeight <= 0 ||
      targetWidth % 2 != 0 || targetHeight % 2 != 0 ||
      frameIntervalUs <= 0 ||
      !IsSupportedRotation(rotation) ||
      napi_typeof(env, arguments[8], &listenerType) != napi_ok ||
      listenerType != napi_function) {
    napi_throw_type_error(env, nullptr, "Video file decoder arguments are invalid");
    return nullptr;
  }

  auto* decoder = new NativeVideoFileDecoder();
  std::string error;
  if (!decoder->Initialize(
          env,
          arguments[8],
          fd,
          static_cast<int64_t>(sizeValue),
          static_cast<int64_t>(playbackAnchorUs),
          static_cast<int64_t>(mediaStartUs),
          rotation,
          targetWidth,
          targetHeight,
          static_cast<int64_t>(frameIntervalUs),
          &error)) {
    delete decoder;
    napi_throw_error(env, nullptr, error.c_str());
    return nullptr;
  }

  napi_value result = nullptr;
  napi_create_object(env, &result);
  napi_property_descriptor descriptor = {
      "release",
      nullptr,
      ReleaseDecoder,
      nullptr,
      nullptr,
      nullptr,
      napi_default,
      nullptr
  };
  napi_define_properties(env, result, 1, &descriptor);
  napi_wrap(
      env,
      result,
      decoder,
      FinalizeDecoder,
      nullptr,
      nullptr);
  return result;
}
}  // namespace

namespace xmax {
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
}  // namespace xmax
