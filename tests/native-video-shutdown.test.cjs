const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

// Execute the decoder's actual worker methods with native threads. Only the
// platform frame processing and the condition variable's scheduling are stubbed.
function workerMethod(source, name) {
  const declaration = source.search(new RegExp(`^  (?:static )?(?:void|bool) ${name}\\(`, 'm'));
  assert.notEqual(declaration, -1, `Missing decoder method: ${name}`);
  const begin = source.lastIndexOf('\n', declaration) + 1;
  let end = source.indexOf('{', begin), depth = 1;
  while (depth && ++end < source.length) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
  }
  assert.equal(depth, 0);
  return source.slice(begin, end + 1);
}

test('HDR shutdown completes when stop races with the worker entering its empty-queue wait', () => {
  const source = fs.readFileSync(path.join(__dirname,
    '../xmax_sdk/src/main/cpp/native_video_file_decoder.cpp'), 'utf8');
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'xmax-native-shutdown-'));
  try {
    const harness = path.join(directory, 'shutdown.cpp');
    const executable = path.join(directory, 'shutdown');
    fs.writeFileSync(harness, `
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <cstdint>
#include <future>
#include <iostream>
#include <mutex>
#include <thread>
using namespace std::chrono_literals;

class ScheduledCondition {
 public:
  std::condition_variable condition;
  std::promise<void> predicateChecked;
  std::promise<void> resumeWait;
  std::promise<void> stopNotified;
  bool firstWait = true;

  template <class Predicate>
  void wait(std::unique_lock<std::mutex>& lock, Predicate predicate) {
    while (!predicate()) {
      if (firstWait) {
        firstWait = false;
        predicateChecked.set_value();
        // Hold the queue lock after checking the predicate but before waiting.
        // A correct stop must acquire this same lock before changing the state.
        resumeWait.get_future().wait();
      }
      condition.wait(lock);
    }
  }

  void notify_all() {
    condition.notify_all();
    stopNotified.set_value();
  }
};

struct HdrSurfaceBufferPacket {};
constexpr int VIDEO_PROCESSING_SUCCESS = 0;
int OH_VideoProcessing_RenderOutputBuffer(void*, uint32_t) { return 0; }
class DecoderWorker {
 public:
  std::mutex hdrSurfaceMutex_;
  std::mutex hdrSurfaceQueueMutex_;
  ScheduledCondition hdrSurfaceCondition_;
  std::atomic<bool> hdrSurfaceWorkerRunning_{true};
  std::deque<uint32_t> hdrPendingOutputBuffers_;
  void* hdrVideoProcessor_ = nullptr;
  void ReportError(const char*) {}
  std::thread hdrSurfaceWorker_;
  bool AcquireHdrSurfaceFrame(HdrSurfaceBufferPacket&) { return false; }
  void ReleaseHdrSurfaceBufferLocked(const HdrSurfaceBufferPacket&) {}
  void HandleHdrSurfaceFrame(const HdrSurfaceBufferPacket&) {}
  void CompleteHdrSurfaceFrame() {}
${workerMethod(source, 'StopHdrSurfaceWorker')}
${workerMethod(source, 'HdrSurfaceWorkerLoop')}
};

int main() {
  DecoderWorker decoder;
  auto& condition = decoder.hdrSurfaceCondition_;
  decoder.hdrSurfaceWorker_ = std::thread([&] { decoder.HdrSurfaceWorkerLoop(); });
  condition.predicateChecked.get_future().wait();
  auto stopping = std::async(std::launch::async, [&] { decoder.StopHdrSurfaceWorker(); });
  // The broken implementation can notify now; the fixed one waits for the lock.
  condition.stopNotified.get_future().wait_for(200ms);
  condition.resumeWait.set_value();
  const bool completed = stopping.wait_for(1s) == std::future_status::ready;
  if (!completed) {
    // Rescue the deliberately stalled worker so a regression fails cleanly.
    condition.condition.notify_all();
  }
  stopping.get();
  if (!completed) {
    std::cerr << "HDR worker lost the stop notification; decoder release never completed\\n";
    return 1;
  }
  return 0;
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

test('HDR output rendering and buffer recycling stay on the same worker during frame bursts', () => {
  const source = fs.readFileSync(path.join(__dirname,
    '../xmax_sdk/src/main/cpp/native_video_file_decoder.cpp'), 'utf8');
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'xmax-hdr-callback-'));
  try {
    const harness = path.join(directory, 'callback.cpp');
    const executable = path.join(directory, 'callback');
    fs.writeFileSync(harness, `
#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <thread>
#include <unistd.h>
using namespace std::chrono_literals;

struct OHNativeWindowBuffer { int references = 0; };
struct OH_NativeImage {};
struct HdrSurfaceBufferPacket {
  OHNativeWindowBuffer* windowBuffer = nullptr;
  int fenceFd = -1;
  int64_t timestampUs = 0;
};
thread_local bool insideProducer = false;
std::mutex producerMutex;
std::mutex buffersMutex;
std::deque<OHNativeWindowBuffer*> buffers;
std::array<OHNativeWindowBuffer, 8> burst;
std::thread::id renderThread;
std::atomic<int> renderCalls{0};
constexpr int VIDEO_PROCESSING_SUCCESS = 0;
int OH_VideoProcessing_RenderOutputBuffer(void*, uint32_t index) {
  std::lock_guard<std::mutex> producerLock(producerMutex);
  std::lock_guard<std::mutex> imageLock(buffersMutex);
  renderThread = std::this_thread::get_id();
  buffers.push_back(&burst.at(index));
  ++renderCalls;
  return VIDEO_PROCESSING_SUCCESS;
}
std::atomic<int> callbackOperations{0}, acquired{0}, released{0};

int OH_NativeImage_AcquireNativeWindowBuffer(OH_NativeImage*, OHNativeWindowBuffer** buffer, int* fence) {
  if (insideProducer || std::this_thread::get_id() != renderThread) ++callbackOperations;
  std::lock_guard<std::mutex> lock(buffersMutex);
  if (buffers.empty()) return -1;
  *buffer = buffers.front();
  buffers.pop_front();
  *fence = -1;
  ++acquired;
  return 0;
}
int OH_NativeWindow_NativeObjectReference(OHNativeWindowBuffer* buffer) {
  ++buffer->references;
  return 0;
}
void OH_NativeWindow_NativeObjectUnreference(OHNativeWindowBuffer* buffer) {
  --buffer->references;
}
int OH_NativeImage_ReleaseNativeWindowBuffer(OH_NativeImage*, OHNativeWindowBuffer*, int) {
  if (insideProducer || std::this_thread::get_id() != renderThread) {
    // The actual VPE deadlocks trying to re-lock producerMutex here. Record the
    // violation without hanging the test process so the regression is readable.
    ++callbackOperations;
  } else {
    std::lock_guard<std::mutex> lock(producerMutex);
  }
  ++released;
  return 0;
}

class DecoderWorker {
 public:
  OH_NativeImage surface;
  OH_NativeImage* hdrOutputSurface_ = &surface;
  std::mutex hdrSurfaceMutex_, hdrSurfaceQueueMutex_, hdrTimestampMutex_;
  std::condition_variable hdrSurfaceCondition_;
  std::atomic<bool> hdrSurfaceWorkerRunning_{true};
  std::deque<uint32_t> hdrPendingOutputBuffers_;
  void* hdrVideoProcessor_ = nullptr;
  size_t hdrSurfaceFramesInFlight_ = 0;
  std::deque<int64_t> pendingHdrTimestamps_;
  std::thread hdrSurfaceWorker_;
  std::mutex completionMutex;
  std::condition_variable completionCondition;
  int completed = 0, rendered = 0;
  void ReportError(const char* error) { throw std::runtime_error(error); }
  void HandleHdrSurfaceFrame(const HdrSurfaceBufferPacket& packet) {
    ++rendered;
    std::lock_guard<std::mutex> lock(hdrSurfaceMutex_);
    ReleaseHdrSurfaceBufferLocked(packet);
  }
  void CompleteHdrSurfaceFrame() {
    --hdrSurfaceFramesInFlight_;
    {
      std::lock_guard<std::mutex> lock(completionMutex);
      ++completed;
    }
    completionCondition.notify_all();
  }
${workerMethod(source, 'StopHdrSurfaceWorker')}
${workerMethod(source, 'EnqueueHdrSurfaceFrame')}
${workerMethod(source, 'AcquireHdrSurfaceFrame')}
${workerMethod(source, 'ReleaseHdrSurfaceBufferLocked')}
${workerMethod(source, 'HdrSurfaceWorkerLoop')}
};

int main() {
  DecoderWorker decoder;
  // Hold the worker until the producer has filled the queue, reproducing the
  // first-frame burst seen on the device without relying on thread timing.
  {
    std::lock_guard<std::mutex> lock(producerMutex);
    insideProducer = true;
    for (uint32_t index = 0; index < burst.size(); ++index) {
      decoder.pendingHdrTimestamps_.push_back(1000);
      decoder.EnqueueHdrSurfaceFrame(index);
    }
    insideProducer = false;
  }
  decoder.hdrSurfaceWorker_ = std::thread([&] { decoder.HdrSurfaceWorkerLoop(); });
  bool completed;
  {
    std::unique_lock<std::mutex> lock(decoder.completionMutex);
    completed = decoder.completionCondition.wait_for(lock, 1s, [&] { return decoder.completed == 8; });
  }
  decoder.StopHdrSurfaceWorker();
  if (callbackOperations != 0) {
    std::cerr << "Surface buffer operations re-entered VPE from its producer callback\\n";
    return 1;
  }
  if (!completed || renderCalls != 8 || acquired != 8 || released != 8 || decoder.rendered != 1 ||
      decoder.hdrSurfaceFramesInFlight_ != 0 || !decoder.pendingHdrTimestamps_.empty()) {
    std::cerr << "Worker did not drain the burst and render the latest frame\\n";
    return 1;
  }
  for (auto& buffer : burst) {
    if (buffer.references != 0) return 1;
  }
  // Late notifications must not schedule work after the worker has stopped.
  decoder.EnqueueHdrSurfaceFrame(0);
  if (!decoder.hdrPendingOutputBuffers_.empty()) return 1;
  // Stop leaves queued output indices owned by VPE; do not render them while
  // its resources are being torn down, and never acquire a new Surface buffer.
  DecoderWorker cancelled;
  cancelled.EnqueueHdrSurfaceFrame(0);
  cancelled.StopHdrSurfaceWorker();
  cancelled.hdrSurfaceWorker_ = std::thread([&] { cancelled.HdrSurfaceWorkerLoop(); });
  cancelled.StopHdrSurfaceWorker();
  return cancelled.hdrPendingOutputBuffers_.empty() && renderCalls == 8 && acquired == 8 ? 0 : 1;
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
