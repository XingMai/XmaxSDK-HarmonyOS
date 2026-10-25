const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

function fixture() {
  const timers = new Map(), logs = [];
  let timerId = 0, identity = 0;
  const load = loadEts({
    '@kit.ArkTS': { util: { generateRandomUUID: () => `binding-${++identity}` } },
    '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
    '@bytertc/volcenginertc': {
      AudioFrameType: { kFrameTypePCM16: 0 }, AudioFrameCallbackMethod: { kRemoteUser: 3 },
      AudioSampleRate: { kAudioSampleRateAuto: -1 }, AudioChannel: { kAudioChannelAuto: 0 },
      MirrorType: { kMirrorTypeNone: 0 }, RenderMode: { kRenderModeHidden: 1 }, StreamIndex: { kStreamIndexMain: 0 },
      VideoPixelFormat: { kVideoPixelFormatI420: 1 },
      RemoteVideoSinkPosition: { kRemoteVideoSinkPositionAfterPostProcess: 1 },
      VideoApplyRotation: { kVideoApplyRotationDefault: -1 },
      VideoSinkMirrorType: { kVideoSinkMirrorTypeOFF: 2 }
    },
    XmaxLogger: { XmaxLogger: { error: value => logs.push(value), debug() {} } }
  }, {
    setTimeout(fn) { timers.set(++timerId, fn); return timerId; },
    clearTimeout(id) { timers.delete(id); }
  });
  const { RealtimeMediaFrameDispatcher: Dispatcher } = load('rendering/video/RealtimeMediaFrameDispatcher.ets');
  const { RtcAudioConverter: Converter } = load('foundation/rtc/RtcAudioConverter.ets');
  const { RealtimeAudioFrame: Audio } = load('service/realtime/RealtimeMediaFrame.ets');
  const { RealtimeVideoFrame: Video } = load('foundation/media/video/RealtimeVideoFrame.ets');
  const { VideoFramePlane: Plane } = load('foundation/media/video/VideoFramePlane.ets');
  function video(timestampUs = 1000000, rotation = 0, width = 2) {
    return new Video(width, 2, 'i420', [new Plane(new ArrayBuffer(6), 2)], timestampUs, rotation);
  }
  function audio(timestampUs = 1000000, sampleRate = 48000, channels = 1, samples = 480) {
    return Converter.copyRemoteFrame({ timestamp_us: timestampUs, sample_rate: sampleRate,
      channel: channels, data_size: samples * channels * 2,
      data: new Uint8Array(samples * channels * 2), frame_type: 0 });
  }
  return { load, timers, logs, Dispatcher, Converter, Audio, Video, video, audio,
    turn() {
      const entries = [...timers];
      for (const [id, callback] of entries) { timers.delete(id); callback(); }
    },
    flush() { for (let turn = 0; timers.size && turn < 100; turn++) this.turn(); assert.equal(timers.size, 0); }
  };
}

test('PCM copying honors typed-array offset and declared length and owns bytes after the callback', () => {
  const f = fixture(), storage = new Uint8Array([99, 1, 2, 3, 4, 88]);
  const raw = { timestamp_us: 123456, sample_rate: 44100, channel: 2,
    data_size: 4, data: storage.subarray(1), frame_type: 0 };
  const copied = f.Converter.copyRemoteFrame(raw);
  assert.deepEqual([...copied.data], [1, 2, 3, 4]);
  storage.fill(0);
  assert.deepEqual([...copied.data], [1, 2, 3, 4]);
  assert.equal(copied.samplesPerChannel, 1);
  assert.equal(copied.timestampUs, 123456);
  assert.equal(copied.sampleRate, 44100);
  assert.equal(copied.channels, 2);
});

test('PCM copying accepts the native ArrayBuffer representation without including trailing bytes', () => {
  const f = fixture(), storage = new Uint8Array([1, 2, 3, 4, 99, 98]);
  const copied = f.Converter.copyRemoteFrame({ timestamp_us: 123456, sample_rate: 48000, channel: 1,
    data_size: 4, data: storage.buffer, frame_type: 0 });
  assert.deepEqual([...copied.data], [1, 2, 3, 4]);
  assert.equal(copied.samplesPerChannel, 2);
  assert.equal(copied.timestampUs, 123456);
  storage.fill(0);
  assert.deepEqual([...copied.data], [1, 2, 3, 4]);
});

test('PCM copying rejects invalid time, format, sample rate, channels and byte bounds', () => {
  const f = fixture();
  const raw = { timestamp_us: 1, sample_rate: 48000, channel: 1,
    data_size: 960, data: new Uint8Array(960), frame_type: 0 };
  for (const patch of [{ timestamp_us: -1 }, { timestamp_us: NaN }, { timestamp_us: 0.5 },
    { sample_rate: 0 }, { sample_rate: 192001 }, { sample_rate: 44099.5 },
    { channel: 0 }, { channel: 3 }, { data_size: 0 }, { data_size: -2 },
    { data_size: 961 }, { data_size: 962 }, { data_size: 3 }, { data_size: 1.5 },
    { data: undefined }, { data: new Int16Array(480) }, { data: new DataView(new ArrayBuffer(960)) },
    { data: new Uint8ClampedArray(960) }, { data: new ArrayBuffer(959) }, { frame_type: 1 }]) {
    assert.throws(() => f.Converter.copyRemoteFrame({ ...raw, ...patch }), { code: 'RTC_ERROR' });
  }
  assert.equal(f.audio(0).timestampUs, 0);
});

test('unified output preserves track offsets and delivery order instead of pairing or sorting tracks', () => {
  const f = fixture(), dispatcher = new f.Dispatcher(), output = [];
  dispatcher.setListener(frame => output.push(frame));
  dispatcher.setStream(true);
  const id = dispatcher.streamId;
  dispatcher.dispatchAudio(f.audio(1000000), id);
  dispatcher.dispatchVideo(f.video(950000), id);
  dispatcher.dispatchAudio(f.audio(1000000), id);
  assert.deepEqual(output, []);
  f.flush();
  assert.deepEqual(output.map(frame => frame.timestampUs), [1000000, 950000, 1010000]);
  assert.deepEqual(output.map(frame => frame.durationUs), [10000, undefined, 10000]);
  assert.deepEqual(output.map(frame => frame.isDiscontinuous), [true, true, false]);
  assert.ok(output.every(frame => frame.streamId === id));
  assert.ok(output[0].content instanceof f.Audio);
  assert.ok(output[1].content instanceof f.Video);
});

test('audio timing uses accumulated sample counts at 44.1 kHz and marks native clock and format changes', () => {
  const f = fixture(), dispatcher = new f.Dispatcher(), output = [];
  dispatcher.setListener(frame => output.push(frame)); dispatcher.setStream(true);
  const id = dispatcher.streamId, anchor = 500000;
  for (let i = 0; i < 1000; i++) {
    dispatcher.dispatchAudio(f.audio(Math.round(anchor + i * 1024 * 1000000 / 44100), 44100, 2, 1024), id);
    f.flush();
  }
  assert.equal(output.at(-1).timestampUs, anchor + 999 * 1024 * 1000000 / 44100);
  assert.equal(output.slice(1).some(frame => frame.isDiscontinuous), false);
  dispatcher.dispatchAudio(f.audio(30000000, 44100, 2, 1024), id);
  dispatcher.dispatchAudio(f.audio(30010000, 48000, 1, 480), id);
  f.flush();
  assert.deepEqual(output.slice(-2).map(frame => frame.isDiscontinuous), [true, true]);
  assert.equal(output.at(-1).timestampUs, 30010000);
});

test('video format changes, repeated or reversed timestamps and invalid timestamps are discontinuous', () => {
  const f = fixture(), dispatcher = new f.Dispatcher(), output = [];
  dispatcher.setListener(frame => output.push(frame)); dispatcher.setStream(true);
  const id = dispatcher.streamId;
  for (const frame of [f.video(10), f.video(20), f.video(20), f.video(19),
    f.video(30, 90), f.video(40, 90, 4), f.video(NaN), f.video(50, 90, 4)]) {
    dispatcher.dispatchVideo(frame, id);
  }
  f.flush();
  assert.deepEqual(output.map(frame => frame.isDiscontinuous), [true, false, true, true, true, true, true]);
});

test('packet and byte bounds discard new output without compressing the audio timeline', () => {
  for (const [frames, bytes] of [[2, 99999], [256, 1920]]) {
    const f = fixture(), dispatcher = new f.Dispatcher(frames, bytes), output = [];
    dispatcher.setListener(frame => output.push(frame)); dispatcher.setStream(true);
    const id = dispatcher.streamId;
    for (let index = 0; index < 5; index++) dispatcher.dispatchAudio(f.audio(1000000 + index * 10000), id);
    assert.equal(dispatcher.pendingCount, 2);
    assert.equal(dispatcher.pendingBytes, 1920);
    f.flush();
    dispatcher.dispatchAudio(f.audio(1050000), id); f.flush();
    assert.deepEqual(output.map(frame => frame.timestampUs), [1000000, 1010000, 1050000]);
    assert.deepEqual(output.map(frame => frame.isDiscontinuous), [true, false, true]);
    assert.equal(dispatcher.pendingCount, 0);
    assert.equal(dispatcher.pendingBytes, 0);
  }
});

test('oversized video drops mark the next video event without affecting continuous audio', () => {
  const f = fixture(), dispatcher = new f.Dispatcher(256, 1000), output = [];
  dispatcher.setListener(frame => output.push(frame)); dispatcher.setStream(true);
  const id = dispatcher.streamId;
  dispatcher.dispatchVideo(f.video(1), id); f.flush();
  const tooLarge = f.video(2); tooLarge.planes[0] = { data: new ArrayBuffer(1001) };
  dispatcher.dispatchVideo(tooLarge, id);
  dispatcher.dispatchAudio(f.audio(1000), id); f.flush();
  dispatcher.dispatchVideo(f.video(3), id);
  dispatcher.dispatchAudio(f.audio(11000), id); f.flush();
  assert.deepEqual(output.map(frame => frame.isDiscontinuous), [true, true, true, false]);
});

for (const action of ['remove listener', 'replace listener', 'replace stream', 'clear stream']) {
  test(`${action} inside a callback clears old packets, stale timers and pending accounting`, () => {
    const f = fixture(), dispatcher = new f.Dispatcher(), output = [];
    const replacement = frame => output.push(`new:${frame.timestampUs}`);
    dispatcher.setStream(true);
    const oldId = dispatcher.streamId;
    dispatcher.setListener(frame => {
      output.push(frame.timestampUs);
      dispatcher.dispatchVideo(f.video(3), oldId);
      if (action === 'remove listener') dispatcher.setListener(null);
      if (action === 'replace listener') dispatcher.setListener(replacement);
      if (action === 'replace stream') dispatcher.setStream(true);
      if (action === 'clear stream') dispatcher.setStream(false);
    });
    dispatcher.dispatchVideo(f.video(1), oldId);
    dispatcher.dispatchVideo(f.video(2), oldId);
    const staleTimer = [...f.timers.values()][0];
    f.turn(); staleTimer();
    assert.deepEqual(output, [1]);
    assert.equal(dispatcher.pendingCount, 0); assert.equal(dispatcher.pendingBytes, 0);
    if (action.includes('stream')) {
      dispatcher.dispatchAudio(f.audio(), oldId);
      assert.equal(dispatcher.pendingCount, 0);
    }
    if (action === 'replace listener') {
      dispatcher.dispatchVideo(f.video(4), oldId); f.flush();
      assert.deepEqual(output, [1, 'new:4']);
    }
  });
}

test('delivery yields after 16 packets, contains listener exceptions and counts the running callback', () => {
  const f = fixture(), dispatcher = new f.Dispatcher(20, 999999), output = [];
  dispatcher.setStream(true);
  const id = dispatcher.streamId;
  dispatcher.setListener(frame => {
    output.push(frame.timestampUs);
    if (output.length === 1) {
      assert.equal(dispatcher.pendingCount, 20);
      dispatcher.dispatchAudio(f.audio(), id);
      assert.equal(dispatcher.pendingCount, 20);
      throw new Error('consumer failure');
    }
  });
  for (let i = 0; i < 20; i++) dispatcher.dispatchVideo(f.video(i), id);
  f.turn(); assert.equal(output.length, 16);
  f.flush(); assert.equal(output.length, 20);
  assert.match(f.logs[0], /consumer failure/);
  assert.equal(dispatcher.pendingBytes, 0);
});

async function rtcFixture() {
  const f = fixture(), handlers = new Map(), roomHandlers = new Map(), calls = [];
  let failure = '', released = 0, nativeObserver = null;
  const engine = {
    getNativeHandle() { return this; },
    on(name, callback) { handlers.set(name, callback); }, off(name) { handlers.delete(name); },
    registerAudioFrameObserver(enabled) {
      calls.push(['register', enabled]);
      return failure === 'register' || (!enabled && failure === 'unregister') ? -1 : 0;
    },
    enableAudioFrameCallback(method, format) { calls.push(['enable', method, format]); return failure === 'enable' ? -2 : 0; },
    disableAudioFrameCallback(method) { calls.push(['disable', method]); return failure === 'disable' ? -3 : 0; },
    setRemoteVideoCanvas() { return 0; },
    setRemoteVideoSinkWithConfig(_key, _config, enabled) { calls.push(['video', enabled]); return 0; }
  };
  // This fixture uses the same classes as the converter and output dispatcher.
  const load = loadEts({
    'libxmax_video.so': { default: {
      createRtcRemoteAudioObserver(handle, callback) {
        assert.equal(handle, engine);
        if (engine.registerAudioFrameObserver(true) !== 0) throw new Error('Native registration failed');
        const observer = nativeObserver = {
          enabled: false,
          setEnabled(value) { this.enabled = value; },
          close() {
            this.enabled = false;
            handlers.delete('onRemoteUserAudioFrame');
            if (engine.registerAudioFrameObserver(false) !== 0) throw new Error('Native detach failed');
          }
        };
        handlers.set('onRemoteUserAudioFrame', (key, frame) => {
          if (!observer.enabled) return;
          const data = frame.data instanceof Uint8Array ?
            frame.data.buffer.slice(frame.data.byteOffset, frame.data.byteOffset + frame.data.byteLength) : frame.data;
          callback(key.room_id, key.user_id, key.stream_index, data, frame.sample_rate,
            frame.channel, frame.timestamp_us, frame.is_discontinuous ?? false);
        });
        return observer;
      }
    } },
    '@kit.ArkTS': { util: { generateRandomUUID: () => require('node:crypto').randomUUID() } },
    '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
    '@bytertc/volcenginertc': {
      AudioFrameType: { kFrameTypePCM16: 0 }, AudioFrameCallbackMethod: { kRemoteUser: 3 },
      AudioSampleRate: { kAudioSampleRateAuto: -1 }, AudioChannel: { kAudioChannelAuto: 0 },
      MirrorType: { kMirrorTypeNone: 0 }, RenderMode: { kRenderModeHidden: 1 }, StreamIndex: { kStreamIndexMain: 0 },
      VideoPixelFormat: { kVideoPixelFormatI420: 1 },
      RemoteVideoSinkPosition: { kRemoteVideoSinkPositionAfterPostProcess: 1 },
      VideoApplyRotation: { kVideoApplyRotationDefault: -1 },
      VideoSinkMirrorType: { kVideoSinkMirrorTypeOFF: 2 }
    },
    RtcEngineManager: { RtcEngineManager: {
      async acquire() { return { engine }; },
      async release() { calls.push(['release', rtc.remoteAudioObserver]); released++; }
    } },
    XmaxLogger: { XmaxLogger: { error: value => f.logs.push(value), debug() {} } }
  }, {
    setTimeout(fn) { const id = Symbol(); f.timers.set(id, fn); return id; },
    clearTimeout(id) { f.timers.delete(id); }
  });
  const { RtcManager } = load('foundation/rtc/RtcManager.ets');
  const { RenderController } = load('rendering/RenderController.ets');
  const { RemoteStream } = load('foundation/rtc/RemoteStream.ets');
  const rtc = new RtcManager({}); await rtc.initialize();
  const room = {
    on(name, callback) { roomHandlers.set(name, callback); },
    subscribeStreamAudio(user, enabled) { calls.push(['subscribe', user, enabled]); return 0; },
    publishStreamVideo() {}, publishStreamAudio() {}, leaveRoom() {}, async destroy() {}
  };
  rtc.room = room; rtc.activeRoomId = 'room'; rtc.bindRoomEvents(room);
  const stream = new RemoteStream('room', 'bot'), key = { room_id: 'room', user_id: 'bot', stream_index: 0 };
  rtc.remoteStreamKeys.set(stream.key(), key);
  const render = new RenderController(rtc);
  return { ...f, load, rtc, render, stream, key, engine, handlers, roomHandlers, calls,
    failure(value) { failure = value; }, get released() { return released; },
    get nativeObserver() { return nativeObserver; },
    audio(patch = {}, streamKey = key) { handlers.get('onRemoteUserAudioFrame')?.(streamKey, {
      timestamp_us: 1000000, sample_rate: 48000, channel: 1,
      frame_type: 0, data_size: 960, data: new Uint8Array(960), ...patch }); },
    video() { handlers.get('onRemoteVideoFrame')(key, 1, {
      width: 2, height: 2, rotation: 0, timestamp_us: 990000, pixel_format: 1,
      number_of_planes: 3, plane_stride: [2, 1, 1], plane_data: [
        new Uint8Array(4).buffer, new Uint8Array(1).buffer, new Uint8Array(1).buffer
      ] }); }
  };
}

test('RTC-to-render unified output observes only the bound subscribed user and preserves playback settings', async () => {
  const f = await rtcFixture(), output = [];
  f.render.setRemoteMediaFrameListener(frame => output.push(frame));
  f.render.setRemoteStream(f.stream);
  assert.equal(f.calls.some(call => call[0] === 'subscribe'), false);
  f.audio(); f.flush(); assert.deepEqual(output, []);
  f.rtc.subscribeRemoteAudio('bot', true);
  f.audio({}, { ...f.key, user_id: 'other' });
  f.audio({}, { ...f.key, room_id: 'old' });
  f.audio({}, { ...f.key, stream_index: 1 });
  f.audio(); f.video(); f.flush();
  assert.equal(output.length, 2);
  assert.deepEqual(output.map(frame => frame.timestampUs), [1000000, 990000]);
  assert.equal(output[0].streamId, output[1].streamId);
  assert.deepEqual(f.calls.find(call => call[0] === 'enable'), ['enable', 3,
    { sample_rate: -1, channel: 0, samples_per_call: 0 }]);
  f.rtc.subscribeRemoteAudio('bot', false);
  f.audio(); f.flush(); assert.equal(output.length, 2);
  f.render.setRemoteMediaFrameListener(null);
  assert.deepEqual(f.calls.filter(call => call[0] !== 'video').at(-1), ['disable', 3]);
  assert.equal(f.nativeObserver.enabled, false);
  f.render.resetRemoteTrack(null); await f.rtc.destroy();
  assert.equal(f.released, 1);
  assert.equal(f.handlers.has('onRemoteUserAudioFrame'), false);
});

test('native ArrayBuffer PCM reaches unified media output with owned bytes and unchanged timing', async () => {
  const f = await rtcFixture(), output = [], samples = new Uint8Array(960).fill(17);
  f.render.setRemoteMediaFrameListener(frame => output.push(frame));
  f.render.setRemoteStream(f.stream); f.rtc.subscribeRemoteAudio('bot', true);
  f.audio({ data: samples.buffer });
  samples.fill(0);
  f.video(); f.flush();
  assert.equal(output.length, 2);
  assert.equal(output[0].content.data.byteLength, 960);
  assert.ok(output[0].content.data.every(value => value === 17));
  assert.equal(output[0].content.sampleRate, 48000);
  assert.equal(output[0].content.channels, 1);
  assert.equal(output[0].content.samplesPerChannel, 480);
  assert.deepEqual(output.map(frame => frame.timestampUs), [1000000, 990000]);
  assert.deepEqual(f.logs, []);
  f.render.resetRemoteTrack(null); await f.rtc.destroy();
});

test('native audio queue loss reanchors sample time and is visible even for gaps below 100 ms', async () => {
  const f = await rtcFixture(), output = [];
  f.render.setRemoteMediaFrameListener(frame => output.push(frame));
  f.render.setRemoteStream(f.stream); f.rtc.subscribeRemoteAudio('bot', true);
  f.audio(); f.flush();
  f.audio({ timestamp_us: 1030000, is_discontinuous: true }); f.flush();
  f.audio({ timestamp_us: 1040000 }); f.flush();
  assert.deepEqual(output.map(frame => frame.timestampUs), [1000000, 1030000, 1040000]);
  assert.deepEqual(output.map(frame => frame.isDiscontinuous), [true, true, false]);
  f.render.resetRemoteTrack(null); await f.rtc.destroy();
});

test('recording restarts reuse one engine observer but replace its media binding and sample timeline', async () => {
  const f = await rtcFixture(), first = [], second = [];
  f.render.setRemoteMediaFrameListener(frame => first.push(frame));
  f.render.setRemoteStream(f.stream); f.rtc.subscribeRemoteAudio('bot', true);
  f.audio(); f.flush();
  const observer = f.nativeObserver;
  f.render.setRemoteMediaFrameListener(null);
  assert.equal(observer.enabled, false);
  f.render.setRemoteMediaFrameListener(frame => second.push(frame));
  f.audio({ timestamp_us: 2000000 }); f.flush();
  assert.equal(f.nativeObserver, observer);
  assert.equal(f.calls.filter(call => call[0] === 'register' && call[1]).length, 1);
  assert.equal(second.length, 1);
  assert.equal(second[0].timestampUs, 2000000);
  assert.equal(second[0].isDiscontinuous, true);
  f.render.resetRemoteTrack(null); await f.rtc.destroy();
  assert.equal(f.calls.filter(call => call[0] === 'register' && !call[1]).length, 1);
});

test('malformed PCM does not terminate playback and valid audio and video continue through one listener', async () => {
  const f = await rtcFixture(), unified = [];
  f.render.setRemoteMediaFrameListener(frame => unified.push(frame));
  f.render.setRemoteStream(f.stream); f.rtc.subscribeRemoteAudio('bot', true);
  f.audio({ timestamp_us: NaN }); f.video(); f.flush();
  assert.equal(unified.length, 1);
  assert.match(f.logs.at(-1), /Invalid remote PCM16/);
  f.audio(); f.flush(); assert.equal(unified.length, 2);
  f.render.setRemoteMediaFrameListener(null);
  f.audio(); f.video(); f.flush(); assert.equal(unified.length, 2);
  f.render.resetRemoteTrack(null); await f.rtc.destroy();
});

test('observer registration failures preserve existing delivery and rollback native PCM observation', async () => {
  const f = await rtcFixture(), output = [];
  f.render.setRemoteStream(f.stream); f.video();
  f.failure('enable');
  assert.throws(() => f.render.setRemoteMediaFrameListener(frame => output.push(frame)), { code: 'RTC_ERROR' });
  assert.equal(f.render.mediaFrameDispatcher.hasListener, false);
  assert.equal(f.rtc.observedRemoteAudioStreams.size, 0);
  assert.equal(f.nativeObserver.enabled, false);
  f.failure('');
  f.render.setRemoteMediaFrameListener(frame => output.push(frame));
  f.rtc.subscribeRemoteAudio('bot', true); f.audio(); f.flush();
  assert.equal(output.length, 1);
  f.render.resetRemoteTrack(null); await f.rtc.destroy();
});

test('disconnect and same-user rebind discard queued media and assign a fresh binding identity', async () => {
  const f = await rtcFixture(), output = [];
  f.render.setRemoteMediaFrameListener(frame => output.push(frame));
  f.render.setRemoteStream(f.stream); f.rtc.subscribeRemoteAudio('bot', true);
  f.audio(); f.video(); f.flush(); const oldId = output[0].streamId;
  f.audio(); f.video();
  f.render.stopRemoteFrameDelivery(); f.flush();
  assert.equal(output.length, 2);
  f.audio(); f.video(); f.flush(); assert.equal(output.length, 2);
  f.render.setRemoteStream(f.stream);
  f.audio(); f.video(); f.flush();
  assert.equal(output.length, 4);
  assert.notEqual(output[2].streamId, oldId);
  assert.ok(output.slice(2).every(frame => frame.isDiscontinuous));
  const oldCallback = f.handlers.get('onRemoteUserAudioFrame');
  f.render.resetRemoteTrack(null); await f.rtc.destroy();
  oldCallback(f.key, {}); f.flush(); assert.equal(output.length, 4);
});

test('PCM disable failure still unregisters the native observer and cannot prevent engine destruction', async () => {
  const f = await rtcFixture();
  f.render.setRemoteMediaFrameListener(() => {}); f.render.setRemoteStream(f.stream);
  f.failure('disable');
  f.render.resetRemoteTrack(null);
  assert.equal(f.nativeObserver.enabled, false);
  await f.rtc.destroy();
  assert.equal(f.released, 1);
  assert.ok(f.logs.some(message => /cleanup failed/.test(message)));
});

test('native detach failure retains the disabled observer until engine destruction completes', async () => {
  const f = await rtcFixture();
  f.render.setRemoteMediaFrameListener(() => {}); f.render.setRemoteStream(f.stream);
  const observer = f.nativeObserver;
  f.failure('unregister');
  f.render.resetRemoteTrack(null);
  await f.rtc.destroy();
  assert.equal(observer.enabled, false);
  assert.equal(f.calls.find(call => call[0] === 'release')[1], observer);
  assert.equal(f.rtc.remoteAudioObserver, null);
  assert.equal(f.released, 1);
  assert.ok(f.logs.some(message => /detach failed/.test(message)));
});

test('audio unpublication filters late PCM until a successful resubscription', async () => {
  const f = await rtcFixture(), output = [];
  f.render.setRemoteMediaFrameListener(frame => output.push(frame));
  f.render.setRemoteStream(f.stream); f.rtc.subscribeRemoteAudio('bot', true);
  f.audio(); f.flush();
  f.roomHandlers.get('onUserPublishStreamAudio')('room', 'bot', false);
  f.audio(); f.flush(); assert.equal(output.length, 1);
  f.roomHandlers.get('onUserPublishStreamAudio')('room', 'bot', true);
  f.audio(); f.flush(); assert.equal(output.length, 1);
  f.rtc.subscribeRemoteAudio('bot', true);
  f.audio(); f.flush(); assert.equal(output.length, 2);
  f.render.resetRemoteTrack(null); await f.rtc.destroy();
});

test('multiple watched users share one native observer and disable it after the last removal', async () => {
  const f = await rtcFixture();
  const { RemoteStream } = f.load('foundation/rtc/RemoteStream.ets');
  const other = new RemoteStream('room', 'other');
  f.rtc.observeRemoteAudioFrames(f.stream, true);
  f.rtc.observeRemoteAudioFrames(f.stream, true);
  f.rtc.observeRemoteAudioFrames(other, true);
  assert.equal(f.calls.filter(call => call[0] === 'register').length, 1);
  f.rtc.observeRemoteAudioFrames(f.stream, false);
  assert.equal(f.calls.some(call => call[0] === 'disable'), false);
  f.rtc.observeRemoteAudioFrames(other, false);
  assert.deepEqual(f.calls.at(-1), ['disable', 3]);
  assert.equal(f.nativeObserver.enabled, false);
  assert.throws(() => f.rtc.observeRemoteAudioFrames(new RemoteStream('old', 'bot'), true), { code: 'RTC_ERROR' });
  await f.rtc.destroy();
  assert.deepEqual(f.calls.at(-2), ['register', false]);
  assert.equal(f.calls.at(-1)[0], 'release');
});

test('native observer registration failure can be retried without replacing the application receiver', async () => {
  const f = await rtcFixture(), output = [];
  f.render.setRemoteStream(f.stream);
  f.failure('register');
  assert.throws(() => f.render.setRemoteMediaFrameListener(frame => output.push(frame)), { code: 'RTC_ERROR' });
  assert.equal(f.render.mediaFrameDispatcher.hasListener, false);
  assert.equal(f.rtc.remoteAudioObserver, null);
  f.failure('');
  f.render.setRemoteMediaFrameListener(frame => output.push(frame));
  f.rtc.subscribeRemoteAudio('bot', true); f.audio(); f.flush();
  assert.equal(output.length, 1);
  f.render.resetRemoteTrack(null); await f.rtc.destroy();
});
