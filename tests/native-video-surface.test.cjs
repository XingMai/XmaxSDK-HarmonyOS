const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const source = fs.readFileSync(path.join(__dirname,
  '../xmax_sdk/src/main/cpp/native_video_file_decoder.cpp'), 'utf8');

function method(name) {
  const begin = source.search(new RegExp(`^  (?:void|bool) ${name}\\(`, 'm'));
  assert.notEqual(begin, -1, name);
  let end = source.indexOf('{', begin), depth = 1;
  while (depth && ++end < source.length) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
  }
  assert.equal(depth, 0);
  return source.slice(begin, end + 1);
}

test('Surface downscaling selects rotated sizes, falls back before start, and preserves NV12 frames', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'xmax-video-surface-'));
  try {
    const harness = path.join(directory, 'surface.cpp');
    const executable = path.join(directory, 'surface');
    fs.writeFileSync(harness, `
#include <algorithm>
#include <atomic>
#include <cassert>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <utility>
#include <vector>
#include <poll.h>
#include <unistd.h>
#define OH_LOG_Print(...) ((void)0)
int destroyed = 0;
void OH_VideoDecoder_Destroy(void*) { ++destroyed; }

class OutputSelection {
 public:
  int width_ = 3840, height_ = 2160, targetWidth_ = 1472, targetHeight_ = 832, rotation_ = 0;
  bool isHdrVivid_ = false, useSurfaceOutput_ = false;
  bool initializeSucceeds = true, surfaceDecoderSucceeds = true, bufferDecoderSucceeds = true;
  int initialized = 0, released = 0;
  std::vector<bool> attempts;
  void* decoder_ = nullptr;
  bool InitializeOutputSurface(std::string* error) {
    ++initialized;
    if (!initializeSucceeds) { *error = "surface unavailable"; ++released; }
    return initializeSucceeds;
  }
  void ReleaseOutputSurface() { ++released; }
  bool PrepareDecoder(const char*, std::string* error) {
    // Reconfiguration must create a new codec, never reuse the failed codec.
    assert(decoder_ == nullptr);
    decoder_ = this;
    attempts.push_back(useSurfaceOutput_);
    bool success = useSurfaceOutput_ ? surfaceDecoderSucceeds : bufferDecoderSucceeds;
    if (!success) *error = "codec unavailable";
    return success;
  }
${method('ShouldUseSurfaceOutput')}
${method('PrepareOutput')}
};

${source.slice(source.indexOf('void CopyOrRotateNv12('), source.indexOf('class NativeVideoFileDecoder'))}

struct OHNativeWindowBuffer {};
struct OH_NativeImage {};
struct OH_NativeBuffer {};
struct OH_NativeBuffer_Plane { uint32_t offset = 0; };
struct OH_NativeBuffer_Planes { uint32_t planeCount = 2; OH_NativeBuffer_Plane planes[2]; };
struct OH_NativeBuffer_Config { int32_t width, height, stride, format; };
constexpr int NATIVEBUFFER_PIXEL_FMT_YCBCR_420_SP = 24;
OH_NativeBuffer_Config bufferConfig;
std::vector<uint8_t> pixels;
OH_NativeBuffer nativeBuffer;
int unmaps = 0, releases = 0;
int OH_NativeBuffer_FromNativeWindowBuffer(OHNativeWindowBuffer*, OH_NativeBuffer** result) {
  *result = &nativeBuffer; return 0;
}
int OH_NativeBuffer_MapPlanes(OH_NativeBuffer*, void** data, OH_NativeBuffer_Planes* planes) {
  *data = pixels.data(); planes->planes[1].offset = bufferConfig.stride * bufferConfig.height; return 0;
}
void OH_NativeBuffer_GetConfig(OH_NativeBuffer*, OH_NativeBuffer_Config* config) { *config = bufferConfig; }
void OH_NativeBuffer_Unmap(OH_NativeBuffer*) { ++unmaps; }
void OH_NativeWindow_NativeObjectUnreference(OHNativeWindowBuffer*) {}
void OH_NativeImage_ReleaseNativeWindowBuffer(OH_NativeImage*, OHNativeWindowBuffer*, int) { ++releases; }
struct SurfaceBufferPacket { OHNativeWindowBuffer* windowBuffer; int fenceFd = -1; int64_t timestampUs = 1234; };
struct DecodedFramePacket {
  int32_t width, height, stride;
  int64_t timestampUs;
  std::vector<uint8_t> data;
};
class SurfaceReader {
 public:
  OH_NativeImage image;
  OH_NativeImage* surfaceOutputSurface_ = &image;
  std::mutex surfaceMutex_;
  std::atomic<bool> running_{true};
  int32_t targetWidth_ = 4, targetHeight_ = 2, rotation_ = 0;
  std::vector<uint8_t> surfaceSourceData_, surfaceScaledData_;
  DecodedFramePacket output;
  bool dispatched = false;
  std::string error;
  void ReportError(const std::string& reason) { error = reason; }
  void Dispatch(DecodedFramePacket* packet) {
    // CPU transformation and dispatch must not hold a Surface buffer hostage.
    assert(unmaps == 1 && releases == 1);
    output = std::move(*packet); delete packet; dispatched = true;
  }
${method('HandleSurfaceFrame')}
};

int main() {
  for (int rotation : {0, 90, 180, 270}) {
    OutputSelection selection;
    selection.rotation_ = rotation;
    if (rotation == 90 || rotation == 270) {
      std::swap(selection.targetWidth_, selection.targetHeight_);
    }
    assert(selection.ShouldUseSurfaceOutput());
    selection.width_ = 1472; selection.height_ = 832;
    assert(!selection.ShouldUseSurfaceOutput());
    selection.width_ = 640; selection.height_ = 480;
    assert(!selection.ShouldUseSurfaceOutput());
    selection.isHdrVivid_ = true;
    assert(selection.ShouldUseSurfaceOutput());
  }
  OutputSelection mixed;
  mixed.width_ = 3840; mixed.height_ = 720;
  assert(!mixed.ShouldUseSurfaceOutput()); // Do not upscale one axis in VPE.

  std::string error;
  OutputSelection success;
  assert(success.PrepareOutput("video/avc", &error));
  assert(success.attempts == std::vector<bool>{true} && destroyed == 0);
  OutputSelection noSurface;
  noSurface.initializeSucceeds = false;
  assert(noSurface.PrepareOutput("video/avc", &error) && error.empty());
  assert(noSurface.attempts == std::vector<bool>{false} && noSurface.released == 1);
  OutputSelection noSurfaceCodec;
  noSurfaceCodec.surfaceDecoderSucceeds = false;
  assert(noSurfaceCodec.PrepareOutput("video/avc", &error) && error.empty());
  assert((noSurfaceCodec.attempts == std::vector<bool>{true, false}));
  assert(destroyed == 1 && noSurfaceCodec.released == 1);
  OutputSelection noCodec;
  noCodec.surfaceDecoderSucceeds = noCodec.bufferDecoderSucceeds = false;
  assert(!noCodec.PrepareOutput("video/avc", &error) && !error.empty());
  OutputSelection hdrFailure;
  hdrFailure.isHdrVivid_ = true; hdrFailure.surfaceDecoderSucceeds = false;
  assert(!hdrFailure.PrepareOutput("video/hevc", &error));
  assert(hdrFailure.attempts == std::vector<bool>{true}); // Never bypass HDR tone mapping.
  OutputSelection small;
  small.width_ = 640; small.height_ = 480;
  assert(small.PrepareOutput("video/avc", &error));
  assert(small.initialized == 0 && small.attempts == std::vector<bool>{false});

  OHNativeWindowBuffer windowBuffer;
  const SurfaceBufferPacket packet{&windowBuffer};
  for (bool differentSize : {false, true}) {
    for (int rotation : {0, 90, 180, 270}) {
      bufferConfig = {8, 4, 12, NATIVEBUFFER_PIXEL_FMT_YCBCR_420_SP};
      pixels.resize(12 * 4 * 3 / 2);
      for (size_t i = 0; i < pixels.size(); ++i) pixels[i] = static_cast<uint8_t>(i);
      SurfaceReader reader;
      reader.rotation_ = rotation;
      reader.targetWidth_ = differentSize ? 4 : 8;
      reader.targetHeight_ = differentSize ? 2 : 4;
      if (rotation == 90 || rotation == 270) std::swap(reader.targetWidth_, reader.targetHeight_);
      std::vector<uint8_t> expected;
      ScaleAndRotateNv12(pixels.data(), 12, pixels.data() + 48, 12, 8, 4,
          rotation, reader.targetWidth_, reader.targetHeight_, &expected);
      unmaps = releases = 0;
      reader.HandleSurfaceFrame(packet);
      assert(reader.dispatched && reader.error.empty());
      assert(reader.output.data == expected && reader.output.timestampUs == 1234);
      assert(reader.output.width == reader.targetWidth_ && reader.output.height == reader.targetHeight_);
      // A correctly sized Surface must bypass the intermediate scale/copy buffer.
      if (!differentSize) assert(reader.surfaceScaledData_.empty());
      std::fill(pixels.begin(), pixels.end(), 255);
      assert(reader.output.data == expected); // Output owns its memory after buffer release.
    }
  }
  SurfaceReader invalid;
  bufferConfig.format = -1;
  unmaps = releases = 0;
  invalid.HandleSurfaceFrame(packet);
  assert(!invalid.dispatched && !invalid.error.empty() && unmaps == 1 && releases == 1);
}
`);
    const compile = spawnSync(process.env.CXX || 'clang++',
      ['-std=c++17', '-pthread', harness, '-o', executable], { encoding: 'utf8', timeout: 30000 });
    assert.equal(compile.status, 0, compile.error?.message || compile.stderr);
    const run = spawnSync(executable, [], { encoding: 'utf8', timeout: 10000 });
    assert.equal(run.status, 0, run.error?.message || run.stderr);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
