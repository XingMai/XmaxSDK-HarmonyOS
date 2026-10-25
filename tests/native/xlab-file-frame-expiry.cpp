#include <algorithm>
#include <atomic>
#include <cassert>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

/** A deterministic monotonic clock shared by native dispatch and simulated ArkTS delivery. */
struct Clock {
  using duration = std::chrono::microseconds;
  using time_point = std::chrono::time_point<Clock, duration>;
  inline static int64_t nowUs = 0;
  static time_point now() { return time_point(duration(nowUs)); }
};

// FILE_FRAME_AND_EXPIRY

constexpr int napi_ok = 0, napi_tsfn_blocking = 0;
using napi_env = int;
using napi_value = int;
std::vector<std::unique_ptr<Frame>> queued;
std::vector<uint8_t> arrayBuffer;
int callbacks = 0, allocations = 0;
int64_t callbackTimestamp = -1;
std::string callbackError;

int napi_call_threadsafe_function(int, Frame *frame, int) { queued.emplace_back(frame); return napi_ok; }
void napi_create_object(napi_env, napi_value *result) { *result = 1; }
void napi_create_string_utf8(napi_env, const char *text, size_t length, napi_value *result) {
  callbackError.assign(text, length); *result = 1;
}
void napi_get_boolean(napi_env, bool, napi_value *result) { *result = 1; }
int napi_create_arraybuffer(napi_env, size_t size, void **storage, napi_value *result) {
  allocations++; arrayBuffer.resize(size); *storage = arrayBuffer.data(); *result = 1; return napi_ok;
}
void napi_get_undefined(napi_env, napi_value *result) { *result = 0; }
void napi_call_function(napi_env, napi_value, napi_value, int, const napi_value *, napi_value *result) {
  callbacks++; *result = 0;
}
napi_value Number(napi_env, double value) { return static_cast<int>(value); }
void Set(napi_env, napi_value, const char *key, napi_value value) {
  if (std::string(key) == "timestampUs") callbackTimestamp = value;
}

// FILE_DELIVER_CALLBACK

struct Waiter {
  int64_t oversleepUs = 0;
  template<class Lock, class Predicate>
  void wait_until(Lock &, Clock::time_point due, Predicate predicate) {
    if (!predicate()) Clock::nowUs = std::max(Clock::nowUs, due.time_since_epoch().count()) + oversleepUs;
  }
};
struct Harness {
  struct Track { bool ended = true; std::unique_ptr<Frame> pending; };
  std::unique_ptr<Track> video_ = std::make_unique<Track>(), audio_;
  std::atomic<bool> stopping_{false};
  std::mutex mutex_;
  Waiter changed_;
  std::string error_;
  int fps_ = 30, callback_ = 1;
  int64_t anchorUs_ = 1000000, firstMediaUs_ = 0, lastOutputUs_ = -1;
  bool timelineStarted_ = false;

  void Pending(bool video, int64_t pts) {
    auto frame = std::make_unique<Frame>();
    frame->video = video; frame->timestampUs = pts; frame->data.assign(16, 42);
    if (video) video_->pending = std::move(frame);
    else {
      if (!audio_) audio_ = std::make_unique<Track>();
      audio_->pending = std::move(frame);
    }
  }
  // FILE_DELIVER_NEXT
};

void Reset() {
  queued.clear(); arrayBuffer.clear(); callbacks = allocations = 0;
  callbackTimestamp = -1; callbackError.clear(); Clock::nowUs = 1000000;
}

int main() {
  // Strictly greater than one video frame / 100 ms is stale; equality remains accepted.
  for (bool video : {false, true}) for (int fps : {24, 30, 60}) {
    for (bool expired : {false, true}) {
      Reset(); Harness source; source.fps_ = fps;
      const int64_t allowance = video ? 1000000 / fps : 100000;
      Clock::nowUs = source.anchorUs_ + allowance + (expired ? 1 : 0);
      source.Pending(video, 0); source.DeliverNext();
      assert(queued.size() == (expired ? 0 : 1));
      assert(source.anchorUs_ == 1000000 && source.firstMediaUs_ == 0 && source.timelineStarted_);
      assert(!source.video_->pending && (!source.audio_ || !source.audio_->pending));
      if (expired) assert(source.lastOutputUs_ == -1);
      else {
        assert(queued.front()->timestampUs == 1000000);
        assert(queued.front()->expiresUs == 1000000 + allowance);
      }
    }
  }

  // A slow worker skips stale video and catches up without moving the shared audio/video origin.
  Reset(); Harness source;
  Clock::nowUs = 1100000;
  for (int64_t pts : {0, 33333, 66666}) {
    source.Pending(true, pts); source.DeliverNext(); assert(queued.empty());
  }
  source.Pending(false, 25000); source.DeliverNext();
  assert(queued.size() == 1 && queued[0]->timestampUs == 1025000);
  source.Pending(true, 100000); source.DeliverNext();
  assert(queued.size() == 2 && queued[1]->timestampUs == 1100000);
  assert(source.firstMediaUs_ == 0 && source.anchorUs_ == 1000000);

  // A wakeup delayed beyond the allowance must not publish a burst of expired samples.
  for (bool video : {false, true}) {
    Reset(); Harness delayed;
    delayed.changed_.oversleepUs = (video ? 1000000 / delayed.fps_ : 100000) + 1;
    delayed.Pending(video, 50000); delayed.DeliverNext();
    assert(queued.empty() && delayed.lastOutputUs_ == -1);
  }

  // Main-thread congestion must drop a queued stale frame before ArrayBuffer allocation or Sink invocation.
  for (bool video : {false, true}) for (bool expired : {false, true}) {
    Reset(); Harness congested;
    congested.Pending(video, 0); congested.DeliverNext(); assert(queued.size() == 1);
    Clock::nowUs = queued[0]->expiresUs + (expired ? 1 : 0);
    Deliver(1, 1, nullptr, queued[0].release()); queued.clear();
    assert(callbacks == (expired ? 0 : 1) && allocations == (expired ? 0 : 1));
    if (!expired) assert(callbackTimestamp == 1000000 && arrayBuffer == std::vector<uint8_t>(16, 42));
  }

  // Cancellation and codec failure preserve their previous behavior; error notifications never expire.
  Reset(); Harness cancelled; cancelled.Pending(true, 50000); cancelled.stopping_ = true;
  cancelled.DeliverNext(); assert(queued.empty());
  Reset(); Harness failed; failed.Pending(true, 50000); failed.error_ = "codec failed";
  bool threw = false;
  try { failed.DeliverNext(); } catch (const std::runtime_error &error) { threw = std::string(error.what()) == "codec failed"; }
  assert(threw && queued.empty());
  auto error = std::make_unique<Frame>(); error->error = "decoder failed";
  Clock::nowUs = 9999999999;
  Deliver(1, 1, nullptr, error.release());
  assert(callbacks == 1 && callbackError == "decoder failed" && allocations == 0);

  // A new playback cycle can start after an expired tail; no expiry state leaks into it.
  Reset(); Harness previous; previous.Pending(true, 0); Clock::nowUs += 200000;
  previous.DeliverNext(); assert(queued.empty() && !previous.video_->pending);
  Harness next; next.anchorUs_ = Clock::nowUs;
  next.Pending(true, 0); next.DeliverNext();
  assert(queued.size() == 1 && queued[0]->timestampUs == 1200000);
}
