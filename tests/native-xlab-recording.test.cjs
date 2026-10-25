const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const directory = path.resolve(__dirname, '../examples/XLab/entry/src/main/cpp');

test('recorder PCM packing and padded NV12 conversion execute the production native methods', () => {
  const source = fs.readFileSync(path.join(directory, 'realtime_recorder.cpp'), 'utf8');
  const methods = source.slice(source.indexOf('  void Enqueue('), source.indexOf('  /** Creates container metadata'));
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'xlab-recorder-packing-'));
  try {
    const harness = path.join(temporary, 'packing.cpp'), executable = path.join(temporary, 'packing');
    fs.writeFileSync(harness, `
#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstring>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>
#include "${path.join(directory, 'realtime_recorder.h')}"
using xlab::RecordingPacket;
constexpr int AV_ERR_OK = 0, AVCODEC_BUFFER_FLAGS_EOS = 1;
struct OH_AVCodecBufferAttr { int64_t pts = 0; int32_t size = 0, offset = 0; uint32_t flags = 0; };
struct OH_AVBuffer { std::vector<uint8_t> bytes; OH_AVCodecBufferAttr attr; };
struct EncodedInput { std::vector<uint8_t> bytes; OH_AVCodecBufferAttr attr; };
struct OH_AVCodec { std::vector<OH_AVBuffer> buffers; std::vector<EncodedInput> submitted; };
struct OH_AVFormat {};
void OH_AVFormat_Destroy(OH_AVFormat *value) { delete value; }
using Format = std::unique_ptr<OH_AVFormat, decltype(&OH_AVFormat_Destroy)>;
const char *OH_MD_KEY_VIDEO_STRIDE = "stride", *OH_MD_KEY_VIDEO_SLICE_HEIGHT = "slice";
OH_AVFormat *OH_VideoEncoder_GetInputDescription(OH_AVCodec *) { return new OH_AVFormat; }
bool OH_AVFormat_GetIntValue(OH_AVFormat *, const char *, int *) { return false; }
int32_t OH_AVBuffer_GetCapacity(OH_AVBuffer *buffer) { return static_cast<int32_t>(buffer->bytes.size()); }
uint8_t *OH_AVBuffer_GetAddr(OH_AVBuffer *buffer) { return buffer->bytes.data(); }
int OH_AVBuffer_SetBufferAttr(OH_AVBuffer *buffer, OH_AVCodecBufferAttr *attr) { buffer->attr = *attr; return 0; }
int OH_AudioCodec_PushInputBuffer(OH_AVCodec *codec, uint32_t index) {
  auto &buffer = codec->buffers[index];
  codec->submitted.push_back({std::vector<uint8_t>(buffer.bytes.begin(), buffer.bytes.begin() + buffer.attr.size), buffer.attr});
  return 0;
}
int OH_VideoEncoder_PushInputBuffer(OH_AVCodec *codec, uint32_t index) { return OH_AudioCodec_PushInputBuffer(codec, index); }
void Check(int value, const char *reason) { if (value) throw std::runtime_error(reason); }
struct Harness {
  struct Buffer { uint32_t index; OH_AVBuffer *value; };
  struct Track {
    bool video = false, inputEnded = false;
    OH_AVCodec *codec = nullptr;
    int width = 0, height = 0, rotation = 0, sampleRate = 48000, channels = 1, stride = 0, sliceHeight = 0;
    int64_t originUs = 1000000, arrivalUs = 0, lastQueuedUs = -1, lastQueuedEndUs = -1, endUs = 0;
    size_t pendingBytes = 0, packetOffset = 0;
    std::deque<RecordingPacket> pending;
    std::deque<Buffer> inputs;
  } video_, audio_;
  std::mutex mutex_;
  size_t retainedBytes_ = 0, retainedPackets_ = 0;
  bool Pop(std::deque<Buffer> &queue, Buffer &buffer) { if (queue.empty()) return false; buffer = queue.front(); queue.pop_front(); return true; }
  void Prepare(Track &, const RecordingPacket &) { throw std::runtime_error("unconfigured fixture"); }
  void Accept(RecordingPacket packet) { retainedBytes_ += packet.data.size(); retainedPackets_++; Enqueue(std::move(packet)); }
  ${methods}
};

RecordingPacket Audio(int64_t timestamp, int samples, int channels, uint8_t value, int rate = 48000) {
  RecordingPacket packet; packet.timestampUs = timestamp; packet.channels = channels; packet.sampleRate = rate;
  packet.data.assign(samples * channels * 2, value); return packet;
}
void Inputs(Harness::Track &track, OH_AVCodec &codec, int capacity) {
  codec.buffers.resize(8); track.codec = &codec;
  for (uint32_t i = 0; i < codec.buffers.size(); i++) { codec.buffers[i].bytes.resize(capacity); track.inputs.push_back({i, &codec.buffers[i]}); }
}
int main() {
  {
    Harness h; OH_AVCodec codec; Inputs(h.audio_, codec, 4096);
    h.Accept(Audio(1000000, 480, 1, 1)); h.Accept(Audio(1010000, 480, 1, 2)); h.Accept(Audio(1020000, 480, 1, 3));
    h.Feed(h.audio_, false); assert(codec.submitted.size() == 1);
    auto &first = codec.submitted[0]; assert(first.bytes.size() == 2048 && first.attr.pts == 0);
    assert(std::all_of(first.bytes.begin(), first.bytes.begin() + 960, [](uint8_t x) { return x == 1; }));
    assert(std::all_of(first.bytes.begin() + 960, first.bytes.begin() + 1920, [](uint8_t x) { return x == 2; }));
    assert(std::all_of(first.bytes.begin() + 1920, first.bytes.end(), [](uint8_t x) { return x == 3; }));
    h.Feed(h.audio_, true); assert(codec.submitted.size() == 3);
    auto &last = codec.submitted[1]; assert(last.bytes.size() == 2048 && std::abs(last.attr.pts - 21333) <= 1);
    assert(std::all_of(last.bytes.begin(), last.bytes.begin() + 832, [](uint8_t x) { return x == 3; }));
    assert(std::all_of(last.bytes.begin() + 832, last.bytes.end(), [](uint8_t x) { return x == 0; }));
    assert(codec.submitted[2].attr.flags == AVCODEC_BUFFER_FLAGS_EOS && codec.submitted[2].bytes.empty());
    assert(h.retainedBytes_ == 0 && h.retainedPackets_ == 0);
  }
  {
    Harness h; OH_AVCodec codec; h.audio_.channels = 2; h.audio_.sampleRate = 44100; Inputs(h.audio_, codec, 4096);
    for (int i = 0; i < 3; i++) h.Accept(Audio(1000000 + std::llround(i * 1024.0 * 1000000 / 44100), 1024, 2, i, 44100));
    h.Feed(h.audio_, true); assert(codec.submitted.size() == 4);
    for (int i = 0; i < 3; i++) {
      assert(codec.submitted[i].bytes.size() == 4096);
      assert(codec.submitted[i].attr.pts == std::llround(i * 1024.0 * 1000000 / 44100));
    }
  }
  {
    Harness h; OH_AVCodec codec; Inputs(h.audio_, codec, 2048);
    h.Accept(Audio(1000000, 480, 1, 1));
    bool failed = false; try { h.Accept(Audio(1020000, 480, 1, 1)); } catch (const std::runtime_error &) { failed = true; }
    assert(failed);
  }
  {
    Harness h; OH_AVCodec codec; Inputs(h.audio_, codec, 2048);
    RecordingPacket packet; packet.video = true; packet.timestampUs = 900000000; packet.arrivalUs = 10000;
    bool failed = false;
    try { h.Enqueue(packet); } catch (const std::runtime_error &error) {
      failed = std::string(error.what()).find("clocks do not match") != std::string::npos;
    }
    assert(failed);
  }
  {
    Harness h; OH_AVCodec codec; auto &track = h.video_;
    track.video = true; track.width = 2; track.height = 2; track.stride = 4; track.sliceHeight = 4;
    track.sampleRate = 0; track.channels = 0; Inputs(track, codec, 24);
    RecordingPacket packet; packet.video = true; packet.timestampUs = 1000000; packet.width = 2; packet.height = 2;
    packet.data = {16, 17, 18, 19, 100, 200}; h.Accept(packet); h.Feed(track, true);
    const auto &bytes = codec.submitted[0].bytes; assert(bytes.size() == 24);
    assert(bytes[0] == 16 && bytes[1] == 17 && bytes[4] == 18 && bytes[5] == 19);
    assert(bytes[2] == 16 && bytes[8] == 16 && bytes[16] == 100 && bytes[17] == 200 && bytes[18] == 128);
    assert(codec.submitted[1].attr.flags == AVCODEC_BUFFER_FLAGS_EOS);
    assert(h.retainedBytes_ == 0 && h.retainedPackets_ == 0);
  }
}
`);
    const compiled = spawnSync(process.env.CXX || 'clang++', ['-std=c++17', '-pthread',
      '-fsanitize=address,undefined', harness, '-o', executable], { encoding: 'utf8', timeout: 30000 });
    assert.equal(compiled.status, 0, compiled.stderr);
    const run = spawnSync(executable, [], { encoding: 'utf8', timeout: 10000 });
    assert.equal(run.status, 0, run.error?.message || run.stderr);
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
});

test('MP4 track metadata always contains MIME and geometry or PCM format even when encoder descriptions omit them', () => {
  const source = fs.readFileSync(path.join(directory, 'realtime_recorder.cpp'), 'utf8');
  const method = source.slice(source.indexOf('  Format MuxerFormat('), source.indexOf('  void OpenTrackMuxer('));
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'xlab-muxer-format-'));
  try {
    const harness = path.join(temporary, 'format.cpp'), executable = path.join(temporary, 'format');
    fs.writeFileSync(harness, `
#include <cassert>
#include <cstdint>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
struct OH_AVFormat { std::map<std::string, int> ints; std::string mime; std::vector<uint8_t> config; };
struct OH_AVCodec {};
struct OH_AVCodecBufferAttr { int offset = 0, size = 0; };
struct OH_AVBuffer { std::vector<uint8_t> data; OH_AVCodecBufferAttr attr; };
const char *OH_AVCODEC_MIMETYPE_VIDEO_AVC = "video/avc", *OH_AVCODEC_MIMETYPE_AUDIO_AAC = "audio/mp4a-latm";
const char *OH_MD_KEY_PROFILE = "profile", *OH_MD_KEY_AAC_IS_ADTS = "adts", *OH_MD_KEY_CODEC_CONFIG = "config";
constexpr int AAC_PROFILE_LC = 0;
void OH_AVFormat_Destroy(OH_AVFormat *format) { delete format; }
using Format = std::unique_ptr<OH_AVFormat, decltype(&OH_AVFormat_Destroy)>;
OH_AVFormat *OH_AVFormat_CreateVideoFormat(const char *mime, int w, int h) {
  auto *format = new OH_AVFormat; format->mime = mime; format->ints = {{"width", w}, {"height", h}}; return format;
}
OH_AVFormat *OH_AVFormat_CreateAudioFormat(const char *mime, int rate, int channels) {
  auto *format = new OH_AVFormat; format->mime = mime; format->ints = {{"sampleRate", rate}, {"channels", channels}}; return format;
}
OH_AVFormat *OH_VideoEncoder_GetOutputDescription(OH_AVCodec *) {
  auto *format = new OH_AVFormat; format->ints["stride"] = 672; format->config = {1, 2, 3}; return format;
}
OH_AVFormat *OH_AudioCodec_GetOutputDescription(OH_AVCodec *codec) { return OH_VideoEncoder_GetOutputDescription(codec); }
bool OH_AVFormat_SetIntValue(OH_AVFormat *format, const char *key, int value) { format->ints[key] = value; return true; }
bool OH_AVFormat_GetBuffer(OH_AVFormat *format, const char *, uint8_t **data, size_t *size) {
  *data = format->config.data(); *size = format->config.size(); return true;
}
bool OH_AVFormat_SetBuffer(OH_AVFormat *format, const char *, uint8_t *data, size_t size) {
  format->config.assign(data, data + size); return true;
}
int OH_AVBuffer_GetBufferAttr(OH_AVBuffer *buffer, OH_AVCodecBufferAttr *attr) { *attr = buffer->attr; return 0; }
uint8_t *OH_AVBuffer_GetAddr(OH_AVBuffer *buffer) { return buffer->data.data(); }
int OH_AVBuffer_GetCapacity(OH_AVBuffer *buffer) { return buffer->data.size(); }
void Check(int code, const char *reason) { if (code) throw std::runtime_error(reason); }
struct Track { bool video; int width = 640, height = 480, sampleRate = 48000, channels = 2; OH_AVCodec *codec = nullptr; };
struct Harness { ${method} };
int main() {
  Harness h;
  Track video{true}, audio{false};
  auto v = h.MuxerFormat(video, nullptr), a = h.MuxerFormat(audio, nullptr);
  assert(v->mime == "video/avc" && v->ints.at("width") == 640 && v->ints.at("height") == 480);
  assert(a->mime == "audio/mp4a-latm" && a->ints.at("sampleRate") == 48000 && a->ints.at("channels") == 2);
  assert(a->ints.at("profile") == AAC_PROFILE_LC && a->ints.at("adts") == 0);
  assert(v->ints.count("stride") == 0 && a->ints.count("stride") == 0);
  assert(v->config == std::vector<uint8_t>({1, 2, 3}));
  OH_AVBuffer config{{99, 98, 7, 6}, {2, 2}};
  auto overridden = h.MuxerFormat(video, &config);
  assert(overridden->config == std::vector<uint8_t>({7, 6}));
  config.attr.size = 3;
  bool failed = false;
  try { h.MuxerFormat(video, &config); } catch (const std::runtime_error &) { failed = true; }
  assert(failed);
}
`);
    const compile = spawnSync(process.env.CXX || 'clang++', ['-std=c++17', '-fsanitize=address,undefined',
      harness, '-o', executable], { encoding: 'utf8', timeout: 30000 });
    assert.equal(compile.status, 0, compile.stderr);
    const run = spawnSync(executable, [], { encoding: 'utf8', timeout: 10000 });
    assert.equal(run.status, 0, run.error?.message || run.stderr);
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
});

test('native finalization is queued off the ArkTS caller and MP4 remuxing preserves cross-track offsets', () => {
  const module = fs.readFileSync(path.join(directory, 'recorder_module.cpp'), 'utf8');
  const source = fs.readFileSync(path.join(directory, 'realtime_recorder.cpp'), 'utf8');
  const entry = module.slice(module.indexOf('napi_value Finish('), module.indexOf('napi_value Initialize('));
  assert.match(entry, /napi_create_async_work/); assert.match(entry, /napi_queue_async_work/);
  assert.doesNotMatch(entry, /recorder->Finish\(/);
  assert.match(module, /work\.handle\.recorder->Finish\(work.cancel\)/);
  assert.match(source, /std::min\(video_\.originUs, audio_\.originUs\)/);
  assert.match(source, /video.offsetUs = video_\.originUs - originUs/);
  assert.match(source, /audio.offsetUs = audio_\.originUs - originUs/);
  assert.match(source, /attr.pts \+= offsetUs/);
  assert.match(source, /OH_AVMuxer_SetRotation\(muxer, video_\.rotation\)/);
  assert.match(source, /else audio.ended = true/);
});
