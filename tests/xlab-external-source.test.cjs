const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const { loadEts } = require('./ets-loader.cjs');

test('app-owned file source passes native size/FPS limits, forwards video/PCM, and detaches before async release', async () => {
  const sdk = loadEts();
  const { RealtimeVideoFormat } = sdk('service/realtime/RealtimeVideoFormat.ets');
  const { RealtimeVideoFrame } = sdk('foundation/media/video/RealtimeVideoFrame.ets');
  const { RealtimeAudioFrame } = sdk('service/realtime/RealtimeMediaFrame.ets');
  const { VideoFramePlane } = sdk('foundation/media/video/VideoFramePlane.ets');
  let onFrame, releases = 0, starts = 0, closed = 0;
  const decoder = { width: 4, height: 4, hasAudio: true,
    start() { starts++; }, async release() { releases++; } };
  const load = loadEts({
    '@xmax/sdk': { RealtimeVideoFormat, RealtimeVideoFrame, RealtimeAudioFrame, VideoFramePlane,
      VideoPixelFormat: { NV12: 'nv12' }, VideoRotation: { ROTATION_0: 0 } },
    '@kit.CoreFileKit': { fileIo: { OpenMode: { READ_ONLY: 0 }, async open() { return { fd: 7 }; },
      async stat() { return { size: 100 }; }, async close() { closed++; } } },
    'libxlab_recorder.so': { async createFileSource(fd, size, maximumPixels, fps, callback) {
      assert.equal(fd, 7); assert.equal(size, 100);
      assert.equal(maximumPixels, 1280000); assert.equal(fps, 24);
      onFrame = callback; return decoder;
    } }
  });
  const { RealtimeFileVideoSource } = load(path.resolve(__dirname,
    '../examples/XLab/entry/src/main/ets/modules/xlrealtime/external/RealtimeFileVideoSource.ets'));
  const source = await RealtimeFileVideoSource.create('file://media/video.mp4', 24, 1280000);
  assert.equal(closed, 1);
  const videos = [], audio = [], errors = [];
  await source.start({ isRequestingFrames: true, pushVideo: value => videos.push(value),
    pushAudio: value => audio.push(value), reportError: value => errors.push(value) });
  for (let i = 0; i < 24; i++) onFrame({ video: true, width: 4, height: 4,
    timestampUs: 1000000 + i * 1000000 / 24, data: new ArrayBuffer(24) });
  assert.equal(starts, 1);
  assert.equal(videos.length, 24);
  onFrame({ video: false, sampleRate: 48000, channels: 2, timestampUs: 1025000, data: new ArrayBuffer(1920) });
  assert.equal(audio[0].samplesPerChannel, 480);
  assert.equal(audio[0].timestampUs, 1025000);
  onFrame({ error: 'decoder failed' });
  assert.equal(errors[0].message, 'decoder failed');
  await source.stop(); await source.stop();
  onFrame({ error: 'late' });
  assert.equal(releases, 1);
  assert.equal(errors.length, 1);
});

test('app native decoded frames remove padding, apply file rotation, and reject unconverted P010', () => {
  const cpp = path.resolve(__dirname, '../examples/XLab/entry/src/main/cpp/file_frame_source.cpp');
  const source = fs.readFileSync(cpp, 'utf8');
  const copy = source.slice(source.indexOf('  std::unique_ptr<Frame> CopyVideoFrame('), source.indexOf('  void Drain('));
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'xlab-external-file-'));
  try {
    const harness = path.join(directory, 'frames.cpp'), executable = path.join(directory, 'frames');
    fs.writeFileSync(harness, `
#include <algorithm>
#include <cassert>
#include <cstring>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
struct OH_AVCodecBufferAttr { int64_t pts; int offset, size; };
struct OH_AVFormat {};
struct OH_AVBuffer { std::vector<uint8_t> data; };
void OH_AVFormat_Destroy(OH_AVFormat *p) { delete p; }
using Format = std::unique_ptr<OH_AVFormat, decltype(&OH_AVFormat_Destroy)>;
const char *OH_MD_KEY_VIDEO_STRIDE = "stride", *OH_MD_KEY_VIDEO_SLICE_HEIGHT = "slice",
 *OH_MD_KEY_PIXEL_FORMAT = "pixels", *OH_MD_KEY_AUDIO_SAMPLE_FORMAT = "sample",
 *OH_MD_KEY_AUD_SAMPLE_RATE = "rate", *OH_MD_KEY_AUD_CHANNEL_COUNT = "channels";
constexpr int AV_PIXEL_FORMAT_NV12 = 2, SAMPLE_S16LE = 1;
int pixels = 2;
bool OH_AVFormat_GetIntValue(OH_AVFormat *, const char *key, int *value) {
  if (key == OH_MD_KEY_VIDEO_STRIDE) *value = 8;
  else if (key == OH_MD_KEY_VIDEO_SLICE_HEIGHT) *value = 4;
  else if (key == OH_MD_KEY_PIXEL_FORMAT) *value = pixels;
  else if (key == OH_MD_KEY_AUDIO_SAMPLE_FORMAT) *value = 1;
  else if (key == OH_MD_KEY_AUD_SAMPLE_RATE) *value = 48000;
  else if (key == OH_MD_KEY_AUD_CHANNEL_COUNT) *value = 2;
  return true;
}
OH_AVFormat *OH_VideoDecoder_GetOutputDescription(void *) { return new OH_AVFormat; }
OH_AVFormat *OH_AudioCodec_GetOutputDescription(void *c) { return OH_VideoDecoder_GetOutputDescription(c); }
uint8_t *OH_AVBuffer_GetAddr(OH_AVBuffer *b) { return b->data.data(); }
int OH_AVBuffer_GetCapacity(OH_AVBuffer *b) { return b->data.size(); }
struct Frame {
 bool video = false; int width = 0, height = 0, sampleRate = 0, channels = 0;
 int64_t timestampUs = 0; std::vector<uint8_t> data;
};
struct Track {
 bool video; int width = 4, height = 2, outputWidth = 4, outputHeight = 2, rotation = 90, sampleRate = 48000, channels = 2;
 bool hasVideoAnchor = false; int64_t videoAnchorPts = 0, videoBucket = -1; void *codec = nullptr;
};
struct Harness { int64_t firstMediaUs_ = -1; int fps_ = 24; bool timelineStarted_ = false; ${copy} };
int main() {
 Harness h; Track video{true}, audio{false};
 OH_AVBuffer buffer{std::vector<uint8_t>(48, 253)};
 for (int y = 0; y < 2; y++) for (int x = 0; x < 4; x++) buffer.data[y * 8 + x] = y * 4 + x;
 buffer.data[32] = 100; buffer.data[33] = 150; buffer.data[34] = 101; buffer.data[35] = 151;
 auto frame = h.CopyFrame(video, &buffer, {100, 0, 48});
 assert(frame->width == 2 && frame->height == 4);
 assert(frame->data == std::vector<uint8_t>({4,0,5,1,6,2,7,3,100,150,101,151}));
 auto pcm = h.CopyFrame(audio, &buffer, {75, 2, 4});
 assert(pcm->timestampUs == 75 && h.firstMediaUs_ == 75);
 assert(pcm->channels == 2 && pcm->sampleRate == 48000);
 assert(pcm->data == std::vector<uint8_t>({2,3,253,253}));
 pixels = 99; bool failed = false;
 try { h.CopyFrame(video, &buffer, {200, 0, 48}); } catch (const std::runtime_error &) { failed = true; }
 assert(failed);

 // Cross tile boundaries with unequal Y/UV padding, optional downscaling, and all rotations.
 const int inputWidth = 70, inputHeight = 38, yStride = 80, uvStride = 86;
 std::vector<uint8_t> yData(yStride * inputHeight), uvData(uvStride * inputHeight / 2);
 for (size_t i = 0; i < yData.size(); i++) yData[i] = (i * 13) % 251;
 for (size_t i = 0; i < uvData.size(); i++) uvData[i] = (i * 7) % 241;
 for (int rotation : {0, 90, 180, 270}) for (bool scaled : {false, true}) {
   video.outputWidth = scaled ? 36 : inputWidth; video.outputHeight = scaled ? 20 : inputHeight;
   video.rotation = rotation;
   auto image = h.CopyVideoFrame(video, yData.data(), yStride, uvData.data(), uvStride, inputWidth, inputHeight, 999);
   const int lumaLength = image->width * image->height;
   for (int plane = 0; plane < 2; plane++) {
     const int step = plane ? 2 : 1, preW = video.outputWidth / step, preH = video.outputHeight / step;
     const int outW = image->width / step, outH = image->height / step;
     const auto &data = plane ? uvData : yData;
     const int stride = plane ? uvStride : yStride;
     for (int oy = 0; oy < outH; oy++) for (int ox = 0; ox < outW; ox++) {
       int px = ox, py = oy;
       if (rotation == 90) { px = oy; py = preH - 1 - ox; }
       else if (rotation == 180) { px = preW - 1 - ox; py = preH - 1 - oy; }
       else if (rotation == 270) { px = preW - 1 - oy; py = ox; }
       const int sx = px * (inputWidth / step) / preW, sy = py * (inputHeight / step) / preH;
       for (int component = 0; component < step; component++)
         assert(image->data[(plane ? lumaLength : 0) + (oy * outW + ox) * step + component] ==
             data[sy * stride + sx * step + component]);
     }
   }
 }
}
`);
    const compile = spawnSync('clang++', ['-std=c++17', '-fsanitize=address,undefined', harness, '-o', executable],
      { encoding: 'utf8', timeout: 30000 });
    assert.equal(compile.status, 0, compile.stderr);
    const run = spawnSync(executable, [], { encoding: 'utf8', timeout: 10000 });
    assert.equal(run.status, 0, run.stderr);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('app native file loops rebuild the source/demuxer pair and clean up on stop or failure', () => {
  const source = fs.readFileSync(path.resolve(__dirname,
    '../examples/XLab/entry/src/main/cpp/file_frame_source.cpp'), 'utf8');
  const feed = source.slice(source.indexOf('  void Feed('), source.indexOf('  /** Copies upright NV12'));
  const lifecycle = source.slice(source.indexOf('  void CloseTrack('), source.indexOf('\n};\n\nvoid Require('));
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'xlab-external-loop-'));
  try {
    const harness = path.join(directory, 'loops.cpp'), executable = path.join(directory, 'loops');
    fs.writeFileSync(harness, `
#include <algorithm>
#include <atomic>
#include <cassert>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <deque>
#include <fcntl.h>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <unistd.h>
#include <vector>
using Clock = std::chrono::steady_clock;
using OH_AVErrCode = int;
constexpr int AV_ERR_OK = 0, AVCODEC_BUFFER_FLAGS_EOS = 1, SEEK_MODE_CLOSEST_SYNC = 0;
constexpr int napi_ok = 0, napi_tsfn_blocking = 0;
struct OH_AVCodecBufferAttr { int64_t pts = 0; int size = 0, flags = 0; };
struct OH_AVBuffer { OH_AVCodecBufferAttr attr; };
struct OH_AVSource { bool alive = true; int codecs = 0; };
struct OH_AVDemuxer { OH_AVSource *source; int selected = 0; int reads[2] = {}; };
struct OH_AVCodec { OH_AVSource *source; };
int created = 0, destroyed = 0, demuxers = 0, cycles = 0, failRead = 0, failOpen = 0;
int frames = 0, callbacks = 0;
std::vector<std::string> errors;
OH_AVSource *OH_AVSource_CreateWithFD(int fd, int64_t offset, int64_t length) {
  assert(fcntl(fd, F_GETFD) != -1 && offset == 0 && length == 16);
  if (failOpen && created == failOpen) return nullptr;
  created++;
  return new OH_AVSource;
}
OH_AVDemuxer *OH_AVDemuxer_CreateWithSource(OH_AVSource *source) {
  demuxers++;
  return new OH_AVDemuxer{source};
}
int OH_AVDemuxer_Destroy(OH_AVDemuxer *demuxer) {
  assert(demuxer->source->codecs == 0);
  demuxer->source->alive = false;
  demuxers--;
  delete demuxer;
  return 0;
}
int OH_AVSource_Destroy(OH_AVSource *source) {
  assert(source->codecs == 0 && demuxers == 0);
  destroyed++;
  delete source;
  return 0;
}
int OH_AVDemuxer_SelectTrackByID(OH_AVDemuxer *demuxer, int id) {
  demuxer->selected |= 1 << id;
  return 0;
}
int OH_AVDemuxer_SeekToTime(OH_AVDemuxer *demuxer, int, int) {
  assert(demuxer->selected & 1);
  return 0;
}
int OH_AVDemuxer_ReadSampleBuffer(OH_AVDemuxer *demuxer, int id, OH_AVBuffer *buffer) {
  if (!demuxer->source->alive || !(demuxer->selected & (1 << id))) return 2;
  if (failRead && created == failRead) return 4;
  buffer->attr = {0, demuxer->reads[id] == 0 ? 1 : 0,
      demuxer->reads[id] == 0 ? 0 : AVCODEC_BUFFER_FLAGS_EOS};
  demuxer->reads[id]++;
  assert(demuxer->reads[id] <= 2);
  return 0;
}
int OH_AVBuffer_GetBufferAttr(OH_AVBuffer *buffer, OH_AVCodecBufferAttr *attr) { *attr = buffer->attr; return 0; }
int OH_VideoDecoder_PushInputBuffer(OH_AVCodec *, int) { return 0; }
int OH_AudioCodec_PushInputBuffer(OH_AVCodec *, int) { return 0; }
int OH_VideoDecoder_Stop(OH_AVCodec *) { return 0; }
int OH_AudioCodec_Stop(OH_AVCodec *) { return 0; }
int OH_VideoDecoder_Destroy(OH_AVCodec *codec) { codec->source->codecs--; delete codec; return 0; }
int OH_AudioCodec_Destroy(OH_AVCodec *codec) { return OH_VideoDecoder_Destroy(codec); }
void Check(int code, const char *message) {
  if (code) throw std::runtime_error(std::string(message) + ": " + std::to_string(code));
}
struct Frame { int64_t timestampUs = 0; std::string error; };
int napi_call_threadsafe_function(int, Frame *frame, int) {
  errors.push_back(frame->error);
  delete frame;
  return napi_ok;
}
struct Harness {
  struct FileVideoSurface {};
  struct Buffer { int index; OH_AVBuffer *value; };
  struct Track {
    bool video = false, ended = false, inputEnded = false;
    int id = 0;
    OH_AVCodec *codec = nullptr;
    std::deque<Buffer> inputs, outputs;
    std::unique_ptr<Frame> pending;
    std::unique_ptr<FileVideoSurface> surface;
    bool surfaceInputEnded = false;
    std::deque<int64_t> surfaceTimes;
    bool hasVideoAnchor = false;
    int64_t videoBucket = -1;
    OH_AVBuffer buffers[2];
  };
  int fd_ = -1, callback_ = 0;
  int64_t length_ = 16, lastOutputUs_ = -1, firstMediaUs_ = -1, anchorUs_ = 0;
  int64_t latestPrepareUs_ = 0;
  bool timelineStarted_ = false;
  std::atomic<bool> stopping_{false};
  std::mutex mutex_;
  std::condition_variable changed_;
  std::string error_;
  OH_AVSource *source_ = nullptr;
  OH_AVDemuxer *demuxer_ = nullptr;
  std::unique_ptr<Track> video_ = std::make_unique<Track>(), audio_;
  explicit Harness(bool audio) {
    FILE *file = tmpfile();
    assert(file);
    fd_ = dup(fileno(file));
    fclose(file);
    source_ = OH_AVSource_CreateWithFD(fd_, 0, length_);
    video_->video = true;
    if (audio) { audio_ = std::make_unique<Track>(); audio_->id = 1; }
  }
  bool Pop(std::deque<Buffer> &queue, Buffer &buffer) {
    if (queue.empty()) return false;
    buffer = queue.front(); queue.pop_front(); return true;
  }
  void Prepare(Track &track) {
    if (track.video) cycles++;
    track.codec = new OH_AVCodec{source_};
    source_->codecs++;
    OH_AVDemuxer_SelectTrackByID(demuxer_, track.id);
    track.inputs.push_back({0, &track.buffers[0]});
    track.inputs.push_back({1, &track.buffers[1]});
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
    latestPrepareUs_ = std::chrono::duration_cast<std::chrono::microseconds>(Clock::now().time_since_epoch()).count();
  }
  void Drain(Track &track) {
    if (!track.ended && track.inputEnded) {
      track.ended = true;
      track.pending = std::make_unique<Frame>();
    }
  }
  void DeliverNext() {
    assert(anchorUs_ >= latestPrepareUs_);
    for (Track *track : {video_.get(), audio_.get()}) {
      if (!track || !track->pending) continue;
      assert(anchorUs_ >= lastOutputUs_ + 10000);
      track->pending.reset();
      frames++;
    }
    lastOutputUs_ = anchorUs_;
    if (cycles == 5) stopping_ = true;
  }
  void FinishCallback() { callbacks++; }
  ${feed}
  ${lifecycle}
};
void Reset() {
  created = destroyed = demuxers = cycles = failRead = failOpen = frames = callbacks = 0;
  errors.clear();
}
void Verify(Harness &source, int fd) {
  assert(created == destroyed && demuxers == 0 && callbacks == 1);
  assert(source.source_ == nullptr && source.demuxer_ == nullptr && source.fd_ == -1);
  assert(fcntl(fd, F_GETFD) == -1);
  source.Close();
  assert(created == destroyed);
}
int main() {
  for (bool audio : {false, true}) {
    Reset(); Harness source(audio); int fd = source.fd_;
    source.Run();
    if (!errors.empty()) throw std::runtime_error(errors.front());
    assert(errors.empty() && cycles == 5 && created == 5 && frames == 5 * (audio ? 2 : 1));
    Verify(source, fd);
  }
  Reset(); Harness readFailure(true); int readFd = readFailure.fd_; failRead = 2;
  readFailure.Run();
  assert(errors == std::vector<std::string>{"Read external sample: 4"});
  assert(cycles == 2); Verify(readFailure, readFd);

  Reset(); Harness openFailure(false); int openFd = openFailure.fd_; failOpen = 1;
  openFailure.Run();
  assert(errors == std::vector<std::string>{"Cannot read external video"});
  Verify(openFailure, openFd);

  Reset(); Harness stopped(true); int stopFd = stopped.fd_; stopped.stopping_ = true;
  stopped.Run();
  assert(errors.empty() && cycles == 0); Verify(stopped, stopFd);
}
`);
    const compile = spawnSync('clang++', ['-std=c++17', '-fsanitize=address,undefined', harness, '-o', executable],
      { encoding: 'utf8', timeout: 30000 });
    assert.equal(compile.status, 0, compile.error?.message || compile.stderr);
    const run = spawnSync(executable, [], { encoding: 'utf8', timeout: 10000 });
    assert.equal(run.status, 0, run.error?.message || run.stderr);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('app HDR Surface conversion preserves NV12 planes/PTS, drains before EOS, and releases partial resources', () => {
  const cpp = path.resolve(__dirname, '../examples/XLab/entry/src/main/cpp');
  const source = fs.readFileSync(path.join(cpp, 'file_frame_source.cpp'), 'utf8');
  const header = fs.readFileSync(path.join(cpp, 'file_video_surface.h'), 'utf8');
  const implementation = fs.readFileSync(path.join(cpp, 'file_video_surface.cpp'), 'utf8')
    .replace(/^#include "[^"\n]+"\n/gm, '');
  const copy = source.slice(source.indexOf('  std::unique_ptr<Frame> CopyVideoFrame('),
    source.indexOf('  std::unique_ptr<Frame> CopyFrame('));
  const configure = source.slice(source.indexOf('  void ConfigureVideoOutput('), source.indexOf('  static void Error('));
  const drain = source.slice(source.indexOf('  void Drain('), source.indexOf('  /** Interleaves decoded tracks'));
  const template = fs.readFileSync(path.join(__dirname, 'native/xlab-file-video-surface.cpp'), 'utf8');
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'xlab-external-hdr-'));
  try {
    const harness = path.join(directory, 'surface.cpp'), executable = path.join(directory, 'surface');
    fs.writeFileSync(harness, template
      .replace('// FILE_VIDEO_SURFACE_HEADER', header)
      .replace('// FILE_VIDEO_SURFACE_IMPLEMENTATION', implementation)
      .replace('// FILE_VIDEO_COPY', copy)
      .replace('// FILE_VIDEO_CONFIGURE', configure)
      .replace('// FILE_VIDEO_DRAIN', drain));
    const compile = spawnSync('clang++', ['-std=c++17', '-fsanitize=address,undefined', harness, '-o', executable],
      { encoding: 'utf8', timeout: 30000 });
    assert.equal(compile.status, 0, compile.error?.message || compile.stderr);
    const run = spawnSync(executable, [], { encoding: 'utf8', timeout: 10000 });
    assert.equal(run.status, 0, run.error?.message || run.stderr);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('app external playback drops late frames at iOS thresholds without retiming or hiding errors', () => {
  const source = fs.readFileSync(path.resolve(__dirname,
    '../examples/XLab/entry/src/main/cpp/file_frame_source.cpp'), 'utf8');
  const frame = source.slice(source.indexOf('struct Frame {'), source.indexOf('/** Owns the system demuxer'));
  const deliver = source.slice(source.indexOf('  void DeliverNext('), source.indexOf('  void Release('));
  const callback = source.slice(source.indexOf('void Deliver(napi_env'), source.indexOf('using Source ='));
  const template = fs.readFileSync(path.join(__dirname, 'native/xlab-file-frame-expiry.cpp'), 'utf8');
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'xlab-external-expiry-'));
  try {
    const harness = path.join(directory, 'expiry.cpp'), executable = path.join(directory, 'expiry');
    fs.writeFileSync(harness, template
      .replace('// FILE_FRAME_AND_EXPIRY', frame)
      .replace('// FILE_DELIVER_NEXT', deliver)
      .replace('// FILE_DELIVER_CALLBACK', callback));
    const compile = spawnSync('clang++', ['-std=c++17', '-fsanitize=address,undefined', harness, '-o', executable],
      { encoding: 'utf8', timeout: 30000 });
    assert.equal(compile.status, 0, compile.error?.message || compile.stderr);
    const run = spawnSync(executable, [], { encoding: 'utf8', timeout: 10000 });
    assert.equal(run.status, 0, run.error?.message || run.stderr);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});
