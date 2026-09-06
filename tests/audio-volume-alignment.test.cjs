const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

const settle = async () => { for (let i = 0; i < 40; i++) await Promise.resolve(); };
function deferred() {
  let resolve;
  const promise = new Promise(yes => { resolve = yes; });
  return { promise, resolve };
}
const logger = { XmaxLogger: { info() {}, debug() {}, warn() {}, error() {} } };

function audioFixture() {
  const renderers = [], events = [];
  const audio = {
    AudioSamplingRate: { SAMPLE_RATE_48000: 48000 }, AudioChannel: { CHANNEL_1: 1 },
    AudioSampleFormat: { SAMPLE_FORMAT_S16LE: 1 }, AudioEncodingType: { ENCODING_TYPE_RAW: 1 },
    StreamUsage: { STREAM_USAGE_MOVIE: 1 }, AudioDataCallbackResult: { VALID: 0 },
    async createAudioRenderer() {
      const renderer = {
        volume: null, released: false,
        on(_event, callback) { this.writeData = callback; },
        async setVolume(value) {
          assert.equal(this.released, false);
          events.push(['volume', value]);
          if (this.gate) await this.gate.promise;
          if (this.failure) throw this.failure;
          this.volume = value;
        },
        async start() { events.push(['start', this.volume]); },
        async stop() { events.push(['stop']); },
        async release() { this.released = true; events.push(['release']); },
        async flush() {}
      };
      renderers.push(renderer);
      return renderer;
    }
  };
  const stubs = { '@kit.AudioKit': { audio }, XmaxLogger: logger };
  const load = loadEts(stubs);
  const { AudioManager } = load('foundation/media/audio/AudioManager.ets');
  return { audio: new AudioManager(), renderers, events, stubs };
}

test('local volume defaults to 45%, caches before playback and survives replacement', async () => {
  const f = audioFixture();
  await f.audio.start();
  assert.equal(f.renderers[0].volume, 0.45);
  await f.audio.stop();
  await f.audio.setVolume(0.27);
  await f.audio.start();
  assert.deepEqual(f.events.at(-1), ['start', 0.27]);
  await f.audio.stop();
  await f.audio.start();
  assert.equal(f.renderers[2].volume, 0.27);
  await f.audio.stop();
});

test('rapid volume updates and renderer replacement execute in order without stale writes', async () => {
  const f = audioFixture();
  await f.audio.start();
  const first = f.renderers[0], gate = deferred();
  first.gate = gate;
  const low = f.audio.setVolume(0.2);
  const high = f.audio.setVolume(0.8);
  const stopping = f.audio.stop();
  const restart = f.audio.start();
  const muted = f.audio.setVolume(0);
  await settle();
  assert.deepEqual(f.events, [['volume', 0.45], ['start', 0.45], ['volume', 0.2]]);
  gate.resolve();
  await Promise.all([low, high, stopping, restart, muted]);
  assert.equal(first.released, true);
  assert.deepEqual(f.events.slice(3), [
    ['volume', 0.8], ['stop'], ['release'], ['volume', 0.8], ['start', 0.8], ['volume', 0]
  ]);
  assert.equal(f.renderers[1].volume, 0);
  await f.audio.stop();
});

test('failed volume changes preserve the previous value and do not poison later operations', async () => {
  const f = audioFixture();
  await f.audio.start();
  await f.audio.setVolume(0.3);
  f.renderers[0].failure = new Error('renderer volume failed');
  await assert.rejects(f.audio.setVolume(0.7), { message: 'renderer volume failed' });
  await f.audio.stop();
  await f.audio.start();
  assert.equal(f.renderers[1].volume, 0.3);
  await f.audio.setVolume(0.9);
  assert.equal(f.renderers[1].volume, 0.9);
  await f.audio.stop();
});

test('adjusting volume does not override generation preview mute or modify PCM frames', async () => {
  const f = audioFixture();
  await f.audio.start();
  const frame = { data: new Uint8Array([1, 2, 3, 4]) }, output = new Uint8Array(4);
  f.audio.setPlaybackEnabled(false);
  await f.audio.setVolume(0.8);
  f.audio.write(frame);
  f.renderers[0].writeData(output.buffer);
  assert.deepEqual([...output], [0, 0, 0, 0]);
  f.audio.setPlaybackEnabled(true);
  f.audio.write(frame);
  f.renderers[0].writeData(output.buffer);
  assert.deepEqual([...output], [1, 2, 3, 4]);
  assert.deepEqual([...frame.data], [1, 2, 3, 4]);
  assert.equal(f.renderers[0].volume, 0.8);
  await f.audio.stop();
});

test('local volume propagates through media controllers even before a video source exists', async () => {
  const f = audioFixture(), uploaded = [];
  let source;
  const load = loadEts({ ...f.stubs,
    '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
    '@kit.ArkTS': { util: {} }, '@kit.CoreFileKit': {}, '@kit.MediaKit': {},
    '@ohos.systemDateTime': {},
    CameraController: { CameraController: class {} }, ImageController: { ImageController: class {} },
    InteractionController: { InteractionController: class {} },
    PermissionManager: { PermissionManager: class {} }, MediaService: { MediaService: class {} },
    VideoSourceController: { VideoSourceController: class {} },
    AudioSourceController: { AudioSourceController: class {
      constructor(onFrame) { source = onFrame; }
    } }
  });
  const { MediaController } = load('media/MediaController.ets');
  const media = new MediaController({}, {}, { pushLocalAudioFrame: frame => uploaded.push(frame) }, () => {});
  assert.equal(media.currentTrack, null);
  await media.setLocalAudioVolume(0.12);
  const audio = media.videoController.audioManager;
  await audio.start();
  assert.equal(f.renderers[0].volume, 0.12);
  media.videoController.acceptsFrames = true;
  const frame = { data: new Uint8Array([12, 34]) };
  source(frame);
  assert.equal(uploaded[0], frame);
  await audio.stop();
});

function streamFixture() {
  const events = [], errors = [];
  const load = loadEts({
    '@ohos.systemDateTime': { default: { TimeType: { ACTIVE: 0 }, getUptime: () => 0 } },
    '@kit.ArkTS': { util: { TextEncoder: class {
      encodeInto(text) { return new Uint8Array(Buffer.from(text)); }
    } } },
    XmaxLogger: logger,
    RoomController: { RoomController: class {
      async join() {} async leave() {} startGeneration() {} stopGeneration() {}
    } },
    QualityController: { QualityController: class {} },
    EncodingController: { EncodingController: class {} }
  });
  const { StreamController } = load('stream/StreamController.ets');
  const { RemoteStream } = load('foundation/rtc/RemoteStream.ets');
  const rtc = {
    setEventListener() {}, publishLocalVideo() {}, unpublishLocalVideo() {}, unpublishLocalAudio() {},
    subscribeRemoteVideo() {},
    setRemoteAudioVolume(user, volume) {
      if (this.failure) throw this.failure;
      events.push(['volume', user, volume]);
    },
    subscribeRemoteAudio(user, enabled) { events.push(['subscribe', user, enabled]); }
  };
  const stream = new StreamController(rtc, () => {}, error => errors.push(error));
  let task = 0;
  return { stream, rtc, events, errors,
    async connect() { await stream.connect({ roomId: 'room', botName: 'bot' }, false, () => {}); },
    async activate() {
      const id = `task-${++task}`;
      const starting = stream.beginGeneration(id, {}, {});
      stream.onSeiMessageReceived(new RemoteStream('room', 'bot'), id);
      await starting;
      stream.activateRemoteAudio();
    }
  };
}

test('remote volume is cached before subscribing, rounded and retained after stop and reconnect', async () => {
  const f = streamFixture();
  f.stream.setRemoteAudioVolume(0.356);
  assert.deepEqual(f.events, []);
  await f.connect();
  await f.activate();
  assert.deepEqual(f.events, [['volume', 'bot', 36], ['subscribe', 'bot', true]]);
  f.stream.setRemoteAudioVolume(0);
  assert.deepEqual(f.events.at(-1), ['volume', 'bot', 0]);
  f.stream.stopGeneration('');
  await f.activate();
  assert.deepEqual(f.events.slice(-2), [['volume', 'bot', 0], ['subscribe', 'bot', true]]);
  await f.stream.disconnect();
  await f.connect();
  await f.activate();
  assert.deepEqual(f.events.slice(-2), [['volume', 'bot', 0], ['subscribe', 'bot', true]]);
  assert.deepEqual(f.errors, []);
  await f.stream.disconnect();
});

test('failed remote adjustment keeps the last successful volume for the next subscription', async () => {
  const f = streamFixture();
  await f.connect();
  await f.activate();
  assert.deepEqual(f.events[0], ['volume', 'bot', 100]);
  f.stream.setRemoteAudioVolume(0.4);
  f.rtc.failure = new Error('RTC volume failed');
  assert.throws(() => f.stream.setRemoteAudioVolume(0.8), { message: 'RTC volume failed' });
  f.rtc.failure = null;
  f.stream.onRemoteAudioPublished('bot', false);
  f.stream.onRemoteAudioPublished('bot', true);
  assert.deepEqual(f.events.slice(-2), [['volume', 'bot', 40], ['subscribe', 'bot', true]]);
  await f.stream.disconnect();
});
