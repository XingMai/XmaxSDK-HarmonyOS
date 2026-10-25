#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace xlab {

/** An owned I420 frame or interleaved PCM16 packet from the SDK's unified callback. */
struct RecordingPacket {
  bool video = false;
  int64_t timestampUs = 0;
  int64_t arrivalUs = 0;
  int32_t width = 0;
  int32_t height = 0;
  int32_t rotation = 0;
  int32_t sampleRate = 0;
  int32_t channels = 0;
  std::vector<uint8_t> data;
};

/** Encodes tracks off the UI thread, then remuxes them with their original timestamp offset. */
class RealtimeRecorder {
public:
  RealtimeRecorder(std::string path, std::function<void(std::string)> failure);
  ~RealtimeRecorder();
  void Append(RecordingPacket packet);
  std::string Finish(bool cancel);

private:
  class State;
  std::unique_ptr<State> state_;
};

} // namespace xlab
