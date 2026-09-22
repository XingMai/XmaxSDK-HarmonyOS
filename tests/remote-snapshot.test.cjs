const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

function pixelMap() {
  return { releases: 0, async release() { this.releases++; } };
}

async function rtcFixture() {
  const handlers = new Map(), timers = new Map();
  let nextTask = 0, nextTimer = 0;
  const engine = {
    on(name, handler) { handlers.set(name, handler); },
    off(name) { handlers.delete(name); },
    takeRemoteSnapshot() { return ++nextTask; }
  };
  const load = loadEts({
    '@bytertc/volcenginertc': { MirrorType: { kMirrorTypeNone: 0 }, StreamIndex: { kStreamIndexMain: 0 } },
    '@kit.ArkTS': {},
    RtcEngineManager: { RtcEngineManager: {
      async acquire() { return { engine }; }, async release() {}
    } },
    RtcQualityConverter: {}, RtcStatsLogger: {}, RtcVideoConverter: {},
    XmaxLogger: { XmaxLogger: { error() {} } }
  }, {
    setTimeout(fn) { timers.set(++nextTimer, fn); return nextTimer; },
    clearTimeout(id) { timers.delete(id); }
  });
  const { RtcManager } = load('foundation/rtc/RtcManager.ets');
  const { RemoteStream } = load('foundation/rtc/RemoteStream.ets');
  const rtc = new RtcManager({}), stream = new RemoteStream('room', 'bot');
  const key = { room_id: 'room', user_id: 'bot', stream_index: 0 };
  await rtc.initialize();
  rtc.activeRoomId = 'room';
  rtc.remoteStreamKeys.set(stream.key(), key);
  return { rtc, stream, key, engine, timers, handlers };
}

test('native snapshot resolves matching task and transfers PixelMap ownership', async () => {
  const f = await rtcFixture(), result = pixelMap();
  const pending = f.rtc.takeRemoteSnapshot(f.stream);
  const callback = f.handlers.get('onTakeRemoteSnapshotResult');
  const wrongStream = pixelMap();
  callback(1, { ...f.key, user_id: 'other' }, wrongStream, 0);
  assert.equal(wrongStream.releases, 1);
  assert.equal(f.timers.size, 1);
  callback(1, f.key, result, 0);
  assert.equal(await pending, result);
  assert.equal(result.releases, 0);
  assert.equal(f.timers.size, 0);
  await result.release();
  await f.rtc.destroy();
  assert.equal(f.handlers.has('onTakeRemoteSnapshotResult'), false);
});

test('native snapshot handles vendor rejection, callback error and timeout without leaking late images', async () => {
  const f = await rtcFixture(), take = f.engine.takeRemoteSnapshot;
  f.engine.takeRemoteSnapshot = () => -1;
  await assert.rejects(f.rtc.takeRemoteSnapshot(f.stream), { code: 'RTC_ERROR' });
  assert.equal(f.timers.size, 0);
  f.engine.takeRemoteSnapshot = take;
  const bad = pixelMap(), failed = f.rtc.takeRemoteSnapshot(f.stream);
  f.handlers.get('onTakeRemoteSnapshotResult')(1, f.key, bad, -1);
  await assert.rejects(failed, { code: 'RTC_ERROR' });
  assert.equal(bad.releases, 1);
  const timedOut = f.rtc.takeRemoteSnapshot(f.stream);
  [...f.timers.values()][0]();
  await assert.rejects(timedOut, { code: 'TIMEOUT' });
  const late = pixelMap();
  f.handlers.get('onTakeRemoteSnapshotResult')(2, f.key, late, 0);
  assert.equal(late.releases, 1);
  await f.rtc.destroy();
});

test('leaving RTC cancels pending snapshots and ignores a stale engine callback', async () => {
  const f = await rtcFixture(), pending = f.rtc.takeRemoteSnapshot(f.stream);
  const callback = f.handlers.get('onTakeRemoteSnapshotResult');
  const rejected = assert.rejects(pending, { code: 'CANCELLED' });
  await f.rtc.destroy();
  await rejected;
  assert.equal(f.timers.size, 0);
  const late = pixelMap();
  callback(1, f.key, late, 0);
  assert.equal(late.releases, 1);
});

function renderFixture() {
  const requests = [], previews = [], logs = [];
  const load = loadEts({
    '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
    XmaxLogger: { XmaxLogger: { error: message => logs.push(message) } }
  });
  const { RenderController } = load('rendering/RenderController.ets');
  const { RemoteStream } = load('foundation/rtc/RemoteStream.ets');
  const render = new RenderController({
    setRemoteVideoFrameListener() {}, setRemoteVideoRenderedListener() {},
    observeRemoteVideoFrames() {}, unbindRemoteVideo() {},
    takeRemoteSnapshot() { const request = deferred(); requests.push(request); return request.promise; }
  });
  render.remoteStream = new RemoteStream('room', 'bot');
  render.remoteBinding = { setVideoReady() {}, setPreviewFrame(frame) { previews.push(frame); } };
  return { render, requests, previews, logs };
}

test('remote freeze displays native PixelMap without copying or converting video planes', async () => {
  const f = renderFixture(), frame = pixelMap();
  const pending = f.render.freezeRemoteVideo();
  f.requests[0].resolve(frame);
  await pending;
  assert.equal(f.previews.at(-1), frame);
  assert.equal(frame.releases, 0);
  f.render.resetRemoteTrack(null);
  assert.equal(frame.releases, 1);
  assert.equal(f.previews.at(-1), undefined);
});

for (const action of ['resume', 'reset', 'replace']) {
  test(`late native snapshot cannot restore an obsolete freeze after ${action}`, async () => {
    const f = renderFixture(), old = pixelMap();
    const pending = f.render.freezeRemoteVideo();
    if (action === 'resume') await f.render.resumeRemoteVideo();
    if (action === 'reset') f.render.resetRemoteTrack(null);
    if (action === 'replace') {
      const newer = f.render.freezeRemoteVideo(), current = pixelMap();
      f.requests[1].resolve(current);
      await newer;
      assert.equal(f.previews.at(-1), current);
    }
    f.requests[0].resolve(old);
    await pending;
    assert.equal(old.releases, 1);
    assert.equal(f.previews.includes(old), false);
    f.render.resetRemoteTrack(null);
  });
}

test('native freeze failure remains nonfatal and does not install a preview overlay', async () => {
  const f = renderFixture(), pending = f.render.freezeRemoteVideo();
  f.requests[0].reject(new Error('snapshot unavailable'));
  await pending;
  assert.equal(f.previews.length, 0);
  assert.equal(f.logs.length, 1);
});
