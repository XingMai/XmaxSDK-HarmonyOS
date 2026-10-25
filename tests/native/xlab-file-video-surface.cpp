#include <algorithm>
#include <atomic>
#include <cassert>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <numeric>
#include <stdexcept>
#include <string>
#include <thread>
#include <unistd.h>
#include <vector>

using VideoProcessing_ErrorCode = int;
using VideoProcessing_State = int;
constexpr int VIDEO_PROCESSING_SUCCESS = 0, VIDEO_PROCESSING_STATE_STOPPED = 1;
constexpr int VIDEO_PROCESSING_TYPE_DETAIL_ENHANCER = 2, VIDEO_DETAIL_ENHANCER_QUALITY_LEVEL_NONE = 0;
constexpr int NATIVEBUFFER_USAGE_CPU_READ = 1, NATIVEBUFFER_USAGE_CPU_READ_OFTEN = 2;
constexpr int NATIVEBUFFER_PIXEL_FMT_YCBCR_420_SP = 24, SET_FORMAT = 1, OH_COLORSPACE_BT709_LIMIT = 3;
const char *VIDEO_DETAIL_ENHANCER_PARAMETER_KEY_QUALITY_LEVEL = "quality";

struct NativeWindow { int format = 0, color = 0; };
using OHNativeWindow = NativeWindow;
struct OHNativeWindowBuffer {};
struct OH_NativeBuffer {};
struct OH_NativeImage { NativeWindow window; };
struct OH_AVFormat {};
struct OH_NativeBuffer_Config { int width, height, format, usage, stride; };
struct OH_NativeBuffer_Plane { uint64_t offset; uint32_t rowStride, columnStride; };
struct OH_NativeBuffer_Planes { int planeCount; OH_NativeBuffer_Plane planes[4]; };
struct OH_VideoProcessing;
struct VideoProcessing_Callback {
  void (*output)(OH_VideoProcessing *, uint32_t, void *) = nullptr;
  void (*state)(OH_VideoProcessing *, int, void *) = nullptr;
  void (*error)(OH_VideoProcessing *, int, void *) = nullptr;
};
struct OH_VideoProcessing {
  VideoProcessing_Callback *callback = nullptr;
  void *context = nullptr;
};
OH_VideoProcessing *processor = nullptr;
OHNativeWindowBuffer windowBuffer;
OH_NativeBuffer nativeBuffer;
std::vector<uint8_t> pixels(48, 253);
int images = 0, processors = 0, callbacks = 0, windows = 0, starts = 0, stops = 0;
int acquired = 0, released = 0, referenced = 0, mapped = 0, rendered = 0, decoderRendered = 0, freed = 0;
int failStage = 0, pixelFormat = 24;
int pendingFence = -1;
int requestedWidth = 0, requestedHeight = 0;

OH_NativeImage *OH_ConsumerSurface_Create() { images++; return new OH_NativeImage; }
int OH_ConsumerSurface_SetDefaultUsage(OH_NativeImage *, int) { return 0; }
int OH_ConsumerSurface_SetDefaultSize(OH_NativeImage *, int width, int height) {
  requestedWidth = width; requestedHeight = height; return 0;
}
OHNativeWindow *OH_NativeImage_AcquireNativeWindow(OH_NativeImage *image) { return &image->window; }
int OH_NativeWindow_NativeWindowHandleOpt(OHNativeWindow *window, int, int format) { window->format = format; return 0; }
int OH_NativeWindow_SetColorSpace(OHNativeWindow *window, int color) { window->color = color; return 0; }
int OH_VideoProcessing_Create(OH_VideoProcessing **value, int) {
  processors++; *value = new OH_VideoProcessing; processor = *value; return 0;
}
OH_AVFormat *OH_AVFormat_Create() { return new OH_AVFormat; }
bool OH_AVFormat_SetIntValue(OH_AVFormat *, const char *, int) { return true; }
void OH_AVFormat_Destroy(OH_AVFormat *format) { delete format; }
int OH_VideoProcessing_SetParameter(OH_VideoProcessing *, OH_AVFormat *) { return failStage == 1 ? 9 : 0; }
int OH_VideoProcessing_GetSurface(OH_VideoProcessing *, OHNativeWindow **window) {
  windows++; *window = new NativeWindow; return 0;
}
int OH_VideoProcessing_SetSurface(OH_VideoProcessing *, OHNativeWindow *window) {
  assert(window->format == 24 && window->color == OH_COLORSPACE_BT709_LIMIT); return 0;
}
int OH_VideoProcessingCallback_Create(VideoProcessing_Callback **value) {
  callbacks++; *value = new VideoProcessing_Callback; return 0;
}
int OH_VideoProcessingCallback_BindOnError(VideoProcessing_Callback *value, decltype(value->error) callback) {
  value->error = callback; return 0;
}
int OH_VideoProcessingCallback_BindOnState(VideoProcessing_Callback *value, decltype(value->state) callback) {
  value->state = callback; return 0;
}
int OH_VideoProcessingCallback_BindOnNewOutputBuffer(VideoProcessing_Callback *value, decltype(value->output) callback) {
  value->output = callback; return 0;
}
int OH_VideoProcessing_RegisterCallback(OH_VideoProcessing *value, VideoProcessing_Callback *callback, void *context) {
  value->callback = callback; value->context = context; return 0;
}
int OH_VideoProcessing_Start(OH_VideoProcessing *) { starts++; return 0; }
int OH_VideoProcessing_Stop(OH_VideoProcessing *value) {
  assert(mapped == 0 && acquired == released && referenced == 0);
  stops++; value->callback->state(value, VIDEO_PROCESSING_STATE_STOPPED, value->context); return 0;
}
int OH_VideoProcessing_Destroy(OH_VideoProcessing *value) {
  processors--; delete value; processor = nullptr; return 0;
}
int OH_VideoProcessingCallback_Destroy(VideoProcessing_Callback *value) { callbacks--; delete value; return 0; }
int OH_NativeWindow_DestroyNativeWindow(OHNativeWindow *window) { windows--; delete window; return 0; }
int OH_NativeImage_Destroy(OH_NativeImage **image) { images--; delete *image; *image = nullptr; return 0; }
int OH_VideoProcessing_RenderOutputBuffer(OH_VideoProcessing *, uint32_t) { rendered++; return failStage == 2 ? 9 : 0; }
int OH_NativeImage_AcquireNativeWindowBuffer(OH_NativeImage *, OHNativeWindowBuffer **buffer, int *fence) {
  if (failStage == 3) return 9;
  acquired++; *buffer = &windowBuffer; *fence = pendingFence; pendingFence = -1; return 0;
}
int OH_NativeWindow_NativeObjectReference(OHNativeWindowBuffer *) {
  if (failStage == 4) return 9;
  referenced++; return 0;
}
int OH_NativeWindow_NativeObjectUnreference(OHNativeWindowBuffer *) { referenced--; return 0; }
int OH_NativeImage_ReleaseNativeWindowBuffer(OH_NativeImage *, OHNativeWindowBuffer *, int fence) {
  if (fence >= 0) close(fence);
  released++; return 0;
}
int OH_NativeBuffer_FromNativeWindowBuffer(OHNativeWindowBuffer *, OH_NativeBuffer **buffer) {
  *buffer = &nativeBuffer; return 0;
}
int OH_NativeBuffer_MapPlanes(OH_NativeBuffer *, void **address, OH_NativeBuffer_Planes *planes) {
  if (failStage == 5) return 9;
  mapped++; *address = pixels.data(); *planes = {3, {{0, 1, 8}, {32, 2, 8}, {33, 2, 8}}}; return 0;
}
void OH_NativeBuffer_GetConfig(OH_NativeBuffer *, OH_NativeBuffer_Config *config) { *config = {4, 2, pixelFormat, 0, 8}; }
int OH_NativeBuffer_Unmap(OH_NativeBuffer *) { mapped--; return 0; }

// FILE_VIDEO_SURFACE_HEADER
// FILE_VIDEO_SURFACE_IMPLEMENTATION

struct OH_AVCodecBufferAttr { int64_t pts; int size, flags; };
struct OH_AVBuffer { OH_AVCodecBufferAttr attr; };
constexpr int AV_ERR_OK = 0, AVCODEC_BUFFER_FLAGS_EOS = 1;
int OH_AVBuffer_GetBufferAttr(OH_AVBuffer *buffer, OH_AVCodecBufferAttr *attr) { *attr = buffer->attr; return 0; }
int OH_VideoDecoder_RenderOutputBuffer(void *, uint32_t) { decoderRendered++; return 0; }
void Check(int code, const char *message) { if (code) throw std::runtime_error(message); }
struct Frame { bool video; int width, height; int64_t timestampUs; std::vector<uint8_t> data; };
struct Track {
  int width = 4, height = 2, rotation = 90;
  int outputWidth = 4, outputHeight = 2;
  bool video = true, hdrVivid = true, ended = false, surfaceInputEnded = false, hasVideoAnchor = false;
  int64_t videoAnchorPts = 0, videoBucket = -1;
  std::deque<int64_t> surfaceTimes;
  void *codec = nullptr;
  std::unique_ptr<FileVideoSurface> surface;
  std::unique_ptr<Frame> pending;
  struct Buffer { uint32_t index; OH_AVBuffer *value; };
  std::deque<Buffer> outputs;
};
struct Harness {
  using Buffer = Track::Buffer;
  std::atomic<bool> stopping_{false};
  int64_t firstMediaUs_ = -1;
  int fps_ = 30, width = 0, height = 0;
  std::unique_ptr<Track> video_;
  bool timelineStarted_ = false;
  bool Pop(std::deque<Buffer> &queue, Buffer &buffer) {
    if (queue.empty()) return false;
    buffer = queue.front(); queue.pop_front(); return true;
  }
  void Release(Track &, int) { freed++; }
  std::unique_ptr<Frame> CopyFrame(Track &, OH_AVBuffer *, OH_AVCodecBufferAttr) {
    throw std::runtime_error("HDR pixels must not use the decoder byte-buffer path");
  }
  // FILE_VIDEO_COPY
  // FILE_VIDEO_CONFIGURE
  // FILE_VIDEO_DRAIN
};

void Output() { processor->callback->output(processor, 1, processor->context); }
void VerifyClean() {
  assert(images == 0 && processors == 0 && callbacks == 0 && windows == 0);
  assert(acquired == released && referenced == 0 && mapped == 0);
}

int main() {
  // Resolve dimensions before binding and request only the model-sized Surface, not the 4K original.
  {
    Harness source;
    source.video_ = std::make_unique<Track>();
    source.video_->width = 3840; source.video_->height = 2160;
    source.ConfigureVideoOutput(1280000, 24);
    assert(source.width == 828 && source.height == 1472 && source.fps_ == 24);
    assert(source.video_->width == 3840 && source.video_->height == 2160);
    FileVideoSurface scaled(source.video_->outputWidth, source.video_->outputHeight, source.stopping_);
    assert(requestedWidth == 1472 && requestedHeight == 828);
  }
  VerifyClean();

  // Native output filtering must not halve 30 fps when integer PTS alternates 33333/33334 us.
  for (int inputFps : {24, 30, 60, 120}) for (int targetFps : {24, 30}) {
    Harness source; source.fps_ = targetFps;
    Track video;
    int count = 0;
    for (int i = 0; i < inputFps; i++)
      if (source.ShouldOutputVideo(video, static_cast<int64_t>(i) * 1000000 / inputFps)) count++;
    assert(count == std::min(inputFps, targetFps));
    assert(!source.ShouldOutputVideo(video, -1));
  }

  for (int y = 0; y < 2; y++) for (int x = 0; x < 4; x++) pixels[y * 8 + x] = y * 4 + x;
  pixels[32] = 100; pixels[33] = 150; pixels[34] = 101; pixels[35] = 151;
  for (int cycle = 0; cycle < 8; cycle++) {
    Harness source;
    Track video;
    video.surface = std::make_unique<FileVideoSurface>(4, 2, source.stopping_);
    assert(video.surface->InputWindow()->color == OH_COLORSPACE_BT709_LIMIT);
    video.surface->Start();
    OH_AVBuffer frame{{12500, 0, 0}}, eos{{25000, 8, AVCODEC_BUFFER_FLAGS_EOS}};
    video.outputs.push_back({0, &frame}); video.outputs.push_back({1, &eos});
    const int previousFreed = freed, previousRendered = decoderRendered;
    source.Drain(video);
    assert(video.surfaceTimes.size() == 1 && !video.ended && !video.pending && decoderRendered == previousRendered + 1);
    assert(freed == previousFreed + 1 && video.surfaceInputEnded);
    source.Drain(video);
    assert(video.outputs.empty() && video.surfaceTimes.size() == 1 && !video.ended);
    Output(); source.Drain(video);
    assert(video.surfaceTimes.empty() && video.ended && video.pending);
    assert(video.pending->timestampUs == 12500 && video.pending->width == 2 && video.pending->height == 4);
    assert(video.pending->data == std::vector<uint8_t>({4,0,5,1,6,2,7,3,100,150,101,151}));
    source.Drain(video);
    assert(video.ended && video.outputs.empty() && video.pending);
    video.pending.reset(); source.Drain(video);
    assert(video.ended && freed == previousFreed + 1);
    video.surface.reset(); VerifyClean();
  }
  assert(starts == stops && starts == 8);

  // Keep GPU work bounded but allow its next frame to run while the previous one is mapped or paced.
  {
    Harness source; Track video;
    video.surface = std::make_unique<FileVideoSurface>(4, 2, source.stopping_);
    video.surface->Start();
    OH_AVBuffer first{{0, 0, 0}}, second{{33333, 0, 0}}, third{{66666, 0, 0}},
        eos{{100000, 0, AVCODEC_BUFFER_FLAGS_EOS}};
    video.outputs = {{0, &first}, {1, &second}, {2, &third}, {3, &eos}};
    const int previousRendered = decoderRendered;
    source.Drain(video);
    assert(video.surfaceTimes.size() == 2 && video.outputs.size() == 2 && !video.ended);
    assert(decoderRendered == previousRendered + 2);
    Output(); source.Drain(video);
    assert(video.pending->timestampUs == 0 && video.surfaceTimes.size() == 2 && video.outputs.size() == 1);
    assert(decoderRendered == previousRendered + 3);
    video.pending.reset(); Output(); source.Drain(video);
    assert(video.pending->timestampUs == 33333 && video.surfaceTimes.size() == 1 && video.surfaceInputEnded);
    assert(!video.ended);
    video.pending.reset(); Output(); source.Drain(video);
    assert(video.pending->timestampUs == 66666 && video.surfaceTimes.empty() && video.ended);
  }
  VerifyClean();

  // A pending Surface frame must be cancellable without rendering or consuming the next output.
  {
    Harness source; Track video;
    video.surface = std::make_unique<FileVideoSurface>(4, 2, source.stopping_);
    video.surface->Start(); video.surfaceTimes.push_back(0);
    source.stopping_ = true; source.Drain(video);
    assert(video.surfaceTimes.size() == 1 && !video.pending);
  }
  VerifyClean();

  // Cancelling an unsignalled fence returns ownership without mapping its unfinished pixels.
  {
    std::atomic<bool> stopping{false};
    FileVideoSurface surface(4, 2, stopping);
    surface.Start(); Output();
    int descriptors[2]; assert(pipe(descriptors) == 0);
    pendingFence = descriptors[0];
    std::thread cancel([&] { std::this_thread::sleep_for(std::chrono::milliseconds(20)); stopping = true; });
    const auto begin = std::chrono::steady_clock::now();
    const bool received = surface.Read([](const uint8_t *, int, const uint8_t *, int, int, int) { assert(false); });
    cancel.join(); close(descriptors[1]);
    assert(!received && std::chrono::steady_clock::now() - begin < std::chrono::seconds(1));
    assert(mapped == 0 && referenced == 0 && acquired == released);
  }
  VerifyClean();

  for (int stage = 1; stage <= 6; stage++) {
    std::atomic<bool> stopping{false};
    failStage = stage;
    pixelFormat = stage == 6 ? 99 : 24;
    bool failed = false;
    try {
      FileVideoSurface surface(4, 2, stopping);
      surface.Start(); Output();
      surface.Read([](const uint8_t *, int, const uint8_t *, int, int, int) {});
    } catch (const std::runtime_error &) { failed = true; }
    assert(failed); VerifyClean();
  }
  failStage = 0; pixelFormat = 24;
  {
    std::atomic<bool> stopping{false};
    FileVideoSurface surface(4, 2, stopping);
    surface.Start(); Output();
    bool failed = false;
    try {
      surface.Read([](const uint8_t *, int, const uint8_t *, int, int, int) { throw std::runtime_error("sink failed"); });
    } catch (const std::runtime_error &) { failed = true; }
    assert(failed && mapped == 0 && referenced == 0 && acquired == released);
    processor->callback->error(processor, 42, processor->context);
    failed = false;
    try { surface.CheckError(); }
    catch (const std::runtime_error &error) {
      failed = std::string(error.what()).find("42") != std::string::npos;
    }
    assert(failed);
  }
  VerifyClean();
}
