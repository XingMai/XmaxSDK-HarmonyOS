const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');
const settle = async () => { for (let i = 0; i < 30; i++) await Promise.resolve(); };
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

function decoderFixture() {
  const opening = deferred(), initialization = deferred(), releasing = deferred();
  const calls = { closed: 0, created: 0, released: 0, paused: 0, resumed: [], frames: 0 };
  let callback;
  const native = {
    pause() { calls.paused++; },
    resume(offset) { calls.resumed.push(offset); },
    release() { calls.released++; return releasing.promise; }
  };
  const load = loadEts({
    '@kit.CoreFileKit': { fileIo: {
      OpenMode: { READ_ONLY: 0 },
      open: () => opening.promise,
      stat: async () => ({ size: 1234 }),
      close: async () => { calls.closed++; }
    } },
    '@ohos.systemDateTime': { default: { TimeType: { ACTIVE: 0 }, getUptime: () => 1000000000 } },
    'libxmax_video.so': { default: { createVideoFileDecoder(...args) {
      calls.created++; callback = args.at(-1); return initialization.promise;
    } } }
  });
  const { VideoFileFrameDecoder } = load('foundation/media/video/VideoFileFrameDecoder.ets');
  const decoder = new VideoFileFrameDecoder('file', 0, 2, 2, 33333,
    { onFrame() { calls.frames++; }, onEndOfStream() {}, onError() {} }, 1000000, 0, 1000000);
  return { decoder, opening, initialization, releasing, calls, native,
    emit() { callback(new ArrayBuffer(6), 2, 2, 2, 1000000, false); } };
}

test('file and native initialization are asynchronous and playback requires explicit activation', async () => {
  const f = decoderFixture();
  assert.equal(f.calls.created, 0);
  f.opening.resolve({ fd: 9 }); await settle();
  assert.equal(f.calls.created, 1);
  let ready = false;
  f.decoder.ready.then(() => { ready = true; }); await settle();
  assert.equal(ready, false);
  f.initialization.resolve(f.native); await f.decoder.ready;
  assert.equal(f.calls.closed, 1);
  assert.deepEqual(f.calls.resumed, []);
  f.decoder.activate(500000);
  f.decoder.activate(500000);
  assert.deepEqual(f.calls.resumed, [500000]);
  f.decoder.pause(); f.decoder.resume(20000);
  assert.equal(f.calls.paused, 1);
  assert.deepEqual(f.calls.resumed, [500000, 20000]);
  f.releasing.resolve(); await f.decoder.release();
});

test('exit during initialization waits for cleanup, suppresses callbacks and releases once', async () => {
  const f = decoderFixture();
  f.opening.resolve({ fd: 9 }); await settle();
  const stopping = f.decoder.release();
  assert.equal(f.decoder.release(), stopping);
  let stopped = false;
  stopping.then(() => { stopped = true; });
  f.initialization.resolve(f.native); await settle();
  assert.equal(stopped, false);
  assert.equal(f.calls.released, 1);
  f.emit(); f.decoder.activate(0); f.decoder.resume(0);
  assert.equal(f.calls.frames, 0);
  assert.deepEqual(f.calls.resumed, []);
  f.releasing.resolve(); await stopping;
  assert.equal(stopped, true);
});

test('exit before file open skips native creation; initialization failure still closes the file', async () => {
  const cancelled = decoderFixture();
  const stopping = cancelled.decoder.release();
  cancelled.opening.resolve({ fd: 9 }); await stopping;
  assert.equal(cancelled.calls.created, 0);
  assert.equal(cancelled.calls.closed, 1);
  const failed = decoderFixture();
  const rejection = assert.rejects(failed.decoder.ready, /codec failed/);
  failed.opening.resolve({ fd: 9 }); await settle();
  failed.initialization.reject(new Error('codec failed'));
  await rejection; await failed.decoder.release();
  assert.equal(failed.calls.closed, 1);
  assert.equal(failed.calls.released, 0);
});

test('pausing during loop initialization keeps the ready decoder paused until resume', async () => {
  const f = decoderFixture();
  f.opening.resolve({ fd: 9 }); await settle();
  f.decoder.pause();
  f.initialization.resolve(f.native); await f.decoder.ready;
  f.decoder.activate(30000);
  assert.deepEqual(f.calls.resumed, []);
  f.decoder.resume(50000);
  assert.deepEqual(f.calls.resumed, [80000]);
  f.releasing.resolve(); await f.decoder.release();
});

function sourceFixture() {
  let nowUs = 1000000;
  const decoders = [], errors = [], timers = [];
  class Decoder {
    constructor() {
      this.gate = deferred(); this.ready = this.gate.promise;
      this.activations = []; this.releaseCount = 0; decoders.push(this);
    }
    activate(offset) { this.activations.push(offset); }
    pause() {}
    resume() {}
    release() {
      if (!this.releasing) {
        this.releaseCount++;
        this.releasing = this.ready.catch(() => {});
      }
      return this.releasing;
    }
  }
  const load = loadEts({
    '@ohos.systemDateTime': { default: { TimeType: { ACTIVE: 0 }, getUptime: () => nowUs * 1000 } },
    VideoFileFrameDecoder: { VideoFileFrameDecoder: Decoder },
    XmaxLogger: { XmaxLogger: { error() {} } }
  }, { setTimeout(fn) { timers.push(fn); return timers.length; } });
  const { VideoSourceController } = load('media/video/VideoSourceController.ets');
  const { MediaTimeline } = load('media/MediaTimeline.ets');
  const source = new VideoSourceController(() => {}, error => errors.push(error));
  source.configure('file', 0, 2, 2, 30);
  const timeline = new MediaTimeline(0, 1000000);
  return { source, timeline, decoders, errors, timers, set now(value) { nowUs = value; } };
}

test('initialization time moves the shared timeline before video and audio are started', async () => {
  const f = sourceFixture();
  const start = f.source.start(f.timeline);
  assert.equal(f.timeline.playbackAnchorForLoop(0), 1100000);
  f.now = 1800000;
  f.decoders[0].gate.resolve(); await start;
  assert.equal(f.timeline.playbackAnchorForLoop(0), 1900000);
  assert.deepEqual(f.decoders[0].activations, [800000]);
  await f.source.stop();
});

test('exit during source initialization cannot activate a stale decoder', async () => {
  const f = sourceFixture();
  const start = f.source.start(f.timeline);
  const cancelled = assert.rejects(start, error => error.code === 'CANCELLED');
  const stop = f.source.stop();
  f.decoders[0].gate.resolve();
  await cancelled; await stop;
  assert.deepEqual(f.decoders[0].activations, []);
  assert.equal(f.decoders[0].releaseCount, 1);
  assert.equal(f.source.decoder, null);
});

test('loop initialization does not shift the ongoing shared audio clock', async () => {
  const f = sourceFixture();
  const start = f.source.start(f.timeline);
  f.now = 1100000; f.decoders[0].gate.resolve(); await start;
  const anchor = f.timeline.playbackAnchorForLoop(0);
  const restarting = f.source.restartAfterEndOfStream(f.decoders[0], 0);
  await settle();
  assert.equal(f.decoders.length, 2);
  f.now = 2300000; f.decoders[1].gate.resolve(); await restarting;
  assert.equal(f.timeline.playbackAnchorForLoop(0), anchor);
  assert.deepEqual(f.decoders[1].activations, [0]);
  await f.source.stop();
});
