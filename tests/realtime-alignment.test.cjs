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

function managerFixture(modelName = 'x2.0-sla') {
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
    async setLocalAudioVolume(value) { this.volume = value; }
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
    setRemoteAudioVolume(value) { this.volume = value; }
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
    startHeartbeat(id, onFailure) { this.heartbeat = error => onFailure(id, error); }
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
  const { RealtimeModels } = load('core/realtime/RealtimeModel.ets');
  const manager = new XmaxRealtimeManager({}, { model: RealtimeModels.realtime(modelName) }, {});
  return { load, manager, media, stream, api, calls, timers, State, Context, Format, Track, MediaStream, XmaxError, Code,
    create: () => manager.createLocalCameraStream(new Format(1024, 1920, 30), CameraPosition.FRONT),
    holdSession() { sessionGate = deferred(); return sessionGate; },
    holdGeneration() { autoConfirm = false; },
    runSwitchDelay() { assert.equal(timers.length, 1); timers.shift()(); }
  };
}

test('default camera formats follow the manager model and reach generation signaling unchanged', async () => {
  for (const [name, width, height, fps] of [['x2.0', 832, 1472, 24], ['x2.0-sla', 1024, 1920, 30]]) {
    const f = managerFixture(name);
    const local = await f.manager.createLocalCameraStream(undefined, 'back');
    assert.deepEqual(local.videoTrack.videoFormat, new f.Format(width, height, fps));
    assert.equal(local.videoTrack.position, 'back');
    await f.manager.startGeneration(local, new f.Context('test'));
    assert.deepEqual(f.calls.sessions, [name]);
    assert.deepEqual(f.calls.starts[0].format, new f.Format(width, height, fps));
    await f.manager.close();
  }
});

test('SLA rejects all image overloads and video input before touching an active camera or generation', async () => {
  const f = managerFixture(), errors = [], mediaCalls = [];
  f.media.createLocalImageStream = async () => { mediaCalls.push('image'); };
  f.media.createLocalVideoStream = async () => { mediaCalls.push('video'); };
  f.manager.setErrorListener(error => errors.push(error));
  const local = await f.manager.createLocalCameraStream();
  for (const generating of [false, true]) {
    if (generating) await f.manager.startGeneration(local, new f.Context('test'));
    const state = f.manager.currentState, calls = JSON.stringify(f.calls);
    for (const source of ['missing.png', new ArrayBuffer(0), new Uint8Array(0), {}]) {
      await assert.rejects(f.manager.createLocalImageStream(source), {
        code: 'INVALID_CONFIGURATION', severity: 'RECOVERABLE',
        message: 'Model x2.0-sla does not support image input'
      });
    }
    await assert.rejects(f.manager.createLocalVideoStream('missing.mp4'), {
      code: 'INVALID_CONFIGURATION', severity: 'RECOVERABLE',
      message: 'Model x2.0-sla does not support video input'
    });
    assert.equal(f.manager.currentState, state);
    assert.equal(f.media.currentTrack, local.videoTrack);
    assert.equal(JSON.stringify(f.calls), calls);
  }
  assert.deepEqual(mediaCalls, []);
  assert.deepEqual(errors, []);
  await f.manager.close();
});

test('x2.0 admits image and video input and forwards optional formats to media preparation', async () => {
  const f = managerFixture('x2.0'), calls = [];
  for (const method of ['createLocalImageStream', 'createLocalVideoStream']) {
    f.media[method] = async (source, format) => {
      calls.push({ method, source, format });
      return new f.MediaStream('local');
    };
    for (const format of [undefined, new f.Format(832, 1472, 20)]) {
      const source = method === 'createLocalImageStream' ? new Uint8Array([1, 2]) : 'source.mp4';
      await f.manager[method](source, format);
      assert.deepEqual(calls.at(-1), { method, source, format });
    }
  }
  assert.equal(calls.length, 4);
  assert.deepEqual(f.calls.sessions, []);
});

test('public volume APIs validate finite normalized values before touching playback', async () => {
  const f = managerFixture(), errors = [];
  f.manager.setErrorListener(error => errors.push(error));
  for (const volume of [-0.01, 1.01, NaN, Infinity, -Infinity]) {
    for (const method of ['setLocalAudioVolume', 'setRemoteAudioVolume']) {
      await assert.rejects(f.manager[method](volume), {
        code: 'INVALID_CONFIGURATION', severity: 'RECOVERABLE'
      });
    }
  }
  assert.equal(f.media.volume, undefined);
  assert.equal(f.stream.volume, undefined);
  for (const volume of [0, 0.45, 1]) {
    await f.manager.setLocalAudioVolume(volume);
    await f.manager.setRemoteAudioVolume(volume);
    assert.equal(f.media.volume, volume);
    assert.equal(f.stream.volume, volume);
  }
  assert.deepEqual(errors, []);
  assert.equal(f.calls.sessions.length, 0);
});

test('volume failures retain their error code and remain recoverable during generation', async () => {
  const f = managerFixture(), errors = [];
  const local = await f.create();
  await f.manager.startGeneration(local, new f.Context('generate'));
  f.manager.setErrorListener(error => errors.push(error));
  f.media.setLocalAudioVolume = async () => { throw new f.XmaxError(f.Code.MEDIA_ERROR, 'local failed'); };
  f.stream.setRemoteAudioVolume = () => { throw new f.XmaxError(f.Code.RTC_ERROR, 'remote failed'); };
  await assert.rejects(f.manager.setLocalAudioVolume(0.6), {
    code: 'MEDIA_ERROR', message: 'local failed', severity: 'RECOVERABLE'
  });
  await assert.rejects(f.manager.setRemoteAudioVolume(0.6), {
    code: 'RTC_ERROR', message: 'remote failed', severity: 'RECOVERABLE'
  });
  assert.deepEqual(errors, []);
  assert.equal(f.manager.currentState.connectionState, f.State.GENERATING);
});

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

test('stop while connecting returns immediately and one-call generation continues like iOS', async () => {
  const f = managerFixture(), local = await f.create(), gate = f.holdSession();
  const pending = outcome(f.manager.startGeneration(local, new f.Context('test')));
  assert.equal(f.calls.audio.at(-1), false);
  const audio = [...f.calls.audio], stops = [...f.calls.stops];
  const stopping = f.manager.stopGeneration();
  let stopped = false;
  stopping.then(() => { stopped = true; });
  await settle();
  assert.equal(stopped, true);
  assert.equal(f.manager.currentState.connectionState, f.State.CONNECTING);
  assert.deepEqual(f.calls.audio, audio);
  assert.deepEqual(f.calls.stops, stops);
  assert.equal(f.calls.starts.length, 0);
  gate.resolve();
  assert.ok((await pending).value.videoTrack);
  assert.equal(f.calls.starts.length, 1);
  assert.equal(f.calls.audio.at(-1), false);
  assert.equal(f.manager.currentState.connectionState, f.State.GENERATING);
});

test('stop from the synchronous CONNECTING listener does not cancel one-call generation', async () => {
  const f = managerFixture(), local = await f.create();
  f.manager.setStateListener(state => {
    if (state.connectionState === f.State.CONNECTING) void f.manager.stopGeneration();
  });
  const remote = await f.manager.startGeneration(local, new f.Context('test'));
  assert.ok(remote.videoTrack);
  assert.equal(f.calls.starts.length, 1);
  assert.equal(f.manager.currentState.connectionState, f.State.GENERATING);
});

test('stop from the CONNECTED listener cancels automatic generation while retaining the connection', async () => {
  const f = managerFixture(), local = await f.create();
  f.manager.setStateListener(state => {
    if (state.connectionState === f.State.CONNECTED) void f.manager.stopGeneration();
  });
  await assert.rejects(f.manager.startGeneration(local, new f.Context('test')), { code: 'CANCELLED' });
  assert.equal(f.calls.starts.length, 0);
  assert.deepEqual(f.calls.closed, []);
  assert.equal(f.calls.audio.at(-1), true);
  assert.equal(f.manager.currentState.connectionState, f.State.CONNECTED);
});

test('close during connection rolls back the late session without reopening audio or generation', async () => {
  const f = managerFixture(), local = await f.create(), gate = f.holdSession();
  const pending = outcome(f.manager.startGeneration(local, new f.Context('test')));
  const closing = f.manager.close();
  let closed = false;
  closing.then(() => { closed = true; });
  await settle();
  assert.equal(closed, false);
  const audioCount = f.calls.audio.length;
  gate.resolve();
  await closing;
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
  const stopping = f.manager.stopGeneration();
  await assert.rejects(f.manager.startGeneration(local, new f.Context('too soon')),
    { code: 'INVALID_CONFIGURATION' });
  await stopping;
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

test('close upgrades a pending stop on an established connection and releases local media', async () => {
  const f = managerFixture(), local = await f.create();
  await f.manager.connect(local);
  f.holdGeneration();
  const running = outcome(f.manager.startGeneration(new f.Context('test')));
  const stopping = f.manager.stopGeneration();
  const closing = f.manager.close();
  assert.equal(stopping, closing);
  assert.equal(f.calls.audio.at(-1), false);
  await closing;
  assert.equal((await running).error.code, f.Code.CANCELLED);
  assert.deepEqual(f.calls.closed, ['session-1']);
  assert.equal(f.stream.currentGenerationTaskId, '');
  assert.equal(f.media.currentTrack, null);
  assert.equal(f.manager.currentState.connectionState, f.State.DISCONNECTED);
});

test('disconnect still cancels one-call connection after stopGeneration returns without action', async () => {
  const f = managerFixture(), local = await f.create(), gate = f.holdSession();
  const running = outcome(f.manager.startGeneration(local, new f.Context('test')));
  await f.manager.stopGeneration();
  const disconnecting = f.manager.disconnect();
  let disconnected = false;
  disconnecting.then(() => { disconnected = true; });
  const audio = [...f.calls.audio];
  await f.manager.stopGeneration(); // DISCONNECTING is also a no-op.
  await settle();
  assert.equal(disconnected, false);
  assert.deepEqual(f.calls.audio, audio);
  assert.equal(f.manager.currentState.connectionState, f.State.DISCONNECTING);
  gate.resolve();
  await disconnecting;
  assert.equal((await running).error.code, f.Code.CANCELLED);
  assert.deepEqual(f.calls.closed, ['session-1']);
  assert.equal(f.calls.starts.length, 0);
  assert.ok(f.media.currentTrack);
  assert.equal(f.calls.audio.at(-1), true);
  assert.equal(f.manager.currentState.connectionState, f.State.DISCONNECTED);
});

test('connection failure after a no-op generation stop reports the original error', async () => {
  const f = managerFixture(), local = await f.create(), gate = f.holdSession();
  const error = new f.XmaxError(f.Code.NETWORK_ERROR, 'session request failed');
  const running = outcome(f.manager.startGeneration(local, new f.Context('test')));
  await f.manager.stopGeneration();
  gate.reject(error);
  assert.equal((await running).error, error);
  assert.equal(f.manager.currentState.connectionState, f.State.ERROR);
  assert.equal(f.calls.starts.length, 0);
  assert.equal(f.calls.audio.at(-1), true);
});

test('stop is a no-op outside CONNECTED and GENERATING, including ERROR with a retained session', async () => {
  const f = managerFixture(), local = await f.create();
  await f.manager.stopGeneration();
  assert.equal(f.manager.currentState.connectionState, f.State.IDLE);
  assert.deepEqual(f.calls.audio, []);
  assert.deepEqual(f.calls.stops, []);
  await f.manager.connect(local);
  f.holdGeneration();
  const running = outcome(f.manager.startGeneration(new f.Context('test')));
  const failure = new f.XmaxError(f.Code.TIMEOUT, 'generation confirmation timed out');
  f.calls.starts.at(-1).gate.reject(failure);
  assert.equal((await running).error, failure);
  assert.equal(f.manager.currentState.connectionState, f.State.ERROR);
  assert.deepEqual(f.calls.closed, []);
  const stops = [...f.calls.stops], audio = [...f.calls.audio];
  await f.manager.stopGeneration();
  assert.equal(f.manager.currentState.connectionState, f.State.ERROR);
  assert.deepEqual(f.calls.stops, stops);
  assert.deepEqual(f.calls.audio, audio);
  await f.manager.disconnect();
  const disconnectedStops = [...f.calls.stops], disconnectedAudio = [...f.calls.audio];
  await f.manager.stopGeneration();
  assert.equal(f.manager.currentState.connectionState, f.State.DISCONNECTED);
  assert.deepEqual(f.calls.stops, disconnectedStops);
  assert.deepEqual(f.calls.audio, disconnectedAudio);
});

test('heartbeat failure cancels startup, closes the session and only then notifies the fatal listener', async () => {
  const f = managerFixture(), local = await f.create(), received = [];
  await f.manager.connect(local);
  f.holdGeneration();
  const running = outcome(f.manager.startGeneration(new f.Context('test')));
  f.manager.setErrorListener(error => received.push({ error,
    state: f.manager.currentState.connectionState,
    closed: [...f.calls.closed], task: f.stream.currentGenerationTaskId
  }));
  const failure = new f.XmaxError(f.Code.SESSION_ERROR, 'heartbeat failed', 1004, 503);
  await f.api.heartbeat(failure);
  assert.equal((await running).error, failure);
  assert.deepEqual(received, [{ error: failure, state: f.State.ERROR, closed: ['session-1'], task: '' }]);
  assert.notEqual(f.media.currentTrack, null);
});

test('stop-signal failure is logged without a fatal callback and preserves the connected preview', async () => {
  const f = managerFixture(), local = await f.create(), errors = [];
  await f.manager.startGeneration(local, new f.Context('test'));
  f.manager.setErrorListener(error => errors.push(error));
  const stop = f.stream.stopGeneration.bind(f.stream);
  f.stream.stopGeneration = task => {
    stop(task);
    throw new f.XmaxError(f.Code.RTC_ERROR, 'stop signal failed');
  };
  await f.manager.stopGeneration();
  assert.deepEqual(errors, []);
  assert.equal(f.stream.currentGenerationTaskId, '');
  assert.equal(f.manager.currentState.connectionState, f.State.CONNECTED);
  assert.equal(f.calls.audio.at(-1), true);
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
  }, { setVideoEncoderConfig() {} }, new (load('service/media/MediaService.ets').MediaService)(
    load('core/realtime/RealtimeModel.ets').RealtimeModels.realtime('x2.0-sla')));
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

function exampleFixture(modelName = 'x2.0-sla') {
  const f = managerFixture(modelName);
  let nextManager = f.manager;
  const load = loadEts({ ...platform,
    '@kit.PerformanceAnalysisKit': { hilog: { error() {} } },
    '@xmax/sdk': {
      CameraPosition: { FRONT: 'front' }, RealtimeConnectionState: f.State,
      RealtimeContext: f.Context, RealtimeMediaStream: f.MediaStream, RealtimeVideoFormat: f.Format,
      XmaxLoggerOption: { ALL: 3 },
      RealtimeConfiguration: class {}, RealtimeModels: { realtime() {} }, XmaxConfiguration: class {},
      XmaxClient: class { createRealtimeManager() { return nextManager; } }
    },
    XLabConfiguration: { XLabConfiguration: { currentApiKey: () => 'test-only' } },
    XLabModelSelection: { XLabModelSelection: { current: () => 'x2.0-sla' } },
    ReferenceDataSource: { ReferenceDataSource: { categories: () => [] } }
  }, { Observed: value => value });
  const path = require('node:path');
  const { RealtimeViewModel } = load(path.resolve(__dirname,
    '../examples/XLab/entry/src/main/ets/modules/xlrealtime/mvvm/viewmodel/RealtimeViewModel.ets'));
  return { ...f, viewModel: new RealtimeViewModel([]),
    useManager(manager) { nextManager = manager; }
  };
}

test('XLab uses model camera defaults for both models without an interpolation size override', async () => {
  for (const [name, width, height, fps] of [['x2.0', 832, 1472, 24], ['x2.0-sla', 1024, 1920, 30]]) {
    const f = exampleFixture(name);
    await f.viewModel.connect({});
    await settle();
    assert.deepEqual(f.viewModel.state.localVideoTrack.videoFormat, new f.Format(width, height, fps));
    assert.deepEqual(f.calls.sessions, []);
    await f.viewModel.suspend();
  }
});

test('XLab applies remembered volumes before local playback and restores both after mute', async () => {
  const f = exampleFixture(), vm = f.viewModel;
  assert.equal(vm.state.localAudioVolume, 0.45);
  assert.equal(vm.state.remoteAudioVolume, 1);
  await vm.setLocalAudioVolume(0.3);
  await vm.setRemoteAudioVolume(0.8);
  const create = f.media.createLocalCameraStream.bind(f.media);
  f.media.createLocalCameraStream = async (...args) => {
    assert.equal(f.media.volume, 0.3);
    assert.equal(f.stream.volume, 0.8);
    return create(...args);
  };
  await vm.connect({});
  await vm.setAudioMuted(true);
  assert.equal(f.media.volume, 0);
  assert.equal(f.stream.volume, 0);
  assert.equal(vm.state.localAudioVolume, 0.3);
  assert.equal(vm.state.remoteAudioVolume, 0.8);
  await vm.setAudioMuted(false);
  assert.equal(f.media.volume, 0.3);
  assert.equal(f.stream.volume, 0.8);
});

test('either XLab slider unmutes both channels and restores the other remembered volume', async () => {
  const f = exampleFixture(), vm = f.viewModel;
  await vm.connect({});
  await vm.setAudioMuted(true);
  await vm.setLocalAudioVolume(0.2);
  assert.equal(vm.state.isAudioMuted, false);
  assert.equal(f.media.volume, 0.2);
  assert.equal(f.stream.volume, 1);
  await vm.setAudioMuted(true);
  await vm.setRemoteAudioVolume(0.7);
  assert.equal(vm.state.isAudioMuted, false);
  assert.equal(f.media.volume, 0.2);
  assert.equal(f.stream.volume, 0.7);
});

test('XLab volume errors show a toast without covering or stopping generation', async () => {
  const f = exampleFixture(), messages = [], vm = f.viewModel;
  await vm.connect({});
  vm.onMessage = message => messages.push(message);
  f.stream.setRemoteAudioVolume = () => { throw new Error('volume failed'); };
  await vm.setRemoteAudioVolume(0.6);
  assert.deepEqual(messages, ['volume failed']);
  assert.equal(vm.state.errorMessage, '');
  assert.ok(vm.state.localVideoTrack);
});

test('XLab restores mute and slider values when recreating its manager after suspension', async () => {
  const f = exampleFixture(), next = managerFixture(), vm = f.viewModel;
  await vm.connect({});
  await vm.setLocalAudioVolume(0.2);
  await vm.setRemoteAudioVolume(0.7);
  await vm.setAudioMuted(true);
  await vm.suspend();
  f.useManager(next.manager);
  const create = next.media.createLocalCameraStream.bind(next.media);
  next.media.createLocalCameraStream = async (...args) => {
    assert.equal(next.media.volume, 0);
    assert.equal(next.stream.volume, 0);
    return create(...args);
  };
  await vm.resume({});
  assert.ok(vm.state.localVideoTrack);
  assert.equal(vm.state.isAudioMuted, true);
  assert.equal(vm.state.localAudioVolume, 0.2);
  assert.equal(vm.state.remoteAudioVolume, 0.7);
  await vm.setAudioMuted(false);
  assert.equal(next.media.volume, 0.2);
  assert.equal(next.stream.volume, 0.7);
});

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
  assert.equal(f.manager.currentState.connectionState, f.State.DISCONNECTING);
  gate.resolve();
  await settle();
  assert.equal(f.calls.starts.length, 0);
  assert.equal(f.viewModel.state.remoteVideoTrack, null);
  assert.equal(f.viewModel.state.isGenerationStarting, false);
  assert.equal(f.viewModel.state.errorMessage, '');
  assert.ok(f.viewModel.state.localVideoTrack);
  assert.equal(f.manager.currentState.connectionState, f.State.DISCONNECTED);
  assert.deepEqual(f.calls.closed, ['session-1']);
});

test('XLab replaces input during connection by closing the old session and generating only the latest prompt', async () => {
  const f = exampleFixture(), gate = f.holdSession();
  await f.viewModel.connect({});
  await settle();
  f.viewModel.state.selectedCategoryId = 'free';
  f.viewModel.submitPrompt('old prompt');
  await settle();
  assert.equal(f.manager.currentState.connectionState, f.State.CONNECTING);
  f.viewModel.submitPrompt('new prompt');
  assert.equal(f.manager.currentState.connectionState, f.State.DISCONNECTING);
  f.viewModel.submitPrompt('latest prompt');
  gate.resolve();
  await settle();
  await settle();
  assert.deepEqual(f.calls.closed, ['session-1']);
  assert.equal(f.calls.sessions.length, 2);
  assert.equal(f.calls.starts.length, 1);
  assert.equal(f.calls.starts[0].context.prompt, 'latest prompt');
  assert.equal(f.manager.currentState.connectionState, f.State.GENERATING);
  assert.ok(f.viewModel.state.remoteVideoTrack);
  assert.ok(f.viewModel.state.localVideoTrack);
  assert.equal(f.viewModel.state.errorMessage, '');
});

test('XLab cancellation after connecting retains the session and local preview', async () => {
  const f = exampleFixture();
  await f.viewModel.connect({});
  await settle();
  f.holdGeneration();
  f.viewModel.state.selectedCategoryId = 'mox';
  f.viewModel.startMoxGeneration();
  await settle();
  assert.equal(f.manager.currentState.connectionState, f.State.CONNECTED);
  assert.equal(f.calls.starts.length, 1);
  f.viewModel.cancelGeneration();
  await settle();
  assert.equal(f.manager.currentState.connectionState, f.State.CONNECTED);
  assert.deepEqual(f.calls.closed, []);
  assert.equal(f.stream.currentGenerationTaskId, '');
  assert.equal(f.viewModel.state.remoteVideoTrack, null);
  assert.ok(f.viewModel.state.localVideoTrack);
  assert.equal(f.viewModel.state.errorMessage, '');
});
