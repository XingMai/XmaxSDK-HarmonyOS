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
#include <atomic>
#include <cassert>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <memory>
#include <string>
#include <time.h>
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
  const char* backend() const { return "test"; }
  xmax::VideoFrameConversionTiming timing() const { return {}; }
};
class ReceiverHarness {
 public:
  ${definition(source, '  void ProcessMappedBuffer(')}
  void ReportError(const std::string&) { assert(false); }
  void Dispatch(FramePacket* packet) { retained.emplace_back(packet); }
  TestTransformer transformer_;
  std::atomic<int32_t> droppedFrameCount_{0}, skippedFrameCount_{0};
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
    assert(packet->processingMilliseconds + 0.000001 >=
           packet->allocationMilliseconds);
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
