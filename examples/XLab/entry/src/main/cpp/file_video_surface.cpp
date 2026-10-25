#include "file_video_surface.h"

#include <cerrno>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <poll.h>
#include <stdexcept>
#include <string>
#include <unistd.h>

#include "multimedia/player_framework/native_avformat.h"
#include "multimedia/video_processing_engine/video_processing.h"
#include "multimedia/video_processing_engine/video_processing_types.h"
#include "native_buffer/native_buffer.h"
#include "native_image/native_image.h"
#include "native_window/external_window.h"

namespace {
void RequireSurface(bool success, const char *message) {
  if (!success) throw std::runtime_error(message);
}

/** Returns mapped pixels, the native reference, and the synchronization fence on every exit path. */
struct SurfaceBuffer {
  OH_NativeImage *surface;
  OHNativeWindowBuffer *window = nullptr;
  OH_NativeBuffer *native = nullptr;
  int fence = -1;
  bool referenced = false, mapped = false;

  ~SurfaceBuffer() {
    if (mapped) OH_NativeBuffer_Unmap(native);
    if (referenced) OH_NativeWindow_NativeObjectUnreference(window);
    if (window) OH_NativeImage_ReleaseNativeWindowBuffer(surface, window, fence);
    else if (fence >= 0) close(fence);
  }
};
}

/** Owns one cycle's processor and Surface; no SDK capture resources are used. */
struct FileVideoSurface::Impl {
  int width, height;
  const std::atomic<bool> &stopping;
  OH_NativeImage *output = nullptr;
  OHNativeWindow *inputWindow = nullptr;
  OH_VideoProcessing *processor = nullptr;
  VideoProcessing_Callback *callbacks = nullptr;
  std::mutex mutex;
  std::condition_variable changed;
  std::deque<uint32_t> outputs;
  std::string error;
  bool started = false, stopped = true, closing = false;

  Impl(int width, int height, const std::atomic<bool> &stopping)
      : width(width), height(height), stopping(stopping) {}

  ~Impl() {
    {
      std::lock_guard<std::mutex> lock(mutex);
      closing = true;
    }
    if (started && OH_VideoProcessing_Stop(processor) == VIDEO_PROCESSING_SUCCESS) {
      std::unique_lock<std::mutex> lock(mutex);
      changed.wait(lock, [this] { return stopped; });
    }

    // Destroy the processor before its callback context and both windows.
    if (processor) OH_VideoProcessing_Destroy(processor);
    if (callbacks) OH_VideoProcessingCallback_Destroy(callbacks);
    if (inputWindow) OH_NativeWindow_DestroyNativeWindow(inputWindow);
    if (output) OH_NativeImage_Destroy(&output);
  }

  static void OnOutput(OH_VideoProcessing *, uint32_t index, void *context) {
    auto &self = *static_cast<Impl *>(context);
    std::lock_guard<std::mutex> lock(self.mutex);
    if (!self.closing) self.outputs.push_back(index);
  }

  static void OnError(OH_VideoProcessing *, VideoProcessing_ErrorCode code, void *context) {
    auto &self = *static_cast<Impl *>(context);
    std::lock_guard<std::mutex> lock(self.mutex);
    if (!self.closing) self.error = "External HDR Surface processing failed: " + std::to_string(code);
  }

  static void OnState(OH_VideoProcessing *, VideoProcessing_State state, void *context) {
    auto &self = *static_cast<Impl *>(context);
    if (state != VIDEO_PROCESSING_STATE_STOPPED) return;
    std::lock_guard<std::mutex> lock(self.mutex);
    self.stopped = true;
    self.changed.notify_all();
  }

  void Prepare() {
    output = OH_ConsumerSurface_Create();
    RequireSurface(output &&
        OH_ConsumerSurface_SetDefaultUsage(output,
            NATIVEBUFFER_USAGE_CPU_READ | NATIVEBUFFER_USAGE_CPU_READ_OFTEN) == 0 &&
        OH_ConsumerSurface_SetDefaultSize(output, width, height) == 0,
        "Configure external HDR output Surface failed");

    OHNativeWindow *outputWindow = OH_NativeImage_AcquireNativeWindow(output);
    RequireSurface(outputWindow &&
        OH_NativeWindow_NativeWindowHandleOpt(outputWindow, SET_FORMAT, NATIVEBUFFER_PIXEL_FMT_YCBCR_420_SP) == 0 &&
        OH_NativeWindow_SetColorSpace(outputWindow, OH_COLORSPACE_BT709_LIMIT) == 0,
        "Configure external HDR output color space failed");

    RequireSurface(OH_VideoProcessing_Create(&processor, VIDEO_PROCESSING_TYPE_DETAIL_ENHANCER) ==
        VIDEO_PROCESSING_SUCCESS && processor, "Create external HDR Surface processor failed");
    OH_AVFormat *parameter = OH_AVFormat_Create();
    const bool configured = parameter &&
        OH_AVFormat_SetIntValue(parameter, VIDEO_DETAIL_ENHANCER_PARAMETER_KEY_QUALITY_LEVEL,
            VIDEO_DETAIL_ENHANCER_QUALITY_LEVEL_NONE) &&
        OH_VideoProcessing_SetParameter(processor, parameter) == VIDEO_PROCESSING_SUCCESS;
    if (parameter) OH_AVFormat_Destroy(parameter);
    RequireSurface(configured, "Configure external HDR Surface processor failed");

    RequireSurface(OH_VideoProcessing_GetSurface(processor, &inputWindow) == VIDEO_PROCESSING_SUCCESS &&
        inputWindow &&
        OH_NativeWindow_NativeWindowHandleOpt(inputWindow, SET_FORMAT, NATIVEBUFFER_PIXEL_FMT_YCBCR_420_SP) == 0 &&
        OH_NativeWindow_SetColorSpace(inputWindow, OH_COLORSPACE_BT709_LIMIT) == 0 &&
        OH_VideoProcessing_SetSurface(processor, outputWindow) == VIDEO_PROCESSING_SUCCESS,
        "Connect external HDR Surfaces failed");

    RequireSurface(OH_VideoProcessingCallback_Create(&callbacks) == VIDEO_PROCESSING_SUCCESS && callbacks &&
        OH_VideoProcessingCallback_BindOnError(callbacks, OnError) == VIDEO_PROCESSING_SUCCESS &&
        OH_VideoProcessingCallback_BindOnState(callbacks, OnState) == VIDEO_PROCESSING_SUCCESS &&
        OH_VideoProcessingCallback_BindOnNewOutputBuffer(callbacks, OnOutput) == VIDEO_PROCESSING_SUCCESS &&
        OH_VideoProcessing_RegisterCallback(processor, callbacks, this) == VIDEO_PROCESSING_SUCCESS,
        "Observe external HDR Surface processor failed");
  }
};

FileVideoSurface::FileVideoSurface(int width, int height, const std::atomic<bool> &stopping)
    : impl_(std::make_unique<Impl>(width, height, stopping)) {
  impl_->Prepare();
}

FileVideoSurface::~FileVideoSurface() = default;

NativeWindow *FileVideoSurface::InputWindow() const { return impl_->inputWindow; }

void FileVideoSurface::Start() {
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->stopped = false;
  }
  RequireSurface(OH_VideoProcessing_Start(impl_->processor) == VIDEO_PROCESSING_SUCCESS,
      "Start external HDR Surface processor failed");
  impl_->started = true;
}

void FileVideoSurface::CheckError() {
  std::lock_guard<std::mutex> lock(impl_->mutex);
  if (!impl_->error.empty()) throw std::runtime_error(impl_->error);
}

bool FileVideoSurface::Read(const PixelConsumer &consume) {
  uint32_t index = 0;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (!impl_->error.empty()) throw std::runtime_error(impl_->error);
    if (impl_->outputs.empty() || impl_->stopping) return false;
    index = impl_->outputs.front();
    impl_->outputs.pop_front();
  }

  // Rendering and returning Surface buffers on the same thread avoids VPE/NativeImage lock inversion.
  RequireSurface(OH_VideoProcessing_RenderOutputBuffer(impl_->processor, index) == VIDEO_PROCESSING_SUCCESS,
      "Render external HDR Surface frame failed");
  SurfaceBuffer buffer{impl_->output};
  RequireSurface(OH_NativeImage_AcquireNativeWindowBuffer(impl_->output, &buffer.window, &buffer.fence) == 0 &&
      buffer.window, "Acquire external HDR Surface frame failed");
  buffer.referenced = OH_NativeWindow_NativeObjectReference(buffer.window) == 0;
  RequireSurface(buffer.referenced, "Retain external HDR Surface frame failed");

  if (buffer.fence >= 0) {
    pollfd descriptor{buffer.fence, POLLIN, 0};
    int result = 0;
    for (int attempt = 0; attempt < 60 && !impl_->stopping; ++attempt) {
      result = poll(&descriptor, 1, 50);
      if (result > 0 || (result < 0 && errno != EINTR)) break;
    }
    if (impl_->stopping) return false;
    RequireSurface(result > 0 && (descriptor.revents & POLLIN), "Wait for external HDR Surface frame failed");
    close(buffer.fence);
    buffer.fence = -1;
  }
  if (impl_->stopping) return false;

  void *address = nullptr;
  OH_NativeBuffer_Planes planes{};
  OH_NativeBuffer_Config config{};
  RequireSurface(OH_NativeBuffer_FromNativeWindowBuffer(buffer.window, &buffer.native) == 0 && buffer.native,
      "Get external HDR native buffer failed");
  buffer.mapped = OH_NativeBuffer_MapPlanes(buffer.native, &address, &planes) == 0;
  OH_NativeBuffer_GetConfig(buffer.native, &config);
  RequireSurface(buffer.mapped && address && planes.planeCount >= 2 &&
      config.format == NATIVEBUFFER_PIXEL_FMT_YCBCR_420_SP &&
      config.width > 0 && config.height > 0 && config.width % 2 == 0 && config.height % 2 == 0 &&
      config.stride >= config.width,
      "External HDR Surface did not output SDR NV12");

  const auto *bytes = static_cast<const uint8_t *>(address);
  consume(bytes + planes.planes[0].offset, config.stride,
      bytes + planes.planes[1].offset, config.stride, config.width, config.height);
  return true;
}
