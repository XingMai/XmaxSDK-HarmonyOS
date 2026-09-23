const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

function fixture(fps = 30) {
  let now = 0;
  const load = loadEts({
    VideoFileFrameDecoder: {},
    MediaTimeline: { MediaTimeline: { currentTimestampUs: () => now } },
    XmaxLogger: { XmaxLogger: { error() {} } }
  });
  const { VideoSourceController } = load('media/video/VideoSourceController.ets');
  const controller = new VideoSourceController(() => {}, () => {});
  controller.configure('file', 0, 2, 2, fps);
  const check = (timestamp, wall) => {
    now = wall;
    return controller.shouldOutputFrame({ timestampUs: timestamp });
  };
  return { controller, check };
}

test('video selection distinguishes stale drops from frame-rate sampling and resets between loops', () => {
  const { controller, check } = fixture();
  assert.equal(check(0, 10000), true);
  assert.equal(check(10000, 20000), false); // Frame-rate sampling.
  assert.equal(check(33333, 140000), false); // Beyond the bounded latency budget.
  assert.equal(check(133333, 150000), true);
  assert.equal(check(2000000, 2010000), true);
  controller.resetFrameSampling();
  assert.equal(check(0, 0), true);
  assert.equal(check(2000000, 2000000), true);
});

test('continuous 30 fps survives the observed 40–78 ms Surface pipeline delay', () => {
  const { check } = fixture();
  for (let index = 0; index < 120; index++) {
    const timestamp = Math.round(index * 1000000 / 30);
    // Steady throughput with fixed processing latency, not a growing backlog.
    const age = index % 10 === 0 ? 78000 : index % 10 === 1 ? 50000 : 40000;
    assert.equal(check(timestamp, timestamp + age), true);
  }
});

test('accepting normal processing delay does not replay stale or duplicate frames', () => {
  const { check } = fixture();
  assert.equal(check(0, 100000), true); // Inclusive budget boundary.
  assert.equal(check(33333, 133334), false); // More than 100 ms behind.
  assert.equal(check(100000, 140000), true); // Recover without shifting the media clock.
  assert.equal(check(100000, 145000), false); // Duplicate.
  assert.equal(check(90000, 150000), false); // Out-of-order.
  assert.equal(check(110000, 150000), false); // Sampling is still enforced.
  assert.equal(check(133333, 173333), true);
});

test('low frame rates retain a three-frame budget, while 60 fps has a 100 ms floor', () => {
  const low = fixture(15);
  assert.equal(low.check(0, 200000), true);
  assert.equal(low.check(100000, 300001), false);
  const high = fixture(60);
  assert.equal(high.check(0, 40000), true);
  assert.equal(high.check(16667, 56667), true);
  assert.equal(high.check(33333, 133334), false);
});
