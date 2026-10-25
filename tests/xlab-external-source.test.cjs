const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const { loadEts } = require('./ets-loader.cjs');

test('app-owned file source forwards public video/PCM frames, paces video, and detaches before async release', async () => {
  const sdk = loadEts();
  const { RealtimeVideoFormat } = sdk('service/realtime/RealtimeVideoFormat.ets');
  const { RealtimeVideoFrame } = sdk('service/realtime/RealtimeVideoFrame.ets');
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
    'libxlab_recorder.so': { async createFileSource(fd, size, callback) {
      assert.equal(fd, 7); assert.equal(size, 100); onFrame = callback; return decoder;
    } }
  });
  const { RealtimeFileVideoSource } = load(path.resolve(__dirname,
    '../examples/XLab/entry/src/main/ets/modules/xlrealtime/external/RealtimeFileVideoSource.ets'));
  const source = await RealtimeFileVideoSource.create('file://media/video.mp4', 24);
  assert.equal(closed, 1);
  const videos = [], audio = [], errors = [];
  await source.start({ isRequestingFrames: true, pushVideo: value => videos.push(value),
    pushAudio: value => audio.push(value), reportError: value => errors.push(value) });
  for (let i = 0; i < 30; i++) onFrame({ video: true, width: 4, height: 4,
    timestampUs: 1000000 + i * 1000000 / 30, data: new ArrayBuffer(24) });
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

test('app native decoded frames remove padding, apply file rotation, and reject HDR rather than misreading P010', () => {
  const cpp = path.resolve(__dirname, '../examples/XLab/entry/src/main/cpp/file_frame_source.cpp');
  const source = fs.readFileSync(cpp, 'utf8');
  const copy = source.slice(source.indexOf('  std::unique_ptr<Frame> CopyFrame('), source.indexOf('  void Drain('));
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'xlab-external-file-'));
  try {
    const harness = path.join(directory, 'frames.cpp'), executable = path.join(directory, 'frames');
    fs.writeFileSync(harness, `
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
struct Track { bool video; int width = 4, height = 2, rotation = 90, sampleRate = 48000, channels = 2; void *codec = nullptr; };
struct Harness { int64_t firstMediaUs_ = -1; bool timelineStarted_ = false; ${copy} };
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
}
`);
    const compile = spawnSync('clang++', ['-std=c++17', '-fsanitize=address,undefined', harness, '-o', executable],
      { encoding: 'utf8', timeout: 30000 });
    assert.equal(compile.status, 0, compile.stderr);
    const run = spawnSync(executable, [], { encoding: 'utf8', timeout: 10000 });
    assert.equal(run.status, 0, run.stderr);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});
