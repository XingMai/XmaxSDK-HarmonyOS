const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { loadEts } = require('./ets-loader.cjs');

const sdkVersion = JSON.parse(fs.readFileSync(
  path.join(__dirname, '../xmax_sdk/oh-package.json5'), 'utf8')).version;
const expectedRuntime = {
  platform: 'harmonyos', os_version: '5.1.0', sdk_version: sdkVersion, device_model: 'Test model'
};

function fixture({ device = { distributionOSVersion: ' 5.1.0 ', productModel: ' Test model ' },
  uuid = randomUUID, extra = {}, globals = {} } = {}) {
  const requests = [];
  let destroyed = 0;
  const load = loadEts({
    '@ohos.systemDateTime': { default: { TimeType: { ACTIVE: 0 }, getUptime: () => 0 } },
    '@kit.BasicServicesKit': { deviceInfo: device },
    '@kit.ArkTS': { util: {
      generateRandomUUID: () => uuid(),
      Base64Helper: class { encodeToStringSync(bytes) { return Buffer.from(bytes).toString('base64'); } },
      TextEncoder: class { encodeInto(value) { return new Uint8Array(Buffer.from(value)); } }
    } },
    '@kit.NetworkKit': { http: {
      RequestMethod: { GET: 'GET', POST: 'POST', PUT: 'PUT', DELETE: 'DELETE' },
      HttpDataType: { STRING: 'STRING' },
      createHttp: () => ({
        async request(url, options) {
          requests.push({ url, options });
          return { responseCode: 200, result: JSON.stringify({ success: true, data: { ok: true } }) };
        },
        destroy() { destroyed++; }
      })
    } },
    ApiLogger: { ApiLogger: { logResponse() {}, logFailure() {} } },
    XmaxLogger: { XmaxLogger: { debug() {}, error() {} } },
    ...extra
  }, globals);
  const { RuntimeInfo } = load('foundation/runtime/RuntimeInfo.ets');
  const { RoomEvent } = load('stream/room/RoomEvent.ets');
  const { RealtimeVideoFormat } = load('service/realtime/RealtimeVideoFormat.ets');
  const { RealtimeContext: Context } = load('service/realtime/RealtimeContext.ets');
  return { load, RuntimeInfo, RoomEvent, Context, requests, get destroyed() { return destroyed; },
    format: new RealtimeVideoFormat(1024, 1920, 30) };
}

test('runtime is a lazy shared snapshot; SDK version matches the HAR package', () => {
  const reads = { os: 0, model: 0 };
  const f = fixture({ device: {
    get distributionOSVersion() { reads.os++; return ' 5.1.0 '; },
    get osFullName() { throw new Error('fallback must not be read'); },
    get productModel() { reads.model++; return ' Test model '; }
  } });
  assert.deepEqual(reads, { os: 0, model: 0 });
  const runtime = f.RuntimeInfo.current;
  assert.deepEqual(runtime.toPayload(), expectedRuntime);
  assert.equal(f.RuntimeInfo.current, runtime);
  assert.deepEqual(JSON.parse(f.RoomEvent.heartbeat('user')).runtime, expectedRuntime);
  assert.deepEqual(reads, { os: 1, model: 1 });
  const { XMAX_SDK_VERSION } = f.load('foundation/runtime/SDKVersion.ets');
  assert.equal(XMAX_SDK_VERSION, sdkVersion);
});

test('OS information falls back to the full OS name if distribution information is blank or throws', () => {
  for (const distribution of [() => ' \n ', () => { throw new Error('unavailable'); }]) {
    const f = fixture({ device: {
      get distributionOSVersion() { return distribution(); },
      osFullName: ' HarmonyOS 5.1.0 ', productModel: ' Phone '
    } });
    assert.deepEqual(f.RuntimeInfo.current.toPayload(), {
      ...expectedRuntime, os_version: 'HarmonyOS 5.1.0', device_model: 'Phone'
    });
  }
});

test('all room events include the same top-level runtime and preserve SLA size and business fields', () => {
  const f = fixture(), task = 'task-test?os=harmonyos', user = 'user';
  const context = new f.Context('prompt', 'reference.png');
  const params = { model: 'default', size: [1024, 1920], prompt: 'prompt', ref_image_path: 'reference.png' };
  const cases = [
    [f.RoomEvent.start(user, task, f.format, context), { event: 'start', params, user_id: user, uid: task }],
    [f.RoomEvent.changeCondition(user, task, f.format, context),
      { event: 'change_condition', params, user_id: user, uid: task }],
    [f.RoomEvent.stop(user, task), { event: 'stop', user_id: user, uid: task }],
    [f.RoomEvent.tracks(user, task, [{ x: 10, y: 20 }, { x: 1023, y: 1919 }]),
      { event: 'tracks', tracks: [[10, 20], [1023, 1919]], user_id: user, uid: task }],
    [f.RoomEvent.heartbeat(user), { event: 'heartbeat', user_id: user }]
  ];
  for (const [json, payload] of cases) {
    assert.deepEqual(JSON.parse(json), { ...payload, runtime: expectedRuntime });
  }
  const noReference = JSON.parse(f.RoomEvent.start(user, task, f.format, new f.Context('prompt')));
  assert.equal(Object.hasOwn(noReference.params, 'ref_image_path'), false);
});

test('GET, POST, PUT and DELETE headers match room runtime without changing API bodies', async () => {
  const device = { distributionOSVersion: '5.1.0', productModel: 'Test model' };
  const f = fixture({ device });
  const firstRuntime = JSON.parse(f.RoomEvent.heartbeat('user')).runtime;
  device.distributionOSVersion = 'changed'; device.productModel = 'changed';
  const { ApiService } = f.load('service/network/ApiService.ets');
  const api = new ApiService('test-key', 'https://cloud.xmax.22duck.cn/open/api/v1');
  const body = { model: 'x2.0-sla', size: [1024, 1920] };
  assert.deepEqual(await api.get('/sessions'), { ok: true });
  await api.post('/sessions', body);
  await api.put('/sessions/id', body);
  await api.delete('/sessions/id');
  assert.equal(f.destroyed, 4);
  assert.deepEqual(f.requests.map(r => r.options.method), ['GET', 'POST', 'PUT', 'DELETE']);
  for (const { url, options } of f.requests) {
    assert.ok(url.startsWith('https://cloud.xmax.22duck.cn/open/api/v1/sessions'));
    assert.deepEqual(options.header, {
      Accept: 'application/json', 'Content-Type': 'application/json', 'X-Api-Key': 'test-key',
      'X-Platform': firstRuntime.platform, 'X-OS-Version': firstRuntime.os_version,
      'X-SDK-Version': firstRuntime.sdk_version, 'X-Device-Model': firstRuntime.device_model
    });
    assert.equal(options.extraData, ['POST', 'PUT'].includes(options.method) ? JSON.stringify(body) : undefined);
  }
  assert.deepEqual(firstRuntime, expectedRuntime);
  assert.deepEqual(body, { model: 'x2.0-sla', size: [1024, 1920] });
});

test('unavailable device properties do not prevent API requests or room events', async () => {
  for (const device of [{}, { distributionOSVersion: ' ', osFullName: ' ', productModel: ' ' }, {
    get distributionOSVersion() { throw new Error('unavailable'); },
    get osFullName() { throw new Error('unavailable'); },
    get productModel() { throw new Error('unavailable'); }
  }]) {
    const f = fixture({ device });
    const { ApiService } = f.load('service/network/ApiService.ets');
    await new ApiService('test-key', 'https://cloud.xmax.22duck.cn/open/api/v1').get('/sessions');
    const runtime = JSON.parse(f.RoomEvent.heartbeat('user')).runtime;
    assert.deepEqual(runtime, { ...expectedRuntime, os_version: 'unknown', device_model: 'unknown' });
    assert.equal(f.requests[0].options.header['X-OS-Version'], 'unknown');
    assert.equal(f.requests[0].options.header['X-Device-Model'], 'unknown');
  }
});

test('task IDs encode all 16 UUID bytes using unpadded Base64URL and the runtime platform', async () => {
  const uuids = ['00112233-4455-4677-8899-aabbccddeeff', 'ffffffff-ffff-4fff-bfff-ffffffffffff',
    'fbefbefb-efbe-4bef-befb-efbefbefbefb', ...Array.from({ length: 20 }, randomUUID)];
  let next = 0;
  const f = fixture({ uuid: () => uuids[next++] });
  const { XmaxRealtimeGenerationManager } = f.load('core/realtime/XmaxRealtimeGenerationManager.ets');
  const starts = [], mediaStarts = [];
  const manager = new XmaxRealtimeGenerationManager({ start: task => mediaStarts.push(task) }, {
    async beginGeneration(task) { starts.push(task); }
  });
  for (const uuid of uuids) {
    const id = await manager.start(f.format, new f.Context('prompt'), () => {});
    const bytes = Buffer.from(uuid.replaceAll('-', ''), 'hex');
    assert.equal(id, `task-${bytes.toString('base64url')}?os=${f.RuntimeInfo.current.platform}`);
    assert.match(id, /^task-[A-Za-z0-9_-]{22}\?os=harmonyos$/);
    assert.deepEqual(Buffer.from(id.slice('task-'.length, id.indexOf('?')), 'base64url'), bytes);
  }
  assert.equal(new Set(starts).size, uuids.length);
  assert.deepEqual(starts, mediaStarts);
});

test('signaling uses the task ID while outgoing frame SEI appends a consecutive frame index', async () => {
  const timers = new Map();
  let timerId = 0;
  const f = fixture({
    extra: {
      RoomHeartbeat: { RoomHeartbeat: class { start() {} stop() {} } },
      EncodingController: { EncodingController: class {} },
      QualityController: { QualityController: class {} }
    },
    globals: {
      setTimeout: (callback, ms) => { timers.set(++timerId, { callback, ms }); return timerId; },
      clearTimeout: id => timers.delete(id)
    }
  });
  const messages = [], frames = [], remoteStreams = [], mediaStarts = [], mediaFormats = [];
  const rtc = {
    setEventListener() {}, async joinRoom() {}, async leaveRoom() {},
    publishLocalVideo() {}, unpublishLocalVideo() {}, unpublishLocalAudio() {},
    sendRoomMessage: text => messages.push(JSON.parse(text)),
    pushExternalVideoFrame: (frame, sei) => frames.push({ frame, sei })
  };
  const { StreamController } = f.load('stream/StreamController.ets');
  const { XmaxRealtimeGenerationManager } = f.load('core/realtime/XmaxRealtimeGenerationManager.ets');
  const stream = new StreamController(rtc, remote => remoteStreams.push(remote));
  const manager = new XmaxRealtimeGenerationManager({
    start: (id, format) => { mediaStarts.push(id); mediaFormats.push(format); }, stop() {}
  }, stream);
  await stream.connect({ roomId: 'room', userId: 'user', token: 'test', botName: 'bot' }, false, () => {});
  const frame = { id: 'frame' };
  stream.pushLocalVideoFrame(frame);
  assert.equal(frames.at(-1).sei, undefined);
  const starting = manager.start(f.format, new f.Context('prompt'), () => {});
  try {
    const task = messages[0].uid;
    assert.match(task, /^task-[A-Za-z0-9_-]{22}\?os=harmonyos$/);
    assert.deepEqual(messages[0].runtime, expectedRuntime);
    stream.pushLocalVideoFrame(frame);
    stream.pushLocalVideoFrame(frame);
    assert.equal(Buffer.from(frames.at(-2).sei).toString('utf8'), `${task}&index=0`);
    assert.equal(Buffer.from(frames.at(-1).sei).toString('utf8'), `${task}&index=1`);
    const remote = { roomId: 'room', userId: 'bot' };
    const baseTask = task.split('?')[0];
    for (const message of ['', '?os=harmonyos', `${baseTask}-other?os=harmonyos&index=0`,
      `${baseTask.slice(0, -1)}?os=harmonyos&index=0`, `task-other?os=harmonyos&index=0`]) {
      stream.onSeiMessageReceived(remote, message);
    }
    stream.onSeiMessageReceived({ roomId: 'other-room', userId: 'bot' }, task);
    stream.onSeiMessageReceived({ roomId: 'room', userId: 'other-bot' }, task);
    assert.deepEqual(remoteStreams, []);
    assert.deepEqual([...timers.values()].map(t => t.ms), [30000]);
    const landscape = { width: f.format.height, height: f.format.width, fps: f.format.fps };
    manager.updateVideoFormat(landscape);
    assert.deepEqual(messages.at(-1).params.size, [landscape.width, landscape.height]);
    assert.equal(messages.at(-1).params.prompt, 'prompt');
    assert.deepEqual(mediaStarts, []);
    stream.onSeiMessageReceived(remote, `${baseTask}?index=12&os=ios`);
    assert.deepEqual(remoteStreams, [remote]);
    assert.equal(timers.size, 0); // SEI confirmation has no artificial delay.
    assert.equal(await starting, task);
    assert.deepEqual(mediaStarts, [task]);
    assert.deepEqual(mediaFormats.at(-1), landscape);
    manager.update(task, f.format, new f.Context('changed'));
    manager.updateVideoFormat(landscape);
    assert.equal(messages.at(-1).params.prompt, 'changed');
    assert.deepEqual(messages.at(-1).params.size, [landscape.width, landscape.height]);
    stream.pushLocalVideoFrame(frame);
    assert.equal(Buffer.from(frames.at(-1).sei).toString('utf8'), `${task}&index=2`);
    stream.sendTracks(task, [{ x: 10, y: 20 }]);
    manager.stop(task);
    assert.deepEqual(messages.map(message => message.event), ['start', 'change_condition', 'change_condition', 'change_condition', 'tracks', 'stop']);
    for (const message of messages) {
      assert.equal(message.uid, task);
      assert.deepEqual(message.runtime, expectedRuntime);
    }
    stream.pushLocalVideoFrame(frame);
    assert.equal(frames.at(-1).sei, undefined);
    assert.equal(timers.size, 0);

    const restarting = manager.start(f.format, new f.Context('next'), () => {});
    restarting.catch(() => {});
    const nextTask = messages.at(-1).uid;
    assert.notEqual(nextTask, task);
    stream.pushLocalVideoFrame(frame);
    assert.equal(Buffer.from(frames.at(-1).sei).toString('utf8'), `${nextTask}&index=0`);
    stream.onSeiMessageReceived(remote, `${task}&index=2`);
    assert.equal(remoteStreams.filter(Boolean).length, 1); // Previous task cannot confirm this generation.
    stream.onSeiMessageReceived(remote, nextTask.split('?')[0]); // Bare task identity is also accepted.
    assert.equal(await restarting, nextTask);
    assert.equal(remoteStreams.filter(Boolean).length, 2);
    assert.equal(timers.size, 0);
    manager.stop(nextTask);
  } finally {
    await stream.disconnect();
    await starting.catch(() => {});
  }
});
