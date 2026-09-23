const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');
const settle = async () => { for (let i = 0; i < 30; i++) await Promise.resolve(); };
const logger = { XmaxLogger: { error() {} } };
function deferred() {
  let resolve;
  const promise = new Promise(yes => { resolve = yes; });
  return { promise, resolve };
}

async function sourceFixture(kind, loop) {
  const decoders = [], timers = [], errors = [];
  let ended = 0;
  class Decoder {
    ready = Promise.resolve();
    constructor(...args) { this.listener = args[kind === 'video' ? 5 : 4]; decoders.push(this); }
    pause() {}
    resume() {}
    activate() {}
    release() { this.released = true; return Promise.resolve(); }
  }
  const load = loadEts({
    VideoFileFrameDecoder: { VideoFileFrameDecoder: Decoder },
    AudioFileFrameDecoder: { AudioFileFrameDecoder: Decoder },
    MediaTimeline: { MediaTimeline: { currentTimestampUs: () => 0 } },
    XmaxLogger: logger
  }, { setTimeout(fn) { timers.push(fn); return timers.length; } });
  const { [kind === 'video' ? 'VideoSourceController' : 'AudioSourceController']: Source } =
    load(`media/${kind}/${kind === 'video' ? 'Video' : 'Audio'}SourceController.ets`);
  const source = new Source(() => {}, error => errors.push(error), () => { ended++; });
  const timeline = { playbackAnchorForLoop: index => index * 1000000, mediaStartUs: 0,
    cycleDurationUs: 1000000, pause() {}, resume() {} };
  const configure = () => kind === 'video' ? source.configure('file', 0, 2, 2, 24, loop) : source.configure('file', loop);
  configure();
  await source.start(timeline);
  return { source, decoders, errors, timeline, configure, get ended() { return ended; },
    async flush() { while (timers.length) { timers.shift()(); await settle(); } }
  };
}

for (const kind of ['video', 'audio']) {
  test(`${kind} loops by default and does not report natural completion`, async () => {
    const f = await sourceFixture(kind);
    f.decoders[0].listener.onEndOfStream();
    await f.flush();
    assert.equal(f.decoders.length, 2);
    assert.equal(f.ended, 0);
    await f.source.stop();
  });
  test(`${kind} plays once with loop=false and emits completion once`, async () => {
    const f = await sourceFixture(kind, false), first = f.decoders[0];
    first.listener.onEndOfStream();
    first.listener.onEndOfStream();
    await f.flush();
    first.listener.onEndOfStream();
    await f.flush();
    assert.equal(f.decoders.length, 1);
    assert.equal(f.ended, 1);
    assert.equal(first.released, true);
    // One track may end before the other; pausing the remaining track is still valid.
    f.source.pause();
    f.source.resume(1000);
    await f.source.stop();
    assert.equal(f.ended, 1);
  });
  test(`${kind} defers completion while paused, including pause after EOS is queued`, async () => {
    const f = await sourceFixture(kind, false);
    f.decoders[0].listener.onEndOfStream();
    f.source.pause();
    await f.flush();
    assert.equal(f.ended, 0);
    f.source.resume(1000);
    await f.flush();
    assert.equal(f.ended, 1);
    await f.source.stop();
  });
  test(`${kind} stopping/replacing suppresses queued and stale completion`, async () => {
    const f = await sourceFixture(kind, false), old = f.decoders[0];
    old.listener.onEndOfStream();
    await f.source.stop();
    f.configure();
    await f.source.start(f.timeline);
    old.listener.onEndOfStream();
    old.listener.onError('late error');
    await f.flush();
    assert.equal(f.ended, 0);
    assert.deepEqual(f.errors, []);
    f.decoders[1].listener.onEndOfStream();
    await f.flush();
    assert.equal(f.ended, 1);
    await f.source.stop();
  });
}

async function mediaFixture(hasAudio = true) {
  let video, audio;
  let ended = 0;
  const gate = deferred(), errors = [];
  class Source {
    constructor(_frame, _error, end) { this.end = end; }
    configure(...args) { this.config = args; }
    start() {}
    pause() {}
    resume() {}
    stop() {}
  }
  const load = loadEts({
    '@kit.CoreFileKit': {}, '@kit.MediaKit': {},
    '@ohos.systemDateTime': { default: { TimeType: { ACTIVE: 0 }, getUptime: () => 0 } },
    VideoSourceController: { VideoSourceController: class extends Source { constructor(...args) { super(...args); video = this; } } },
    AudioSourceController: { AudioSourceController: class extends Source { constructor(...args) { super(...args); audio = this; } } },
    XmaxLogger: logger
  });
  const { MediaSourceController } = load('media/MediaSourceController.ets');
  const manager = { async start() {}, async stop() {}, async flush() {}, drain: () => gate.promise };
  const media = new MediaSourceController({}, manager, () => {}, () => {}, error => errors.push(error), () => { ended++; });
  media.metadata = { durationUs: 1000000, hasAudio };
  await media.start();
  return { media, video, audio, gate, errors, get ended() { return ended; } };
}

for (const first of ['video', 'audio']) {
  test(`completion waits for both tracks and drained audio when ${first} ends first`, async () => {
    const f = await mediaFixture();
    f[first].end();
    await settle();
    assert.equal(f.ended, 0);
    f[first === 'video' ? 'audio' : 'video'].end();
    await settle();
    assert.equal(f.ended, 0);
    f.gate.resolve();
    await settle();
    assert.equal(f.ended, 1);
    f.video.end(); f.audio.end();
    await settle();
    assert.equal(f.ended, 1);
    await f.media.stop();
  });
}

test('silent video completes without waiting for an audio track', async () => {
  const f = await mediaFixture(false);
  f.video.end();
  await settle();
  assert.equal(f.ended, 1);
  await f.media.stop();
});

test('media preparation forwards loop configuration to both sources', async () => {
  const f = await mediaFixture();
  await f.media.stop();
  f.media.readMetadata = async () => ({ width: 2, height: 2, durationUs: 1000000, rotation: 0, hasAudio: true });
  f.media.resolveVideoFormat = () => ({ width: 2, height: 2, fps: 24 });
  await f.media.prepare('once.mp4', undefined, false);
  assert.equal(f.video.config.at(-1), false);
  assert.equal(f.audio.config.at(-1), false);
  await f.media.stop();
  await f.media.prepare('loop.mp4');
  assert.equal(f.video.config.at(-1), true);
  assert.equal(f.audio.config.at(-1), true);
  await f.media.stop();
});

test('stop while draining suppresses completion from the previous file', async () => {
  const f = await mediaFixture();
  f.video.end(); f.audio.end();
  await f.media.stop();
  f.gate.resolve();
  await settle();
  assert.equal(f.ended, 0);
  assert.equal(f.media.hasEnded, false);
});

test('pause during audio drain defers completion until resumed', async () => {
  const f = await mediaFixture();
  f.video.end(); f.audio.end();
  await f.media.pause();
  f.gate.resolve();
  await settle();
  assert.equal(f.ended, 0);
  f.media.resume();
  await settle();
  assert.equal(f.ended, 1);
  await f.media.stop();
});

test('media waits for video initialization before starting audio, and exit cancels the pending start', async () => {
  const f = await mediaFixture();
  await f.media.stop();
  const gate = deferred();
  let audioStarts = 0;
  f.media.metadata = { durationUs: 1000000, hasAudio: true };
  f.video.start = () => gate.promise;
  f.audio.start = () => { audioStarts++; };
  const starting = f.media.start();
  const cancelled = assert.rejects(starting, error => error.code === 'CANCELLED');
  await settle();
  assert.equal(audioStarts, 0);
  await f.media.stop();
  gate.resolve(); await cancelled;
  assert.equal(audioStarts, 0);
  assert.equal(f.media.timeline, null);
});

test('media starts audio only after video initialization succeeds', async () => {
  const f = await mediaFixture();
  await f.media.stop();
  const gate = deferred();
  let audioStarts = 0, videoTimeline, audioTimeline;
  f.media.metadata = { durationUs: 1000000, hasAudio: true };
  f.video.start = timeline => { videoTimeline = timeline; return gate.promise; };
  f.audio.start = timeline => { audioStarts++; audioTimeline = timeline; };
  const starting = f.media.start();
  await settle(); assert.equal(audioStarts, 0);
  gate.resolve(); await starting;
  assert.equal(audioStarts, 1);
  assert.equal(audioTimeline, videoTimeline);
  await f.media.stop();
});
