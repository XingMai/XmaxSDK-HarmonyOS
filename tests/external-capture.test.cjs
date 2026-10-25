const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

function fixture() {
  const events = [], videos = [], audio = [], errors = [], converted = [];
  const native = { convertExternalVideoFrame(frame, width, height) {
    converted.push(frame.timestampUs);
    const output = new Uint8Array(width * height * 3 / 2);
    output.set(new Uint8Array(frame.planes[0].data).subarray(0, Math.min(output.length, 4)));
    return output.buffer;
  } };
  const load = loadEts({
    'libxmax_video.so': { default: native },
    '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
    XmaxLogger: { XmaxLogger: { error: message => events.push(message) } }
  });
  const { RealtimeVideoFormat: Format } = load('service/realtime/RealtimeVideoFormat.ets');
  const { RealtimeVideoFrame: Video } = load('service/realtime/RealtimeVideoFrame.ets');
  const { RealtimeAudioFrame: Audio } = load('service/realtime/RealtimeMediaFrame.ets');
  const { VideoFramePlane: Plane } = load('foundation/media/video/VideoFramePlane.ets');
  const { ExternalVideoFrameSink: Sink } = load('media/external/ExternalVideoFrameSink.ets');
  const { ExternalVideoController: Controller } = load('media/external/ExternalVideoController.ets');
  const { ExternalAudioFrameConverter: Converter } = load('media/external/ExternalAudioFrameConverter.ets');
  const { MediaService } = load('service/media/MediaService.ets');
  const rtc = { useExternalVideoSource() { events.push('video-source'); },
    startExternalAudioSource() { events.push('audio-source'); },
    stopExternalAudioSource() { events.push('stop-audio'); },
    renderLibraryName() { return 'test'; },
    bindLocalVideo() {}, unbindLocalVideo() { events.push('unbind'); } };
  const stream = { setVideoEncoderConfig(format) { events.push(['encoding', format]); },
    pushLocalVideoFrame(frame) { videos.push(frame); }, pushLocalAudioFrame(frame) { audio.push(frame); } };
  const controller = new Controller(rtc, stream, new MediaService(), error => errors.push(error));
  const video = (time = 1000000, width = 4, height = 4, pixelFormat = 'nv12') =>
    new Video(width, height, pixelFormat,
      pixelFormat === 'bgra' ? [new Plane(new Uint8Array(width * height * 4).fill(42).buffer, width * 4)] :
        [new Plane(new Uint8Array(width * height).fill(42).buffer, width),
          new Plane(new Uint8Array(width * height / 2).fill(128).buffer, width)],
      time, 0);
  const pcm = (time = 1000000, rate = 48000, channels = 1, count = 480) => {
    const samples = new Int16Array(count * channels);
    samples.fill(1200);
    return new Audio(new Uint8Array(samples.buffer), rate, channels, count, time);
  };
  const source = (hasAudio = false, width = 1280, height = 720) => ({
    videoFormat: new Format(width, height, 24, 100, 3000), hasAudio,
    starts: 0, stops: 0,
    async start(sink) { this.starts++; this.sink = sink; },
    async stop() { this.stops++; this.sink = null; }
  });
  const sink = (hasAudio = true) => new Sink(new Format(4, 4, 24), new Format(4, 4, 24), hasAudio,
    value => videos.push(value), value => audio.push(value), error => errors.push(error));
  return { load, Format, Video, Plane, Audio, Controller, Converter, controller, events, videos, audio,
    errors, converted, native, video, pcm, source, sink };
}

test('external binding is ready without first frame, preserves FPS, opts into PCM without microphone, and invalidates old sinks', async () => {
  const f = fixture(), source = f.source(true);
  const local = await f.controller.createExternalVideoStream(source);
  const old = source.sink;
  assert.equal(source.starts, 1);
  assert.equal(f.controller.hasAudio, true);
  assert.equal(local.videoTrack.videoFormat.fps, 24);
  assert.equal(local.videoTrack.videoFormat.maximumBitrate, 3000);
  assert.ok(f.events.includes('audio-source'));
  await f.controller.stopExternalVideoStream();
  await f.controller.stopExternalVideoStream();
  assert.equal(source.stops, 1);
  assert.equal(f.controller.currentTrack, null);
  assert.equal(old.isRequestingFrames, false);
  old.pushVideo(f.video()); old.pushAudio(f.pcm()); old.reportError(new Error('late'));
  assert.equal(f.videos.length + f.audio.length + f.errors.length, 0);
  const next = f.source();
  await f.controller.createExternalVideoStream(next);
  assert.equal(next.sink.isRequestingFrames, true);
  assert.equal(old.isRequestingFrames, false);
  await f.controller.stopExternalVideoStream();
});

test('external original size is resized within model limits, aligned to four, and small sources are upscaled', async () => {
  const f = fixture(), large = f.source(false, 3840, 2160);
  await f.controller.createExternalVideoStream(large);
  assert.ok(large.sink.videoFormat.width * large.sink.videoFormat.height <= 2073600);
  assert.equal(large.sink.videoFormat.width % 4, 0);
  assert.equal(large.videoFormat.width, 3840);
  await f.controller.stopExternalVideoStream();
  const small = f.source(false, 200, 200);
  await f.controller.createExternalVideoStream(small);
  assert.ok(small.sink.videoFormat.width > 200);
  assert.ok(small.sink.videoFormat.width * small.sink.videoFormat.height >= f.controller.mediaService.model.minimumInputPixels);
  await f.controller.stopExternalVideoStream();
});

test('external conversion owns returned pixels, preserves PTS and removes rotated or wrong-size sources', () => {
  const f = fixture(), sink = f.sink(), input = f.video();
  sink.pushVideo(input);
  new Uint8Array(input.planes[0].data).fill(0);
  assert.equal(new Uint8Array(f.videos[0].planes[0].data)[0], 42);
  assert.equal(f.videos[0].timestampUs, 1000000);
  assert.equal(f.videos[0].format.pixelFormat, 'nv12');
  for (const time of [NaN, -1, 1000000, 999999]) sink.pushVideo(f.video(time));
  assert.equal(f.converted.length, 1);
  sink.pushVideo(f.video(1001000, 8, 4));
  assert.equal(sink.isRequestingFrames, false);
  sink.reportError(new Error('late'));
  assert.equal(f.errors.length, 1);
});

test('BGRA frames use the same video path and errors invalidate video and audio together', () => {
  const f = fixture(), sink = f.sink();
  sink.pushVideo(f.video(1, 4, 4, 'bgra'));
  sink.pushAudio(f.pcm(2000000));
  assert.equal(f.videos.length, 1);
  assert.equal(f.audio.length, 1);
  f.native.convertExternalVideoFrame = () => { throw new Error('conversion'); };
  sink.pushVideo(f.video(2));
  sink.pushAudio(f.pcm(2010000));
  assert.equal(f.errors.length, 1);
  assert.equal(f.audio.length, 1);
});

test('external start failure rolls back once and permits a fresh binding', async () => {
  const f = fixture(), source = f.source(true);
  source.start = async function (sink) { this.sink = sink; throw new Error('start failed'); };
  await assert.rejects(f.controller.createExternalVideoStream(source), /start failed/);
  assert.equal(source.stops, 1);
  assert.equal(f.controller.hasAudio, false);
  assert.equal(f.controller.currentTrack, null);
  await f.controller.createExternalVideoStream(f.source());
  await f.controller.stopExternalVideoStream();
});

test('close invalidates a pending external start without waiting for its producer Promise', async () => {
  const f = fixture(), source = f.source();
  let resolveStart;
  source.start = async function (sink) { this.sink = sink; await new Promise(resolve => { resolveStart = resolve; }); };
  const starting = f.controller.createExternalVideoStream(source).then(() => null, error => error);
  await Promise.resolve();
  const old = source.sink;
  f.controller.prepareForStop();
  const error = await starting;
  assert.equal(error.code, 'CANCELLED');
  assert.equal(source.stops, 1);
  assert.equal(old.isRequestingFrames, false);
  resolveStart();
  await Promise.resolve();
  assert.equal(f.controller.currentTrack, null);
});

test('external PCM joins partial buffers, preserves audio/video offset, and never plays opted-out audio', () => {
  const f = fixture(), sink = f.sink();
  sink.pushVideo(f.video(20000000));
  sink.pushAudio(f.pcm(20025000, 48000, 1, 200));
  assert.equal(f.audio.length, 0);
  sink.pushAudio(f.pcm(20025000 + 200 * 1000000 / 48000, 48000, 1, 280));
  assert.equal(f.audio.length, 1);
  assert.equal(f.audio[0].timestampUs, 20025000);
  assert.equal(f.audio[0].data.length, 960);
  assert.equal(f.audio[0].timestampUs - f.videos[0].timestampUs, 25000);
  f.sink(false).pushAudio(f.pcm());
  assert.equal(f.audio.length, 1);
});

test('external 44.1 kHz stereo PCM is resampled continuously across packet boundaries', () => {
  const f = fixture(), converter = new f.Converter(), received = [];
  for (let i = 0; i < 20; i++)
    converter.append(f.pcm(3000000 + i * 10000, 44100, 2, 441), value => received.push(value));
  assert.ok(received.length >= 19 && received.length <= 20);
  received.forEach((value, index) => {
    assert.equal(value.timestampUs, 3000000 + index * 10000);
    assert.equal(value.data.length, 960);
    assert.equal(new DataView(value.data.buffer).getInt16(0, true), 1200);
  });
});

test('external PCM drops overlaps, ignores invalid timestamps, and restarts a gapped segment without filling silence', () => {
  const f = fixture(), converter = new f.Converter(), received = [];
  const append = frame => converter.append(frame, value => received.push(value));
  append(f.pcm(NaN)); append(f.pcm(-1));
  append(f.pcm(1000000));
  append(f.pcm(1000000));
  append(f.pcm(2000000, 48000, 1, 240));
  append(f.pcm(3000000));
  assert.deepEqual(received.map(frame => frame.timestampUs), [1000000, 3000000]);
  assert.throws(() => append(f.pcm(4000000, 44100)), /cannot change/);
});
