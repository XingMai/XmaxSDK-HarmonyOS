const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

function fixture(extraStubs = {}) {
  let now = 0, enabled = true;
  const logs = [];
  const load = loadEts({
    '@ohos.systemDateTime': { default: { TimeType: { ACTIVE: 0 }, getUptime: () => now } },
    XmaxLogger: { XmaxLogger: {
      isEnabled: option => enabled && option === 2,
      info: (message, category, option) => logs.push({ message, category, option }),
      error() {}
    } },
    ...extraStubs
  });
  const { CameraFrameStatistics } = load('media/camera/CameraFrameStatistics.ets');
  const statistics = new CameraFrameStatistics();
  const format = { width: 1024, height: 1920, fps: 30 };
  statistics.restart();
  return { statistics, format, load, logs,
    time(value) { now = value; }, enable(value) { enabled = value; } };
}

test('camera metrics report averages, delivery fps and native thread CPU over matching sample windows', () => {
  const f = fixture(), s = f.statistics;
  f.time(10000); // Opening/first-frame delay must not lower steady-state fps.
  s.record(500, 100, 1000);
  for (let i = 1; i <= 60; ++i) {
    f.time(10000 + i * 2000 / 60);
    // Native timestamps cover 2s, independently of callback timestamps.
    s.record(i % 2 ? 2 : 6, 100 + i * 400 / 60, 1000 + i * 2000 / 60);
  }
  assert.equal(f.logs.length, 1);
  const { message, category, option } = f.logs[0];
  assert.equal(category, 'Camera');
  assert.equal(option, 2);
  assert.equal(message, '相机性能 (Camera Performance)\n' +
    '├─ 平均帧处理：4.00 ms\n' +
    '├─ 处理线程 CPU：20.0%\n' +
    '└─ Native 交付：30.0 fps，平均间隔 33.3 ms');
  // Next window must reset totals and use native time, not delivery time, for CPU.
  f.time(14000);
  s.record(8, 700, 4000);
  assert.match(f.logs[1].message, /处理线程 CPU：20.0%/);
  assert.match(f.logs[1].message, /平均帧处理：8.00 ms/);
});

test('unavailable thread clocks are reported as unavailable and recover in the next complete window', () => {
  const f = fixture(), s = f.statistics;
  s.record(1);
  f.time(2000);
  s.record(1, 10, 2000);
  assert.match(f.logs[0].message, /CPU：不可用/);
  f.time(4000);
  s.record(1, 30, 4000);
  assert.match(f.logs[1].message, /CPU：1.0%/);
  f.time(6000);
  s.record(1, undefined, 6000);
  assert.match(f.logs[2].message, /CPU：不可用/);
});

test('logging and camera reconfiguration restart the measurement baseline', () => {
  const f = fixture(), s = f.statistics;
  s.record(1, 0, 0);
  f.enable(false); f.time(1000);
  s.record(100, 100, 1000);
  f.enable(true); f.time(100000);
  s.record(100, 1000, 100000);
  assert.equal(f.logs.length, 0);
  f.time(102000);
  s.record(3, 1010, 102000);
  assert.match(f.logs[0].message, /平均帧处理：3.00 ms/);
  assert.match(f.logs[0].message, /CPU：0.5%/);
  s.restart();
  f.time(200000);
  s.record(1, 2000, 200000);
  assert.equal(f.logs.length, 1);
  f.time(202000);
  s.record(2, 2010, 202000);
  assert.match(f.logs[1].message, /平均帧处理：2.00 ms/);
});

test('CameraFrameOutput forwards native CPU snapshots and processing time into performance logs', () => {
  let callback;
  const f = fixture({
    '@kit.CameraKit': { camera: { ImageRotation: { ROTATION_90: 90, ROTATION_180: 180, ROTATION_270: 270 } } },
    '@kit.ArkUI': { display: { getDefaultDisplaySync: () => ({ rotation: 0 }) } },
    'libxmax_video.so': { default: {
      createFrameReceiver(_width, _height, listener) {
        callback = listener;
        return { getSurfaceId: () => 'surface', configure() {}, release() {} };
      }
    } }
  });
  const { CameraFrameOutput } = f.load('media/camera/CameraFrameOutput.ets');
  let delivered = 0;
  const output = CameraFrameOutput.create({
    createPreviewOutput: () => ({ getPreviewRotation: () => 90 })
  }, { size: { width: 1920, height: 1440 } }, () => delivered++);
  output.configure(f.format, 30);
  callback(new ArrayBuffer(6), 2, 2, 1000, undefined, 5, 0, 0, 'libyuv (NEON enabled)', 100, 1000);
  f.time(2000);
  callback(new ArrayBuffer(6), 2, 2, 2001000, undefined, 3, 2, 4, 'libyuv (NEON enabled)', 300, 3000,
    { allocationMilliseconds: 0.2, uvSplitMilliseconds: 0.3, scaleMilliseconds: 1.4,
      rotationMilliseconds: 0.8, uvMergeMilliseconds: 0.2 });
  assert.equal(delivered, 2);
  assert.match(f.logs[0].message, /CPU：10.0%/);
  assert.match(f.logs[0].message, /平均帧处理：3.00 ms/);
});
