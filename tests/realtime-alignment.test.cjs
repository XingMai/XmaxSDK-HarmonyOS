const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { loadEts } = require('./ets-loader.cjs');

const platform = {
  '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
  '@kit.ArkTS': { util: {
    generateRandomUUID: () => randomUUID(),
    Base64Helper: class { encodeToStringSync(bytes) { return Buffer.from(bytes).toString('base64'); } }
  } },
  '@kit.BasicServicesKit': { deviceInfo: { distributionOSVersion: '5.1.0', productModel: 'Test model' } },
  XmaxLogger: { XmaxLogger: { error() {}, debug() {}, info() {}, warn() {} } }
};
const settle = async () => { for (let i = 0; i < 30; i++) await Promise.resolve(); };
const outcome = promise => promise.then(value => ({ value }), error => ({ error }));
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

function managerFixture() {
  const calls = { sessions: [], closed: [], starts: [], updates: [], stops: [], audio: [], switches: 0 };
  const timers = [];
  let sessionGate = null, autoConfirm = true, media, stream, api;
  let Track, Format, MediaStream, XmaxError, Code, CameraPosition, updatePosition;
  class FakeMedia {
    constructor() { media = this; this.currentTrack = null; this.hasAudio = true; }
    get currentVideoFormat() { return this.currentTrack?.videoFormat; }
    async createLocalCameraStream(format, position) {
      if (this.currentTrack) throw new XmaxError(Code.INVALID_CONFIGURATION, 'Already started');
      this.currentTrack = new Track('video0', format, position);
      return new MediaStream('local', this.currentTrack);
    }
    async stopLocalCameraStream() { this.currentTrack = null; }
    async stopLocalStream() { this.currentTrack = null; }
    owns(local) { return local.videoTrack !== undefined && Track.resolve(local.videoTrack) === this.currentTrack; }
    setLocalAudioPreviewEnabled(value) { calls.audio.push(value); }
    start(task) { this.interactionTask = task; }
    stop() { this.interactionTask = null; }
    prepareForClose() {}
    setCameraPreviewReadyListener() {}
    async switchCamera() {
      calls.switches++;
      updatePosition(this.currentTrack, CameraPosition.BACK);
      return new MediaStream('local', this.currentTrack);
    }
  }
  class FakeStream {
    constructor() { stream = this; this.currentGenerationTaskId = ''; }
    async connect(_connection, _audio, ensure) { ensure(); }
    async disconnect() { this.stopGeneration(''); }
    activateRemoteAudio() {}
    beginGeneration(task, format, context) {
      this.currentGenerationTaskId = task;
      const gate = deferred();
      this.confirmation = gate;
      calls.starts.push({ task, format, context, gate });
      if (autoConfirm) gate.resolve();
      return gate.promise;
    }
    updateGeneration(task, format, context) { calls.updates.push({ task, format, context }); }
    stopGeneration(task) {
      calls.stops.push(task);
      this.currentGenerationTaskId = '';
      this.confirmation?.reject(new XmaxError(Code.CANCELLED, 'Stopped'));
      this.confirmation = null;
    }
  }
  class FakeSessionService {
    constructor() { api = this; }
    async createSession(model) {
      calls.sessions.push(model);
      if (sessionGate) await sessionGate.promise;
      return { id: `session-${calls.sessions.length}`, connection: { roomId: 'room', botName: 'bot' } };
    }
    async closeSession(id) { calls.closed.push(id); }
    startHeartbeat() {}
    stopHeartbeat() {}
  }
  const load = loadEts({ ...platform,
    RtcManager: { RtcManager: class {} },
    MediaController: { MediaController: FakeMedia },
    StreamController: { StreamController: FakeStream },
    RealtimeSessionService: { RealtimeSessionService: FakeSessionService },
    RenderController: { RenderController: class {
      registerRemoteTrack() {} resetRemoteTrack() {} failRemoteFrameWait() {}
      async waitUntilRemoteFrameReady() {}
    } }
  }, { setTimeout: callback => { timers.push(callback); return timers.length; } });
  ({ RealtimeVideoTrack: Track, updateRealtimeVideoTrackPosition: updatePosition } = load('service/realtime/RealtimeVideoTrack.ets'));
  ({ RealtimeVideoFormat: Format } = load('service/realtime/RealtimeVideoFormat.ets'));
  ({ RealtimeMediaStream: MediaStream } = load('service/realtime/RealtimeMediaStream.ets'));
  ({ XmaxError, XmaxErrorCode: Code } = load('foundation/errors/XmaxError.ets'));
  ({ CameraPosition } = load('foundation/media/camera/CameraPosition.ets'));
  const { RealtimeContext: Context } = load('service/realtime/RealtimeContext.ets');
  const { RealtimeConnectionState: State } = load('service/realtime/RealtimeState.ets');
  const { XmaxRealtimeManager } = load('core/realtime/XmaxRealtimeManager.ets');
  const manager = new XmaxRealtimeManager({}, { model: { name: 'x2.0-sla' } }, {});
  return { manager, media, stream, calls, timers, State, Context, Format, Track, MediaStream,
    create: () => manager.createLocalCameraStream(new Format(1024, 1920, 30), CameraPosition.FRONT),
    holdSession() { sessionGate = deferred(); return sessionGate; },
    holdGeneration() { autoConfirm = false; },
    runSwitchDelay() { assert.equal(timers.length, 1); timers.shift()(); }
  };
}

test('one-call generation connects on demand, reuses its remote track and supports the original API', async () => {
  const f = managerFixture(), local = await f.create();
  assert.equal(f.calls.sessions.length, 0);
  const context = new f.Context('first');
  const first = await f.manager.startGeneration(local, context);
  const second = await f.manager.startGeneration(local, new f.Context('updated'));
  assert.equal(second.videoTrack, first.videoTrack);
  assert.deepEqual(f.calls.sessions, ['x2.0-sla']);
  assert.equal(f.calls.starts.length, 1);
  assert.equal(f.calls.updates[0].context.prompt, 'updated');
  assert.equal(f.calls.starts[0].format, local.videoTrack.videoFormat);
  assert.equal(f.calls.starts[0].format.width, 1024);
  await f.manager.stopGeneration();
  const resumed = await f.manager.startGeneration(local);
  assert.equal(resumed.videoTrack, first.videoTrack);
  assert.equal(f.calls.starts[1].context.prompt, 'updated');
  await f.manager.stopGeneration();
  assert.equal(await f.manager.startGeneration(new f.Context('legacy')), undefined);
});

test('missing context and foreign stream are rejected before creating a session', async () => {
  const f = managerFixture(), local = await f.create();
  await assert.rejects(f.manager.startGeneration(local), { code: 'INVALID_CONFIGURATION' });
  const foreign = new f.MediaStream('local', new f.Track('video0', local.videoTrack.videoFormat));
  await assert.rejects(f.manager.startGeneration(foreign, new f.Context('test')), { code: 'INVALID_CONFIGURATION' });
  assert.equal(f.calls.sessions.length, 0);
});

test('stop while connecting cancels automatic generation and restores local audio preview', async () => {
  const f = managerFixture(), local = await f.create(), gate = f.holdSession();
  const pending = outcome(f.manager.startGeneration(local, new f.Context('test')));
  assert.equal(f.calls.audio.at(-1), false);
  await f.manager.stopGeneration();
  gate.resolve();
  assert.equal((await pending).error.code, 'CANCELLED');
  assert.equal(f.calls.starts.length, 0);
  assert.equal(f.calls.audio.at(-1), true);
  assert.equal(f.manager.currentState.connectionState, f.State.CONNECTED);
});

test('stop from the synchronous CONNECTING listener also cancels one-call generation', async () => {
  const f = managerFixture(), local = await f.create();
  f.manager.setStateListener(state => {
    if (state.connectionState === f.State.CONNECTING) void f.manager.stopGeneration();
  });
  await assert.rejects(f.manager.startGeneration(local, new f.Context('test')), { code: 'CANCELLED' });
  assert.equal(f.calls.starts.length, 0);
});

test('close during connection rolls back the late session without reopening audio or generation', async () => {
  const f = managerFixture(), local = await f.create(), gate = f.holdSession();
  const pending = outcome(f.manager.startGeneration(local, new f.Context('test')));
  await f.manager.close();
  const audioCount = f.calls.audio.length;
  gate.resolve();
  assert.equal((await pending).error.code, 'CANCELLED');
  assert.equal(f.calls.audio.length, audioCount);
  assert.equal(f.calls.audio.at(-1), false);
  assert.equal(f.calls.starts.length, 0);
  assert.deepEqual(f.calls.closed, ['session-1']);
  assert.equal(f.manager.currentState.connectionState, f.State.DISCONNECTED);
});

test('a cancelled start cannot stop a newer generation or restore its muted preview', async () => {
  const f = managerFixture(), local = await f.create();
  await f.manager.connect(local);
  f.holdGeneration();
  const old = outcome(f.manager.startGeneration(new f.Context('old')));
  void f.manager.stopGeneration();
  const newer = f.manager.startGeneration(local, new f.Context('new'));
  const newTask = f.stream.currentGenerationTaskId;
  assert.equal((await old).error.code, 'CANCELLED');
  assert.equal(f.stream.currentGenerationTaskId, newTask);
  assert.equal(f.calls.audio.at(-1), false);
  f.calls.starts.at(-1).gate.resolve();
  await newer;
  assert.equal(f.media.interactionTask, newTask);
  assert.equal(f.manager.currentState.taskId, newTask);
});

test('switchCamera preserves track/session/format and restores the last generation context', async () => {
  const f = managerFixture(), local = await f.create();
  await f.manager.startGeneration(local, new f.Context('first'));
  await f.manager.startGeneration(new f.Context('latest'));
  const oldTask = f.manager.currentState.taskId;
  const switching = f.manager.switchCamera();
  await settle();
  assert.equal(f.manager.currentState.connectionState, f.State.CONNECTED);
  assert.equal(f.calls.switches, 1);
  f.runSwitchDelay();
  const switched = await switching;
  assert.equal(switched.videoTrack, local.videoTrack);
  assert.equal(f.calls.sessions.length, 1);
  assert.equal(f.calls.starts.at(-1).context.prompt, 'latest');
  assert.notEqual(f.manager.currentState.taskId, oldTask);
  assert.equal(f.calls.starts.at(-1).format, local.videoTrack.videoFormat);
});

test('stopping during the camera settling delay prevents generation from restarting', async () => {
  const f = managerFixture(), local = await f.create();
  await f.manager.startGeneration(local, new f.Context('test'));
  const switching = outcome(f.manager.switchCamera());
  await settle();
  await f.manager.stopGeneration();
  f.runSwitchDelay();
  assert.equal((await switching).error.code, 'CANCELLED');
  assert.equal(f.calls.starts.length, 1);
  assert.equal(f.calls.audio.at(-1), true);
});

test('camera switching is rejected while generation startup is still pending', async () => {
  const f = managerFixture(), local = await f.create();
  await f.manager.connect(local);
  f.holdGeneration();
  const starting = outcome(f.manager.startGeneration(new f.Context('test')));
  await assert.rejects(f.manager.switchCamera(), { code: 'INVALID_CONFIGURATION' });
  assert.equal(f.calls.switches, 0);
  await f.manager.stopGeneration();
  assert.equal((await starting).error.code, 'CANCELLED');
});

test('camera specifications require disconnect, stop and create; old streams become invalid', async () => {
  const f = managerFixture(), local = await f.create();
  const firstRemote = await f.manager.startGeneration(local, new f.Context('test'));
  assert.equal(f.manager.replaceLocalCameraStream, undefined);
  await assert.rejects(f.manager.stopLocalCameraStream(), { code: 'INVALID_CONFIGURATION' });
  await f.manager.disconnect();
  await f.manager.stopLocalCameraStream();
  const format = new f.Format(832, 1472, 24);
  const newLocal = await f.manager.createLocalCameraStream(format);
  await assert.rejects(f.manager.startGeneration(local, new f.Context('test')), { code: 'INVALID_CONFIGURATION' });
  const remote = await f.manager.startGeneration(newLocal, new f.Context('new specs'));
  assert.notEqual(remote.videoTrack, firstRemote.videoTrack);
  assert.equal(remote.videoTrack.videoFormat, format);
  assert.equal(f.calls.sessions.length, 2);
});

function renderFixture() {
  const load = loadEts({ ...platform,
    DefaultTrajectoryEffectRenderer: { DefaultTrajectoryEffectRenderer: class {} },
    TrajectoryOverlayView: { TrajectoryOverlayView: class {} }
  });
  const { RealtimeVideoTrack: Track, updateRealtimeVideoTrackPosition: updatePosition } = load('service/realtime/RealtimeVideoTrack.ets');
  const { VideoRenderBinding: Binding, VideoRenderRegistry: Registry } = load('rendering/video/VideoRenderRegistry.ets');
  return { load, Track, updatePosition, Binding, Registry };
}

test('ArkUI property copies retain opaque track identity, metadata and render/interaction bindings', () => {
  const f = renderFixture();
  const original = new f.Track('same-id', { width: 1024, height: 1920, fps: 30 }, 0);
  const copy = Object.assign(Object.create(Object.getPrototypeOf(original)), original);
  const another = new f.Track('same-id');
  const { TrajectoryRegistry } = f.load('rendering/trajectory/TrajectoryRegistry.ets');
  const binding = new f.Binding('rtc', () => {}, () => {});
  f.Registry.register(original, binding);
  TrajectoryRegistry.register(original, { submit() {} });
  assert.equal(f.Track.resolve(copy), original);
  assert.equal(copy.videoFormat, original.videoFormat);
  f.updatePosition(original, 1);
  assert.equal(copy.position, 1);
  assert.equal(f.Registry.libraryName(copy), 'rtc');
  assert.equal(f.Registry.libraryName(another), '');
  assert.equal(TrajectoryRegistry.binding(copy), TrajectoryRegistry.binding(original));
  f.Registry.unregister(original);
  TrajectoryRegistry.unregister(original);
});

test('video view rebinds a changed track, clears frames, and ignores late surface callbacks', () => {
  const f = renderFixture(), events = [];
  const { XmaxVideoView } = f.load('rendering/video/XmaxVideoView.ets');
  const a = new f.Track('same-id'), b = new f.Track('same-id');
  const bindingA = new f.Binding('rtc', id => events.push(['attachA', id]), id => events.push(['detachA', id]));
  const bindingB = new f.Binding('rtc', id => events.push(['attachB', id]), id => events.push(['detachB', id]));
  f.Registry.register(a, bindingA); f.Registry.register(b, bindingB);
  const view = new XmaxVideoView(), ready = [];
  view.onVideoReadyChanged = value => ready.push(value);
  view.track = a; view.aboutToAppear();
  const oldView = view.viewId;
  view.attachVideo(oldView);
  bindingA.setPreviewFrame('old frame'); bindingA.setVideoReady(true);
  assert.equal(view.previewFrame, 'old frame');
  view.track = b; view.onTrackChanged();
  assert.equal(view.previewFrame, undefined);
  assert.equal(ready.at(-1), false);
  view.attachVideo(view.viewId);
  view.attachVideo(oldView);
  bindingA.setPreviewFrame('late frame'); bindingA.setVideoReady(true);
  assert.equal(view.previewFrame, undefined);
  assert.deepEqual(events.map(event => event[0]), ['attachA', 'detachA', 'attachB']);
  bindingB.setVideoReady(true);
  bindingB.setPreviewFrame('active frame');
  assert.equal(ready.at(-1), true);
  f.Registry.unregister(b);
  assert.equal(ready.at(-1), false);
  assert.equal(view.previewFrame, undefined);
  view.aboutToDisappear();
  assert.equal(events.filter(event => event[0] === 'detachB').length, 1);
  f.Registry.unregister(a);
});

test('remote rendering waits for first frame, hides on stop, and replays readiness for a reused RTC stream', () => {
  const f = renderFixture(), readiness = [], rendered = new Set(), bound = [];
  const { RemoteVideoController } = f.load('rendering/video/RemoteVideoController.ets');
  const { RemoteStream } = f.load('foundation/rtc/RemoteStream.ets');
  let listener;
  const rtc = {
    setRemoteVideoRenderedListener(value) { listener = value; },
    hasRenderedRemoteVideo(stream) { return rendered.has(stream.key()); },
    bindRemoteVideo(stream, view) { bound.push([stream.key(), view]); },
    unbindRemoteVideo() {}
  };
  const controller = new RemoteVideoController(rtc, ready => readiness.push(ready));
  const stream = new RemoteStream('room', 'bot');
  controller.attach('view', 0); controller.setRemoteStream(stream);
  assert.equal(readiness.at(-1), false);
  listener(new RemoteStream('old-room', 'bot'));
  assert.equal(readiness.at(-1), false);
  rendered.add(stream.key()); listener(stream);
  assert.equal(readiness.at(-1), true);
  controller.setRemoteStream(null);
  assert.equal(readiness.at(-1), false);
  listener(stream);
  assert.equal(readiness.at(-1), false);
  controller.setRemoteStream(new RemoteStream('room', 'bot'));
  assert.equal(readiness.at(-1), true);
  controller.detach('old-view');
  assert.equal(readiness.at(-1), true);
  controller.detach('view');
  assert.equal(readiness.at(-1), false);
  controller.reset();
});

test('a stop from the GENERATING listener prevents returning a stale successful start', async () => {
  const f = managerFixture(), local = await f.create();
  f.manager.setStateListener(state => {
    if (state.connectionState === f.State.GENERATING) void f.manager.stopGeneration();
  });
  await assert.rejects(f.manager.startGeneration(local, new f.Context('test')), { code: 'CANCELLED' });
  assert.equal(f.manager.currentState.connectionState, f.State.CONNECTED);
  assert.equal(f.media.interactionTask, null);
});

test('composite view resets on replacement/nil and ignores a removed remote view callback', () => {
  const f = renderFixture();
  const { XmaxRealtimeVideoView } = f.load('rendering/video/XmaxRealtimeVideoView.ets');
  const view = new XmaxRealtimeVideoView();
  view.remoteTrack = new f.Track('remote'); view.aboutToAppear();
  const oldKey = view.remoteViewKey;
  view.onRemoteVideoReady(oldKey, true);
  assert.equal(view.remoteReady, true);
  view.remoteTrack = new f.Track('remote'); view.onRemoteTrackChanged();
  assert.equal(view.remoteReady, false);
  view.onRemoteVideoReady(oldKey, true);
  assert.equal(view.remoteReady, false);
  view.onRemoteVideoReady(view.remoteViewKey, true);
  assert.equal(view.remoteReady, true);
  view.remoteTrack = undefined; view.onRemoteTrackChanged();
  view.onRemoteVideoReady(view.remoteViewKey, true);
  assert.equal(view.remoteReady, false);
});

test('camera controller preserves native capture format and track when switching; SLA dimensions stay unchanged', async () => {
  const calls = [];
  const load = loadEts({ ...platform,
    PermissionManager: { PermissionManager: class { async ensureCameraPermission() {} } }
  });
  const { CameraController } = load('media/camera/CameraController.ets');
  const { RealtimeVideoFormat } = load('service/realtime/RealtimeVideoFormat.ets');
  const { CameraPosition } = load('foundation/media/camera/CameraPosition.ets');
  const camera = new CameraController({}, {
    switchCamera(position) { calls.push(['switch', position]); },
    startVideoCapture(...format) { calls.push(['capture', ...format]); },
    renderLibraryName() { return 'rtc'; },
    stopVideoCapture() {}, unbindLocalVideo() {}
  }, { setVideoEncoderConfig() {} });
  const local = await camera.createLocalCameraStream(new RealtimeVideoFormat(1024, 1920, 30), CameraPosition.FRONT);
  assert.deepEqual(calls[1], ['capture', 1024, 1920, 30]);
  const switched = await camera.switchCamera();
  assert.equal(switched.videoTrack, local.videoTrack);
  assert.equal(switched.videoTrack.position, CameraPosition.BACK);
  assert.equal(calls.filter(call => call[0] === 'capture').length, 1);
  await camera.stopLocalCameraStream();
});

test('RTC first-frame cache ignores other rooms/engines and resets on unpublish and leaving', async () => {
  const handlers = new Map(), roomHandlers = new Map();
  const engine = { on(name, fn) { handlers.set(name, fn); }, off(name) { handlers.delete(name); } };
  const load = loadEts({ ...platform,
    '@bytertc/volcenginertc': { MirrorType: { kMirrorTypeNone: 0 }, StreamIndex: { kStreamIndexMain: 0 } },
    RtcEngineManager: { RtcEngineManager: { async acquire() { return { engine }; }, async release() {} } },
    RtcQualityConverter: {}, RtcStatsLogger: {}, RtcVideoConverter: {}
  });
  const { RtcManager } = load('foundation/rtc/RtcManager.ets');
  const { RemoteStream } = load('foundation/rtc/RemoteStream.ets');
  const rtc = new RtcManager({}), stream = new RemoteStream('room', 'bot'), events = [];
  rtc.setRemoteVideoRenderedListener(value => events.push(value.key()));
  await rtc.initialize();
  rtc.activeRoomId = 'room';
  const firstFrame = handlers.get('onFirstRemoteVideoFrameRendered');
  firstFrame({ room_id: 'stale-room', user_id: 'bot', stream_index: 0 }, {});
  firstFrame({ room_id: 'room', user_id: 'bot', stream_index: 1 }, {});
  assert.equal(events.length, 0);
  const key = { room_id: 'room', user_id: 'bot', stream_index: 0 };
  firstFrame(key, {});
  assert.equal(rtc.hasRenderedRemoteVideo(stream), true);
  const room = { on(name, fn) { roomHandlers.set(name, fn); } };
  rtc.room = room; rtc.bindRoomEvents(room);
  roomHandlers.get('onUserPublishStreamVideo')('room', 'bot', false);
  assert.equal(rtc.hasRenderedRemoteVideo(stream), false);
  firstFrame(key, {});
  rtc.room = null;
  await rtc.leaveRoom();
  assert.equal(rtc.hasRenderedRemoteVideo(stream), false);
  await rtc.destroy();
  const count = events.length;
  firstFrame(key, {});
  assert.equal(events.length, count);
  assert.equal(handlers.has('onFirstRemoteVideoFrameRendered'), false);
});

function exampleFixture() {
  const f = managerFixture();
  const load = loadEts({ ...platform,
    '@kit.PerformanceAnalysisKit': { hilog: { error() {} } },
    '@xmax/sdk': {
      CameraPosition: { FRONT: 'front' }, RealtimeConnectionState: f.State,
      RealtimeContext: f.Context, RealtimeMediaStream: f.MediaStream, RealtimeVideoFormat: f.Format,
      XmaxLoggerOption: { ALL: 3 },
      RealtimeConfiguration: class {}, RealtimeModels: { realtime() {} }, XmaxConfiguration: class {},
      XmaxClient: class { createRealtimeManager() { return f.manager; } }
    },
    XLabConfiguration: { XLabConfiguration: { currentApiKey: () => 'test-only' } },
    XLabModelSelection: { XLabModelSelection: { current: () => 'x2.0-sla' } },
    ReferenceDataSource: { ReferenceDataSource: { categories: () => [] } }
  }, { Observed: value => value });
  const path = require('node:path');
  const { RealtimeViewModel } = load(path.resolve(__dirname,
    '../examples/XLab/entry/src/main/ets/modules/xlrealtime/mvvm/viewmodel/RealtimeViewModel.ets'));
  return { ...f, viewModel: new RealtimeViewModel([]) };
}

test('XLab starts with local preview only, then starts MOX directly from idle', async () => {
  const f = exampleFixture();
  await f.viewModel.connect({});
  await settle();
  assert.ok(f.viewModel.state.localVideoTrack);
  assert.equal(f.calls.sessions.length, 0);
  f.viewModel.state.selectedCategoryId = 'mox';
  f.viewModel.startMoxGeneration();
  await settle();
  assert.equal(f.calls.sessions.length, 1);
  assert.equal(f.calls.starts.length, 1);
  assert.ok(f.viewModel.state.remoteVideoTrack);
  assert.equal(f.viewModel.state.connectionState, f.State.GENERATING);
});

test('XLab cancellation during one-call connection leaves local preview without starting generation', async () => {
  const f = exampleFixture(), gate = f.holdSession();
  await f.viewModel.connect({});
  await settle();
  f.viewModel.state.selectedCategoryId = 'mox';
  f.viewModel.startMoxGeneration();
  await settle();
  assert.equal(f.manager.currentState.connectionState, f.State.CONNECTING);
  f.viewModel.cancelGeneration();
  gate.resolve();
  await settle();
  assert.equal(f.calls.starts.length, 0);
  assert.equal(f.viewModel.state.remoteVideoTrack, null);
  assert.equal(f.viewModel.state.isGenerationStarting, false);
  assert.equal(f.viewModel.state.errorMessage, '');
  assert.ok(f.viewModel.state.localVideoTrack);
});
