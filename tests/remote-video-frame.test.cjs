const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

function fixture() {
  const timers = new Map(), logs = [], observations = [], received = [], failures = [];
  let timerId = 0, onFrame, sinkError = null;
  const load = loadEts({
    '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
    '@bytertc/volcenginertc': { VideoPixelFormat: { kVideoPixelFormatI420: 1 } },
    XmaxLogger: { XmaxLogger: { error: message => logs.push(message) } }
  }, {
    setTimeout(callback, ms) { timers.set(++timerId, { callback, ms }); return timerId; },
    clearTimeout(id) { timers.delete(id); }
  });
  const { RtcVideoConverter } = load('foundation/rtc/RtcVideoConverter.ets');
  const { RenderController } = load('rendering/RenderController.ets');
  const { RemoteStream } = load('foundation/rtc/RemoteStream.ets');
  const render = new RenderController({
    setRemoteVideoFrameListener(listener) { onFrame = listener; },
    setRemoteVideoRenderedListener() {}, unbindRemoteVideo() {},
    observeRemoteVideoFrames(stream, enabled) {
      if (enabled && sinkError) throw sinkError;
      observations.push([stream.key(), enabled]);
    }
  }, error => failures.push(error));
  const stream = new RemoteStream('room', 'bot');
  return { load, render, stream, RemoteStream, timers, received, observations, logs, failures,
    convert: raw => RtcVideoConverter.copyRemoteFrame(raw),
    frame: (source = stream, copy = () => RtcVideoConverter.copyRemoteFrame(rawFrame())) => onFrame(source, copy),
    failSink(error) { sinkError = error; },
    flush() {
      const tasks = [...timers].filter(([, timer]) => timer.ms === 0);
      for (const [id, timer] of tasks) { timers.delete(id); timer.callback(); }
    }
  };
}

function rawFrame() {
  return { width: 3, height: 3, rotation: 90, timestamp_us: 123456,
    pixel_format: 1, number_of_planes: 3,
    plane_stride: [4, 3, 3], plane_data: [
      Uint8Array.from([1,2,3,99,4,5,6,99,7,8,9]).buffer,
      Uint8Array.from([10,11,99,12,13]).buffer,
      Uint8Array.from([14,15,99,16,17]).buffer
    ] };
}

test('I420 conversion copies visible rows, preserves timestamps/rotation and owns all planes', () => {
  const f = fixture(), raw = rawFrame(), frame = f.convert(raw);
  assert.equal(frame.width, 3); assert.equal(frame.height, 3);
  assert.equal(frame.pixelFormat, 'i420'); assert.equal(frame.rotation, 90);
  assert.equal(frame.timestampUs, 123456);
  assert.deepEqual(frame.planes.map(p => p.stride), [3, 2, 2]);
  assert.deepEqual(frame.planes.map(p => [...new Uint8Array(p.data)]), [[1,2,3,4,5,6,7,8,9],[10,11,12,13],[14,15,16,17]]);
  raw.plane_data.forEach(data => new Uint8Array(data).fill(0));
  assert.equal(new Uint8Array(frame.planes[0].data)[0], 1);
  const second = f.convert(rawFrame());
  new Uint8Array(frame.planes[1].data).fill(0);
  assert.equal(new Uint8Array(second.planes[1].data)[0], 10);
});

test('I420 conversion rejects malformed planes, geometry, format, time and rotation', () => {
  const f = fixture();
  for (const patch of [{ width: 0 }, { width: 2.5 }, { height: Infinity }, { width: 32769 },
    { pixel_format: 2 }, { number_of_planes: 2 }, { timestamp_us: NaN }, { timestamp_us: -1 },
    { rotation: 45 }, { plane_stride: [2, 3, 3] }, { plane_stride: [NaN, 3, 3] },
    { plane_data: [new ArrayBuffer(10), new ArrayBuffer(5), new ArrayBuffer(5)] },
    { plane_data: [undefined] }]) {
    assert.throws(() => f.convert({ ...rawFrame(), ...patch }), { code: 'RTC_ERROR' });
  }
});

test('no public listener means no pixel copy and observation stops after first-frame readiness', async () => {
  const f = fixture();
  f.render.setRemoteStream(f.stream);
  const ready = f.render.waitUntilRemoteFrameReady();
  let copies = 0;
  f.frame(f.stream, () => { copies++; throw new Error('must not copy'); });
  await ready;
  assert.equal(copies, 0);
  assert.deepEqual(f.observations, [['room:bot', true], ['room:bot', false]]);
  assert.equal(f.timers.size, 0);
});

test('public listening keeps the sink after readiness and delivers every queued frame in receive order', async () => {
  const f = fixture();
  f.render.setRemoteVideoFrameListener(frame => f.received.push(frame.timestampUs));
  f.render.setRemoteStream(f.stream);
  const ready = f.render.waitUntilRemoteFrameReady();
  for (let i = 0; i < 20; i++) f.frame(f.stream, () => f.convert({ ...rawFrame(), timestamp_us: i }));
  await ready;
  assert.deepEqual(f.received, []);
  assert.equal(f.timers.size, 1);
  f.flush();
  assert.deepEqual(f.received, Array.from({ length: 20 }, (_, i) => i));
  assert.equal(f.observations.some(([, enabled]) => !enabled), false);
  f.render.setRemoteVideoFrameListener(null);
  assert.deepEqual(f.observations.at(-1), ['room:bot', false]);
  f.render.setRemoteVideoFrameListener(frame => f.received.push(frame.timestampUs));
  assert.deepEqual(f.observations.at(-1), ['room:bot', true]);
  f.frame(); f.flush();
  assert.deepEqual(f.received, [...Array.from({ length: 20 }, (_, i) => i), 123456]);
  f.render.resetRemoteTrack(null);
});

test('listener removal before readiness does not stop required first-frame observation', async () => {
  const f = fixture();
  f.render.setRemoteVideoFrameListener(() => {});
  f.render.setRemoteStream(f.stream);
  f.render.setRemoteVideoFrameListener(null);
  assert.deepEqual(f.observations, [['room:bot', true]]);
  const ready = f.render.waitUntilRemoteFrameReady();
  f.frame(); await ready;
  assert.deepEqual(f.observations.at(-1), ['room:bot', false]);
});

test('receive order survives repeated timestamps, a throwing callback and frames arriving during delivery', () => {
  const f = fixture();
  f.render.setRemoteVideoFrameListener(frame => {
    f.received.push(frame.timestampUs);
    if (f.received.length === 1) {
      f.frame(f.stream, () => f.convert({ ...rawFrame(), timestamp_us: 7 }));
      throw new Error('first callback failed');
    }
  });
  f.render.setRemoteStream(f.stream);
  for (const timestamp of [9, 8, 8]) {
    f.frame(f.stream, () => f.convert({ ...rawFrame(), timestamp_us: timestamp }));
  }
  assert.deepEqual(f.received, []);
  f.flush();
  assert.deepEqual(f.received, [9, 8, 8]);
  assert.match(f.logs.at(-1), /first callback failed/);
  f.flush();
  assert.deepEqual(f.received, [9, 8, 8, 7]);
  assert.equal(f.timers.size, 0);
  f.render.resetRemoteTrack(null);
});

for (const action of ['replace listener', 'remove listener', 'reset stream', 'stop delivery', 'reset track']) {
  test(`${action} inside the callback invalidates the rest of its batch and any queued follow-up`, () => {
    const f = fixture();
    const next = frame => f.received.push(`new:${frame.timestampUs}`);
    f.render.setRemoteVideoFrameListener(frame => {
      f.received.push(frame.timestampUs);
      f.frame(f.stream, () => f.convert({ ...rawFrame(), timestamp_us: 4 }));
      const staleTimer = [...f.timers.values()][0].callback;
      switch (action) {
        case 'replace listener': f.render.setRemoteVideoFrameListener(next); break;
        case 'remove listener': f.render.setRemoteVideoFrameListener(null); break;
        case 'reset stream': f.render.setRemoteStream(f.stream); break;
        case 'stop delivery': f.render.stopRemoteVideoFrameDelivery(); break;
        case 'reset track': f.render.resetRemoteTrack(null); break;
      }
      f.render.setRemoteVideoFrameListener(next);
      f.render.setRemoteStream(f.stream);
      f.frame(f.stream, () => f.convert({ ...rawFrame(), timestamp_us: 5 }));
      staleTimer(); // An already queued old callback cannot drain or clear the new batch.
    });
    f.render.setRemoteStream(f.stream);
    for (const timestamp of [1, 2, 3]) {
      f.frame(f.stream, () => f.convert({ ...rawFrame(), timestamp_us: timestamp }));
    }
    f.flush();
    assert.deepEqual(f.received, [1]);
    f.flush();
    assert.deepEqual(f.received, [1, 'new:5']);
    assert.equal(f.timers.size, 0);
    f.render.resetRemoteTrack(null);
  });
}

test('replacement, stream reset and stop invalidate pending callbacks, including a reused stream ID', () => {
  const f = fixture();
  f.render.setRemoteVideoFrameListener(() => f.received.push('old'));
  f.render.setRemoteStream(f.stream);
  f.frame();
  const staleTimer = [...f.timers.values()][0].callback;
  f.render.setRemoteVideoFrameListener(() => f.received.push('new'));
  staleTimer(); f.flush();
  assert.deepEqual(f.received, []);
  f.frame();
  f.render.setRemoteStream(f.stream);
  f.flush();
  assert.deepEqual(f.received, []);
  f.frame(new f.RemoteStream('room', 'other'));
  f.flush(); assert.deepEqual(f.received, []);
  f.frame();
  f.render.stopRemoteVideoFrameDelivery();
  f.flush(); f.frame(); f.flush();
  assert.deepEqual(f.received, []);
  f.render.setRemoteStream(f.stream);
  f.frame(); f.flush();
  assert.deepEqual(f.received, ['new']);
  f.frame(); f.render.resetRemoteTrack(null); f.flush();
  assert.deepEqual(f.received, ['new']);
});

test('conversion and consumer failures are contained, and later frames still arrive', () => {
  const f = fixture();
  f.render.setRemoteVideoFrameListener(() => { throw new Error('consumer failed'); });
  f.render.setRemoteStream(f.stream);
  f.frame(f.stream, () => { throw new Error('copy failed'); });
  assert.match(f.logs.at(-1), /copy failed/);
  f.frame(); assert.doesNotThrow(() => f.flush());
  assert.match(f.logs.at(-1), /consumer failed/);
  f.render.setRemoteVideoFrameListener(frame => f.received.push(frame));
  f.frame(); f.flush();
  assert.equal(f.received.length, 1);
  assert.deepEqual(f.failures, []);
  f.render.resetRemoteTrack(null);
});

test('failed sink reactivation preserves listener state and can be retried', () => {
  const f = fixture(); f.render.setRemoteStream(f.stream); f.frame();
  const failure = new Error('sink failed'); f.failSink(failure);
  assert.throws(() => f.render.setRemoteVideoFrameListener(frame => f.received.push(frame)), error => error === failure);
  assert.equal(f.render.frameDispatcher.hasListener, false);
  f.failSink(null);
  f.render.setRemoteVideoFrameListener(frame => f.received.push(frame));
  f.frame(); f.flush(); assert.equal(f.received.length, 1);
  f.render.resetRemoteTrack(null);
});
