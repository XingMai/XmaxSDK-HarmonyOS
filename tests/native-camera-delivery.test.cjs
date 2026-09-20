const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

function definition(source, marker) {
  const start = source.indexOf(marker);
  assert.notEqual(start, -1);
  let end = source.indexOf('{', start), depth = 1;
  while (depth && ++end < source.length) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
  }
  assert.equal(depth, 0);
  return source.slice(start, end + 1);
}

test('native direct delivery keeps retained output frames independent', () => {
  const cpp = path.resolve(__dirname, '../xmax_sdk/src/main/cpp');
  const source = fs.readFileSync(path.join(cpp, 'native_frame_receiver.cpp'), 'utf8');
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'xmax-camera-delivery-'));
  try {
    const harness = path.join(directory, 'delivery.cpp');
    const executable = path.join(directory, 'delivery');
    fs.writeFileSync(harness, `
#include <algorithm>
#include <cassert>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <memory>
#include <string>
#include <vector>
#include "video_frame_converter.h"
${definition(source, 'struct FramePacket {')};
${definition(source, 'struct OutputConfiguration {')};
struct Image_Size { uint32_t width; uint32_t height; };
struct TestTransformer {
  void TransformNv21ToNv12(const uint8_t* y, const uint8_t*, uint8_t* output,
                           const xmax::VideoFrameTransformConfiguration& c) {
    lastConfiguration = c;
    std::fill_n(output, c.targetWidth * c.targetHeight * 3 / 2, y[0]);
  }
  xmax::VideoFrameTransformConfiguration lastConfiguration{};
};
class ReceiverHarness {
 public:
  ${definition(source, '  void ProcessMappedBuffer(')}
  void ReportError(const std::string&) { assert(false); }
  void Dispatch(FramePacket* packet) { retained.emplace_back(packet); }
  TestTransformer transformer_;
  std::vector<std::unique_ptr<FramePacket>> retained;
};
int main() {
  ReceiverHarness receiver;
  OutputConfiguration config{6, 8, 90, 30, 30};
  const Image_Size size{8, 8};
  uint8_t source[96];
  // Retain every delivered packet, as if GC/RTC had not released any frame.
  for (int i = 0; i < 61; ++i) {
    config.rotation = (i % 4) * 90;
    std::fill_n(source, sizeof(source), i + 1);
    receiver.ProcessMappedBuffer(source, sizeof(source), size, 8, 1000 + i, config);
    const auto& packet = receiver.retained.back();
    assert(receiver.transformer_.lastConfiguration.rotation == config.rotation);
    assert(packet->width == 6);
    assert(packet->height == 8);
    assert(receiver.transformer_.lastConfiguration.targetWidth == packet->width);
    assert(receiver.transformer_.lastConfiguration.targetHeight == packet->height);
    assert(packet->dataLength == 72);
  }
  for (int i = 0; i < 61; ++i) {
    const auto& packet = receiver.retained[i];
    assert(std::all_of(packet->data.get(), packet->data.get() + packet->dataLength,
                       [i](uint8_t byte) { return byte == i + 1; }));
  }
}
`);
    const compile = spawnSync(process.env.CXX || 'clang++', [
      '-std=c++17', '-O2', '-pthread', '-fsanitize=address,undefined',
      '-I', cpp, harness, '-o', executable
    ], { encoding: 'utf8', timeout: 30000 });
    assert.equal(compile.status, 0, compile.error?.message || compile.stderr);
    const result = spawnSync(executable, [], { encoding: 'utf8', timeout: 30000 });
    assert.equal(result.status, 0, result.error?.message || result.stderr);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test('native camera read failure drops one frame without reporting a media error', () => {
  const cpp = path.resolve(__dirname, '../xmax_sdk/src/main/cpp');
  const source = fs.readFileSync(path.join(cpp, 'native_frame_receiver.cpp'), 'utf8');
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'xmax-camera-read-'));
  try {
    const harness = path.join(directory, 'read.cpp');
    const executable = path.join(directory, 'read');
    fs.writeFileSync(harness, `
#include <cassert>
#include <exception>
#include <mutex>
#include <string>
struct OutputConfiguration {};
struct OH_ImageNative {};
constexpr int IMAGE_SUCCESS = 0;
int readResult = 0;
bool hasImage = true;
int releases = 0;
OH_ImageNative frame;
int OH_ImageReceiverNative_ReadLatestImage(void*, OH_ImageNative** image) {
  *image = hasImage ? &frame : nullptr;
  return readResult;
}
int OH_ImageNative_Release(OH_ImageNative*) { ++releases; return IMAGE_SUCCESS; }
class ReceiverHarness {
 public:
  ${definition(source, '  void ProcessFrame() {')}
  bool ShouldProcessFrame(const OutputConfiguration&) { return true; }
  void ProcessImage(OH_ImageNative*, const OutputConfiguration&) { ++processed; }
  void ReportError(const std::string&) { ++errors; }
  std::mutex configurationMutex_;
  OutputConfiguration configuration_;
  void* receiver_ = nullptr;
  int processed = 0;
  int errors = 0;
};
int main() {
  ReceiverHarness receiver;
  readResult = 1;
  receiver.ProcessFrame();
  assert(receiver.processed == 0 && receiver.errors == 0 && releases == 0);
  readResult = IMAGE_SUCCESS;
  hasImage = false;
  receiver.ProcessFrame();
  assert(receiver.processed == 0 && receiver.errors == 0 && releases == 0);
  hasImage = true;
  receiver.ProcessFrame();
  assert(receiver.processed == 1 && receiver.errors == 0 && releases == 1);
}
`);
    const compile = spawnSync(process.env.CXX || 'clang++', [
      '-std=c++17', '-O2', '-pthread', '-fsanitize=address,undefined',
      harness, '-o', executable
    ], { encoding: 'utf8', timeout: 30000 });
    assert.equal(compile.status, 0, compile.error?.message || compile.stderr);
    const result = spawnSync(executable, [], { encoding: 'utf8', timeout: 30000 });
    assert.equal(result.status, 0, result.error?.message || result.stderr);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
