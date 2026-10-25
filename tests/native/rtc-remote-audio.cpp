#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_set>
#include <vector>

namespace bytertc {
enum class StreamIndex { kStreamIndexMain = 0, kStreamIndexScreen = 1 };
enum class AudioFrameType { kAudioFrameTypePCM16 = 0, kOther = 1 };
struct RemoteStreamKey { const char *room_id; const char *user_id; StreamIndex stream_index; };
struct IAudioFrame {
  int rate = 48000, channels = 2, format = 0;
  int64_t timestamp = 1000000;
  std::vector<uint8_t> bytes = std::vector<uint8_t>(1920, 27);
  int sampleRate() const { return rate; }
  int channel() const { return channels; }
  int dataSize() const { return static_cast<int>(bytes.size()); }
  int64_t timestampUs() const { return timestamp; }
  const uint8_t *data() const { return bytes.data(); }
  AudioFrameType frameType() const { return static_cast<AudioFrameType>(format); }
};
struct IAudioFrameObserver {
  virtual ~IAudioFrameObserver() = default;
  virtual void onRemoteUserAudioFrame(const RemoteStreamKey &, const IAudioFrame &) = 0;
  virtual void onRecordAudioFrameOriginal(const IAudioFrame &) = 0;
  virtual void onRecordAudioFrame(const IAudioFrame &) = 0;
  virtual void onPlaybackAudioFrame(const IAudioFrame &) = 0;
  virtual void onMixedAudioFrame(const IAudioFrame &) = 0;
  virtual void onCaptureMixedAudioFrame(const IAudioFrame &) = 0;
};
struct IRTCEngine {
  std::mutex mutex;
  IAudioFrameObserver *observer = nullptr;
  int registrations = 0, failure = 0;
  int registerAudioFrameObserver(IAudioFrameObserver *value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (value && failure) return failure;
    observer = value; registrations++; return 0;
  }
  void Send(const RemoteStreamKey &key, const IAudioFrame &frame) {
    std::lock_guard<std::mutex> lock(mutex);
    if (observer) observer->onRemoteUserAudioFrame(key, frame);
  }
};
}

using napi_env = void *;
using napi_value = int;
constexpr int napi_ok = 0, napi_queue_full = 1, napi_tsfn_nonblocking = 0, napi_tsfn_abort = 1;
constexpr size_t NAPI_AUTO_LENGTH = static_cast<size_t>(-1);
struct Value { int64_t number = 0; std::string text; std::vector<uint8_t> bytes; };
std::map<int, Value> values;
int valueId = 0, allocations = 0, liveFunctions = 0;
struct Function {
  std::mutex mutex;
  std::deque<void *> packets;
  void (*deliver)(napi_env, napi_value, void *, void *) = nullptr;
};
using napi_threadsafe_function = Function *;
Function *lastFunction = nullptr;
int napi_create_threadsafe_function(napi_env, napi_value, void *, napi_value, size_t, size_t,
    void *, void *, void *, decltype(Function::deliver) callback, Function **result) {
  *result = lastFunction = new Function; (*result)->deliver = callback; liveFunctions++; return napi_ok;
}
int napi_call_threadsafe_function(Function *function, void *packet, int) {
  std::lock_guard<std::mutex> lock(function->mutex);
  if (function->packets.size() == 128) return napi_queue_full;
  function->packets.push_back(packet); return napi_ok;
}
void napi_create_double(napi_env, double number, napi_value *result) {
  *result = ++valueId; values[*result].number = static_cast<int64_t>(number);
}
void napi_create_string_utf8(napi_env, const char *text, size_t size, napi_value *result) {
  *result = ++valueId; values[*result].text.assign(text, size == NAPI_AUTO_LENGTH ? std::strlen(text) : size);
}
int napi_create_arraybuffer(napi_env, size_t size, void **storage, napi_value *result) {
  *result = ++valueId; values[*result].bytes.resize(size); *storage = values[*result].bytes.data();
  allocations++; return napi_ok;
}
void napi_get_boolean(napi_env, bool value, napi_value *result) { napi_create_double(nullptr, value, result); }
void napi_get_undefined(napi_env, napi_value *result) { *result = 0; }
struct Delivered { std::string room, user; int stream, rate, channels; int64_t timestamp; bool lost;
  std::vector<uint8_t> bytes; };
std::vector<Delivered> delivered;
void napi_call_function(napi_env, napi_value, napi_value, size_t count, const napi_value *args, napi_value *) {
  assert(count == 8);
  delivered.push_back({values[args[0]].text, values[args[1]].text, static_cast<int>(values[args[2]].number),
      static_cast<int>(values[args[4]].number), static_cast<int>(values[args[5]].number), values[args[6]].number,
      values[args[7]].number != 0, values[args[3]].bytes});
}
void Flush(Function *function, bool environmentAlive = true) {
  while (true) {
    void *packet;
    {
      std::lock_guard<std::mutex> lock(function->mutex);
      if (function->packets.empty()) break;
      packet = function->packets.front(); function->packets.pop_front();
    }
    function->deliver(environmentAlive ? reinterpret_cast<void *>(1) : nullptr, 1, nullptr, packet);
  }
}
void napi_release_threadsafe_function(Function *function, int) {
  Flush(function, false); delete function; liveFunctions--;
}

// NATIVE_REMOTE_AUDIO

int main() {
  const bytertc::RemoteStreamKey key{"room", "bot", bytertc::StreamIndex::kStreamIndexMain};
  bytertc::IAudioFrame frame;
  {
    bytertc::IRTCEngine engine;
    RemoteAudioObserver observer(reinterpret_cast<void *>(1), 1);
    observer.Attach(&engine);
    engine.Send(key, frame); assert(lastFunction->packets.empty());
    observer.SetEnabled(true);
    engine.Send(key, frame);
    std::fill(frame.bytes.begin(), frame.bytes.end(), 0);
    Flush(lastFunction);
    assert(delivered.size() == 1 && delivered[0].timestamp == 1000000);
    assert(delivered[0].room == "room" && delivered[0].user == "bot" && delivered[0].stream == 0);
    assert(delivered[0].rate == 48000 && delivered[0].channels == 2 && delivered[0].bytes.size() == 1920);
    assert(std::all_of(delivered[0].bytes.begin(), delivered[0].bytes.end(), [](uint8_t x) { return x == 27; }));

    engine.Send(key, frame);
    const int before = allocations;
    observer.SetEnabled(false); observer.SetEnabled(true);
    Flush(lastFunction); assert(allocations == before && delivered.size() == 1);
    engine.Send({"room", "screen", bytertc::StreamIndex::kStreamIndexScreen}, frame);
    assert(lastFunction->packets.empty());

    frame.format = 1; engine.Send(key, frame); frame.format = 0;
    engine.Send(key, frame); Flush(lastFunction);
    assert(delivered.back().lost);

    for (int i = 0; i < 129; i++) engine.Send(key, frame);
    assert(lastFunction->packets.size() == 128);
    Flush(lastFunction); engine.Send(key, frame); Flush(lastFunction);
    assert(delivered.back().lost);

    frame.rate = 192000; frame.bytes.assign(768000, 42);
    for (int i = 0; i < 6; i++) engine.Send(key, frame);
    assert(lastFunction->packets.size() == 5);
    Flush(lastFunction); engine.Send(key, frame); Flush(lastFunction);
    assert(delivered.back().lost && delivered.back().bytes.size() == 768000);

    // Callback and stop synchronization must not retain the engine's borrowed frame or block on ArkTS.
    frame.rate = 48000; frame.bytes.resize(1920);
    std::thread producer([&] { for (int i = 0; i < 1000; i++) engine.Send(key, frame); });
    for (int i = 0; i < 100; i++) { observer.SetEnabled(false); observer.SetEnabled(true); }
    producer.join();
    assert(observer.Close() == 0 && engine.observer == nullptr);
    const size_t count = delivered.size(); Flush(lastFunction); assert(delivered.size() == count);
    assert(observer.Close() == 0 && engine.registrations == 2);
  }
  assert(liveFunctions == 0);
  {
    // Engine-registration failure and environment teardown release all queued native data.
    bytertc::IRTCEngine engine; engine.failure = -1;
    RemoteAudioObserver observer(reinterpret_cast<void *>(1), 1);
    bool failed = false;
    try { observer.Attach(&engine); } catch (const std::runtime_error &) { failed = true; }
    assert(failed && !engine.observer);
  }
  assert(liveFunctions == 0);
  {
    bytertc::IRTCEngine engine;
    RemoteAudioObserver observer(reinterpret_cast<void *>(1), 1);
    observer.Attach(&engine); observer.SetEnabled(true); engine.Send(key, frame);
    const int before = allocations;
    Flush(lastFunction, false); assert(allocations == before);
  }
  assert(liveFunctions == 0);
}
