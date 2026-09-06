const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { loadEts } = require('./ets-loader.cjs');

const settle = async () => { for (let i = 0; i < 40; i++) await Promise.resolve(); };
const outcome = promise => promise.then(value => ({ value }), error => ({ error }));

function fixture(t, timingOptions = {}) {
  const timers = new Map(), events = [], messages = [], observations = [], errors = [], timingLogs = [];
  let now = 0;
  let timerId = 0, rtc, media;
  let Track, Format, MediaStream;
  class FakeRtc {
    constructor() { rtc = this; }
    setEventListener(listener) { this.listener = listener; }
    setRemoteVideoFrameListener(listener) { this.frameListener = listener; }
    setRemoteVideoRenderedListener(listener) { this.renderedListener = listener; }
    observeRemoteVideoFrames(stream, enabled) { observations.push({ key: stream.key(), enabled }); }
    hasRenderedRemoteVideo() { return false; }
    renderLibraryName() { return 'rtc'; }
    bindRemoteVideo() { events.push('bind-surface'); }
    unbindRemoteVideo() {}
    async joinRoom() {
      now += timingOptions.roomMs ?? 0;
      if (timingOptions.roomError) throw timingOptions.roomError;
    }
    async leaveRoom() {}
    publishLocalVideo() {}
    unpublishLocalVideo() {}
    unpublishLocalAudio() {}
    setRemoteAudioVolume() { events.push('audio-volume'); }
    subscribeRemoteAudio(user, enabled) { events.push(`audio:${user}:${enabled}`); }
    subscribeRemoteVideo() {}
    sendRoomMessage(text) {
      const event = JSON.parse(text);
      messages.push(event);
      if (event.event === 'start') now += timingOptions.signalMs ?? 0;
    }
  }
  class FakeMedia {
    constructor() { media = this; this.hasAudio = false; }
    get currentVideoFormat() { return this.track?.videoFormat; }
    async createLocalCameraStream(format, position) {
      this.track = new Track('local', format, position);
      return new MediaStream('local', this.track);
    }
    owns(local) { return local.videoTrack === this.track; }
    start(id) { this.task = id; }
    stop() { this.task = null; }
    setLocalAudioPreviewEnabled(enabled) { this.previewAudio = enabled; }
    prepareForClose() {}
    async stopLocalStream() { this.track = null; }
  }
  const load = loadEts({
    '@ohos.systemDateTime': { default: { TimeType: { ACTIVE: 0 }, getUptime: () => now * 1000000 } },
    '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
    '@kit.BasicServicesKit': { deviceInfo: { distributionOSVersion: '5.1.0', productModel: 'Test' } },
    '@kit.ArkTS': { util: {
      generateRandomUUID: () => randomUUID(),
      Base64Helper: class { encodeToStringSync(bytes) { return Buffer.from(bytes).toString('base64'); } },
      TextEncoder: class { encodeInto(text) { return new Uint8Array(Buffer.from(text)); } }
    } },
    XmaxLogger: { XmaxLogger: { debug() {}, info(message, category, option) {
      if (category === 'Timing') timingLogs.push({ message: typeof message === 'function' ? message() : message, option });
    }, warn() {}, error() {} } },
    RtcManager: { RtcManager: FakeRtc }, MediaController: { MediaController: FakeMedia },
    EncodingController: { EncodingController: class {} },
    QualityController: { QualityController: class {} },
    RoomHeartbeat: { RoomHeartbeat: class { start() {} stop() {} } },
    RealtimeSessionService: { RealtimeSessionService: class {
      async createSession() {
        now += timingOptions.sessionMs ?? 0;
        if (timingOptions.sessionError) throw timingOptions.sessionError;
        return { id: 'session', connection: {
        roomId: 'room', userId: 'user', token: 'test', botName: 'bot'
      } }; }
      startHeartbeat() {} stopHeartbeat() {} async closeSession() {}
    } }
  }, {
    setTimeout: (callback, ms) => { timers.set(++timerId, { callback, ms }); return timerId; },
    clearTimeout: id => timers.delete(id)
  });
  ({ RealtimeVideoTrack: Track } = load('service/realtime/RealtimeVideoTrack.ets'));
  ({ RealtimeVideoFormat: Format } = load('service/realtime/RealtimeVideoFormat.ets'));
  ({ RealtimeMediaStream: MediaStream } = load('service/realtime/RealtimeMediaStream.ets'));
  const { RealtimeContext: Context } = load('service/realtime/RealtimeContext.ets');
  const { RemoteStream } = load('foundation/rtc/RemoteStream.ets');
  const { XmaxRealtimeManager } = load('core/realtime/XmaxRealtimeManager.ets');
  const { XmaxError, XmaxErrorCode: Code } = load('foundation/errors/XmaxError.ets');
  const { RealtimeConnectionState: State } = load('service/realtime/RealtimeState.ets');
  const { RealtimeModels } = load('core/realtime/RealtimeModel.ets');
  const manager = new XmaxRealtimeManager({}, { model: RealtimeModels.realtime('x2.0-sla') }, {});
  manager.setErrorListener(error => errors.push(error));
  manager.setStateListener(state => events.push(`state:${state.connectionState}`));
  const remote = new RemoteStream('room', 'bot');
  t.after(async () => { await manager.close(); assert.equal(timers.size, 0); });
  return { load, rtc, media, manager, events, messages, observations, errors, timers, State, XmaxError, Code,
    timingLogs, advance(ms) { now += ms; },
    remote, RemoteStream,
    async begin() {
      const local = new MediaStream('local', media.track);
      const input = media.track ? local : await manager.createLocalCameraStream(new Format(1024, 1920, 30));
      const pending = outcome(manager.startGeneration(input, new Context('prompt')));
      await settle();
      return { pending, task: messages.filter(m => m.event === 'start').at(-1)?.uid };
    },
    sei(task, stream = remote) { rtc.listener.onSeiMessageReceived(stream, task); },
    frame(stream = remote) { rtc.frameListener(stream); },
    runTimer(ms) {
      const entries = [...timers].filter(([, timer]) => timer.ms === ms);
      assert.equal(entries.length, 1);
      const [id, timer] = entries[0]; timers.delete(id); timer.callback();
    }
  };
}

test('startup timing spans session creation, RTC join, signaling, matched SEI and usable first frame', async t => {
  const f = fixture(t, { sessionMs: 10, roomMs: 20, signalMs: 2 });
  const first = await f.begin();
  assert.deepEqual(f.timingLogs, []);
  f.advance(100); f.sei(first.task); await settle();
  assert.deepEqual(f.timingLogs, []);
  f.advance(25); f.frame(); await first.pending;
  assert.equal(f.timingLogs.length, 1);
  assert.equal(f.timingLogs[0].option, 2);
  for (const detail of ['总耗时：157.0 ms',
    '实时连接：30.0 ms', '等待生成结果流确认：102.0 ms',
    '结果流确认到首帧就绪：25.0 ms']) assert.ok(f.timingLogs[0].message.includes(detail), detail);
  await f.manager.stopGeneration();
  const second = await f.begin();
  f.advance(10); f.sei(second.task); await settle();
  f.advance(3); f.frame(); await second.pending;
  assert.equal(f.timingLogs.length, 2);
  assert.match(f.timingLogs[1].message, /总耗时：15.0 ms/);
  assert.doesNotMatch(f.timingLogs[1].message, /服务端会话创建|实时连接：/);
});

test('rejected concurrent calls and condition updates do not reset startup timing or produce extra reports', async t => {
  const f = fixture(t), first = await f.begin();
  const { RealtimeContext } = f.load('service/realtime/RealtimeContext.ets');
  f.advance(50);
  await assert.rejects(f.manager.startGeneration(new RealtimeContext('overlap')), { code: f.Code.INVALID_CONFIGURATION });
  f.sei(first.task); await settle();
  f.advance(10); f.frame(); await first.pending;
  assert.equal(f.timingLogs.length, 1);
  assert.match(f.timingLogs[0].message, /总耗时：60.0 ms/);
  await f.manager.startGeneration(new RealtimeContext('update'));
  assert.equal(f.timingLogs.length, 1);
});

test('cancelled startup emits no timing report and a retry ignores the old task SEI', async t => {
  const f = fixture(t), first = await f.begin();
  f.advance(20); f.sei(first.task); await settle();
  await f.manager.stopGeneration();
  assert.equal((await first.pending).error.code, f.Code.CANCELLED);
  assert.deepEqual(f.timingLogs, []);
  const second = await f.begin();
  f.advance(10); f.sei(first.task); f.frame(); await settle();
  assert.deepEqual(f.timingLogs, []);
  f.advance(20); f.sei(second.task); await settle();
  f.advance(5); f.frame(); await second.pending;
  assert.equal(f.timingLogs.length, 1);
  assert.match(f.timingLogs[0].message, /总耗时：35.0 ms/);
  assert.match(f.timingLogs[0].message, /等待生成结果流确认：30.0 ms/);
});

test('generation confirmation and first-frame timeouts report the correct stage without changing the error', async t => {
  for (const [matched, milliseconds, stage] of [
    [false, 30000, '正在等待生成结果流确认'], [true, 10000, '结果流已确认，正在等待首帧']
  ]) {
    const f = fixture(t), first = await f.begin();
    if (matched) { f.sei(first.task); await settle(); }
    f.advance(milliseconds); f.runTimer(milliseconds);
    const result = await first.pending;
    assert.equal(result.error.code, f.Code.TIMEOUT);
    assert.equal(f.errors[0], result.error);
    assert.equal(f.timingLogs.length, 1);
    assert.ok(f.timingLogs[0].message.includes(`停留阶段：${stage}`));
    assert.ok(f.timingLogs[0].message.includes(`已耗时：${milliseconds.toFixed(1)} ms`));
    assert.equal(f.manager.currentState.connectionState, f.State.ERROR);
  }
});

test('session and room failures report their connection stage after cleanup', async t => {
  for (const [field, stage] of [['sessionError', '服务端会话创建'], ['roomError', '正在连接 RTC 房间']]) {
    const options = { sessionMs: 10, roomMs: 20 };
    const f = fixture(t, options);
    const error = new f.XmaxError(f.Code.NETWORK_ERROR, 'connection failed');
    options[field] = error;
    const first = await f.begin();
    assert.equal((await first.pending).error, error);
    assert.equal(f.timingLogs.length, 1);
    assert.ok(f.timingLogs[0].message.includes(`停留阶段：${stage}`));
    assert.equal(f.manager.currentState.connectionState, f.State.ERROR);
    assert.equal(f.messages.some(message => message.event === 'start'), false);
  }
});

test('synchronous stop from the GENERATING listener does not produce a successful timing report', async t => {
  const f = fixture(t);
  f.manager.setStateListener(state => {
    if (state.connectionState === f.State.GENERATING) void f.manager.stopGeneration();
  });
  const first = await f.begin();
  f.sei(first.task); await settle(); f.frame();
  assert.equal((await first.pending).error.code, f.Code.CANCELLED);
  assert.deepEqual(f.timingLogs, []);
});

test('GENERATING and one-call return wait for a usable frame without requiring a mounted view', async t => {
  const f = fixture(t), { pending, task } = await f.begin();
  f.rtc.listener.onRemoteAudioPublished('bot', true);
  f.frame(); // A frame before matching SEI cannot satisfy this generation.
  f.sei(task);
  await settle();
  let returned = false; pending.then(() => { returned = true; });
  assert.equal(f.manager.currentState.connectionState, f.State.CONNECTED);
  assert.equal(f.events.includes('audio:bot:true'), false);
  assert.equal(returned, false);
  assert.deepEqual([...f.timers.values()].map(timer => timer.ms), [10000]);
  f.frame(new f.RemoteStream('room', 'other'));
  f.frame(new f.RemoteStream('other-room', 'bot'));
  await settle();
  assert.equal(returned, false);
  f.frame();
  const result = await pending;
  assert.ok(result.value.videoTrack);
  assert.equal(f.manager.currentState.connectionState, f.State.GENERATING);
  assert.equal(f.manager.currentState.taskId, task);
  assert.ok(f.events.indexOf('audio:bot:true') < f.events.indexOf(`state:${f.State.GENERATING}`));
  assert.equal(f.events.includes('bind-surface'), false);
  assert.equal(f.observations.at(-1).enabled, false);
  assert.equal(f.timers.size, 0);
});

test('an immediate frame after SEI is remembered until Core starts waiting', async t => {
  const f = fixture(t), { pending, task } = await f.begin();
  f.sei(task); f.frame();
  assert.ok((await pending).value.videoTrack);
  assert.equal(f.timers.size, 0);
});

test('10-second first-frame timeout stops the task, restores preview audio and allows retry', async t => {
  const f = fixture(t), first = await f.begin();
  f.sei(first.task); await settle(); f.runTimer(10000);
  const failure = (await first.pending).error;
  assert.equal(failure.code, f.Code.TIMEOUT);
  assert.equal(failure.message, 'Remote video first frame timed out');
  assert.deepEqual(f.errors, [failure]);
  assert.equal(f.manager.currentState.connectionState, f.State.ERROR);
  assert.equal(f.messages.at(-1).event, 'stop');
  assert.equal(f.messages.at(-1).uid, first.task);
  assert.equal(f.media.previewAudio, true);
  assert.equal(f.media.task, null);
  f.frame(); await settle();
  assert.equal(f.events.includes('audio:bot:true'), false);
  const second = await f.begin();
  f.sei(second.task); f.frame();
  assert.ok((await second.pending).value.videoTrack);
});

test('stop cancels first-frame waiting and an old timeout cannot fail a new task', async t => {
  const f = fixture(t), first = await f.begin();
  f.sei(first.task); await settle();
  const oldTimeout = [...f.timers.values()][0].callback;
  await f.manager.stopGeneration();
  assert.equal((await first.pending).error.code, f.Code.CANCELLED);
  assert.equal(f.errors.length, 0);
  const second = await f.begin(); f.sei(second.task); await settle();
  oldTimeout(); await settle();
  assert.equal(f.manager.currentState.connectionState, f.State.CONNECTED);
  assert.equal(f.messages.at(-1).event, 'start');
  f.frame();
  assert.equal((await second.pending).error, undefined);
});

test('stop after the frame callback but before its continuation cannot activate audio or emit GENERATING', async t => {
  const f = fixture(t), { pending, task } = await f.begin();
  f.sei(task); await settle(); f.frame();
  await f.manager.stopGeneration();
  assert.equal((await pending).error.code, f.Code.CANCELLED);
  assert.equal(f.events.includes('audio:bot:true'), false);
  assert.equal(f.events.includes(`state:${f.State.GENERATING}`), false);
});

test('disconnect and close cancel pending first-frame waits without a late state transition', async t => {
  for (const operation of ['disconnect', 'close']) {
    const f = fixture(t), { pending, task } = await f.begin();
    f.sei(task); await settle(); await f.manager[operation]();
    assert.equal((await pending).error.code, f.Code.CANCELLED);
    f.frame(); await settle();
    assert.equal(f.events.includes(`state:${f.State.GENERATING}`), false);
    assert.equal(f.timers.size, 0);
  }
});

test('restarting on the same remote stream requires a new frame and stops old audio', async t => {
  const f = fixture(t), first = await f.begin();
  f.sei(first.task); f.frame(); await first.pending;
  await f.manager.stopGeneration();
  assert.equal(f.events.at(-2), 'audio:bot:false');
  f.rtc.listener.onRemoteAudioPublished('bot', true);
  assert.equal(f.events.filter(e => e === 'audio:bot:true').length, 1);
  const second = await f.begin();
  f.sei(first.task); f.frame(); await settle(); // Old task cannot arm first-frame observation.
  f.sei(second.task); await settle();
  assert.equal(f.manager.currentState.connectionState, f.State.CONNECTED);
  f.frame(); await second.pending;
  assert.equal(f.events.filter(e => e === 'audio:bot:true').length, 2);
  f.rtc.listener.onRemoteAudioPublished('bot', true); // Repeated publication is idempotent.
  assert.equal(f.events.filter(e => e === 'audio:bot:true').length, 2);
});

test('remote video removal cancels startup and audio cannot resume from later publication', async t => {
  const f = fixture(t), { pending, task } = await f.begin();
  f.sei(task); await settle();
  f.rtc.listener.onRemoteVideoPublished('bot', false);
  assert.equal((await pending).error.code, f.Code.CANCELLED);
  f.rtc.listener.onRemoteAudioPublished('bot', true);
  assert.equal(f.events.includes('audio:bot:true'), false);
});

test('audio activation failure rejects startup, stops the task, and never emits GENERATING', async t => {
  const f = fixture(t), { pending, task } = await f.begin();
  const error = new f.XmaxError(f.Code.RTC_ERROR, 'audio failed');
  f.rtc.subscribeRemoteAudio = (_user, enabled) => { if (enabled) throw error; };
  f.sei(task); f.frame();
  assert.equal((await pending).error, error);
  assert.deepEqual(f.errors, [error]);
  assert.equal(f.messages.at(-1).event, 'stop');
  assert.equal(f.events.includes(`state:${f.State.GENERATING}`), false);
});

test('fatal RTC errors during first-frame waiting reject promptly with the original error once', async t => {
  const f = fixture(t), { pending, task } = await f.begin();
  f.sei(task); await settle();
  const error = new f.XmaxError(f.Code.RTC_ERROR, 'subscription failed');
  f.rtc.subscribeRemoteVideo = () => { throw error; };
  f.rtc.listener.onRemoteVideoPublished('bot', true);
  assert.equal((await pending).error, error);
  assert.deepEqual(f.errors, [error]);
  assert.equal(f.timers.size, 0);
  assert.equal(f.events.includes(`state:${f.State.GENERATING}`), false);
});

test('a sink setup failure stops generation before any audio or GENERATING state', async t => {
  const f = fixture(t), { pending, task } = await f.begin();
  const error = new f.XmaxError(f.Code.RTC_ERROR, 'sink failed');
  f.rtc.observeRemoteVideoFrames = (_stream, enabled) => { if (enabled) throw error; };
  f.sei(task);
  assert.equal((await pending).error, error);
  assert.equal(f.events.includes('audio:bot:true'), false);
  assert.equal(f.messages.at(-1).event, 'stop');
});

test('RTC bridge observes postprocessed main-stream frames only while armed and removes its callback on destroy', async () => {
  const handlers = new Map(), sinks = [], received = [];
  const engine = {
    on: (name, callback) => handlers.set(name, callback),
    off: name => handlers.delete(name),
    setRemoteVideoSinkWithConfig(key, config, enabled) { sinks.push({ key, config, enabled }); return 0; }
  };
  const load = loadEts({
    '@kit.ArkTS': { util: { TextDecoder: { create: () => ({
      decodeToString: bytes => Buffer.from(bytes).toString('utf8')
    }) } } },
    '@bytertc/volcenginertc': {
      MirrorType: { kMirrorTypeNone: 0 }, StreamIndex: { kStreamIndexMain: 0 },
      RemoteVideoSinkPosition: { kRemoteVideoSinkPositionAfterPostProcess: 1 },
      VideoPixelFormat: { kVideoPixelFormatI420: 1 },
      VideoApplyRotation: { kVideoApplyRotationDefault: -1 },
      VideoSinkMirrorType: { kVideoSinkMirrorTypeOFF: 2 }
    },
    RtcEngineManager: { RtcEngineManager: { async acquire() { return { engine }; }, async release() {} } },
    RtcStatsLogger: { RtcStatsLogger: {} }, XmaxLogger: { XmaxLogger: {} }
  });
  const { RtcManager } = load('foundation/rtc/RtcManager.ets');
  const { RemoteStream } = load('foundation/rtc/RemoteStream.ets');
  const rtc = new RtcManager({});
  await rtc.initialize();
  rtc.activeRoomId = 'room';
  rtc.setEventListener({ onSeiMessageReceived() {} });
  rtc.setRemoteVideoFrameListener(stream => received.push(stream.key()));
  const key = { room_id: 'room', user_id: 'bot', stream_index: 0 };
  const frame = { width: 1024, height: 1920 };
  handlers.get('onSEIMessageReceived')(key, new Uint8Array(Buffer.from('task')).buffer);
  const onFrame = handlers.get('onRemoteVideoFrame');
  const stream = new RemoteStream('room', 'bot');
  onFrame(key, 1, frame);
  assert.deepEqual(received, []);
  rtc.observeRemoteVideoFrames(stream, true);
  assert.deepEqual(sinks[0], { key, config: {
    position: 1, pixel_format: 1, apply_rotation: -1, mirror_type: 2
  }, enabled: true });
  onFrame({ ...key, room_id: 'other' }, 1, frame);
  onFrame({ ...key, user_id: 'other' }, 1, frame);
  onFrame({ ...key, stream_index: 1 }, 1, frame);
  onFrame(key, 0, frame);
  onFrame(key, 1, { width: 0, height: 1920 });
  assert.deepEqual(received, []);
  onFrame(key, 1, frame);
  assert.deepEqual(received, ['room:bot']);
  rtc.observeRemoteVideoFrames(stream, false);
  assert.equal(sinks.at(-1).enabled, false);
  onFrame(key, 1, frame);
  assert.equal(received.length, 1);
  rtc.observeRemoteVideoFrames(stream, true);
  onFrame(key, 1, frame);
  assert.equal(received.length, 2);
  await rtc.destroy();
  assert.equal(handlers.has('onRemoteVideoFrame'), false);
  onFrame(key, 1, frame); // Callback retained by a previous engine cannot leak into another lifetime.
  assert.equal(received.length, 2);
});
