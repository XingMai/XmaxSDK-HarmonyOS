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
  const statistics = new CameraFrameStatistics(1920, 1440);
  const format = { width: 1024, height: 1920, fps: 30 };
  statistics.configure(format, 30, 90);
  return { statistics, format, load, logs,
    time(value) { now = value; }, enable(value) { enabled = value; } };
}

test('camera metrics report averages, delivery fps and native thread CPU over matching sample windows', () => {
  const f = fixture(), s = f.statistics;
  f.time(10000); // Opening/first-frame delay must not lower steady-state fps.
  s.record(500, 100, 100, 'libyuv (NEON enabled)', 100, 1000);
  for (let i = 1; i <= 60; ++i) {
    f.time(10000 + i * 2000 / 60);
    // Native timestamps cover 2s, independently of callback timestamps.
    s.record(i % 2 ? 2 : 6, i === 60 ? 3 : 0, i === 60 ? 12 : 0,
      'libyuv (NEON enabled)', 100 + i * 400 / 60, 1000 + i * 2000 / 60);
  }
  assert.equal(f.logs.length, 1);
  const { message, category, option } = f.logs[0];
  assert.equal(category, 'CameraPerf');
  assert.equal(option, 2);
  assert.match(message, /1920×1440 @ 30 fps → 1024×1920 @ 30 fps，旋转 90°/);
  assert.match(message, /libyuv \(NEON enabled\)/);
  assert.match(message, /平均帧处理：4.00 ms/);
  assert.match(message, /处理线程 CPU：20.0%（单核 100%）/);
  assert.match(message, /Native 交付：30.0 fps，平均间隔 33.3 ms/);
  assert.match(message, /丢帧：3（4.8%，不含主动跳帧），主动采样跳帧：12/);
  assert.doesNotMatch(message, /P95|最大/);
  // Next window must reset totals and use native time, not delivery time, for CPU.
  f.time(14000);
  s.record(8, 0, 0, 'scalar', 700, 4000);
  assert.match(f.logs[1].message, /处理线程 CPU：20.0%/);
  assert.match(f.logs[1].message, /平均帧处理：8.00 ms/);
  assert.match(f.logs[1].message, /丢帧：0/);
});

test('unavailable thread clocks are reported as unavailable and recover in the next complete window', () => {
  const f = fixture(), s = f.statistics;
  s.record(1, 0, 0, 'scalar');
  f.time(2000);
  s.record(1, 0, 0, 'scalar', 10, 2000);
  assert.match(f.logs[0].message, /CPU：不可用/);
  f.time(4000);
  s.record(1, 0, 0, 'scalar', 30, 4000);
  assert.match(f.logs[1].message, /CPU：1.0%/);
  f.time(6000);
  s.record(1, 0, 0, 'scalar', undefined, 6000);
  assert.match(f.logs[2].message, /CPU：不可用/);
});

test('logging and camera reconfiguration restart the measurement baseline', () => {
  const f = fixture(), s = f.statistics;
  s.record(1, 0, 0, 'scalar', 0, 0);
  f.enable(false); f.time(1000);
  s.record(100, 50, 50, 'scalar', 100, 1000);
  f.enable(true); f.time(100000);
  s.record(100, 50, 50, 'scalar', 1000, 100000);
  assert.equal(f.logs.length, 0);
  f.time(102000);
  s.record(3, 0, 0, 'scalar', 1010, 102000);
  assert.match(f.logs[0].message, /平均帧处理：3.00 ms/);
  assert.match(f.logs[0].message, /CPU：0.5%/);
  s.configure({ width: 832, height: 1472, fps: 24 }, 30, 270);
  f.time(200000);
  s.record(1, 0, 0, 'scalar', 2000, 200000);
  assert.equal(f.logs.length, 1);
  f.time(202000);
  s.record(2, 0, 12, 'scalar', 2010, 202000);
  assert.match(f.logs[1].message, /832×1472 @ 24 fps，旋转 270°/);
});

test('CameraFrameOutput forwards native CPU snapshots and backend into performance logs', () => {
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
  assert.match(f.logs[0].message, /libyuv \(NEON enabled\)/);
  assert.match(f.logs[0].message, /缩放：平均 1.40 ms/);
  assert.match(f.logs[0].message, /输出分配\/初始化：平均 0.20 ms/);
});


test('stage timing averages use the same complete frame window and reset after logging', () => {
  const f = fixture(), s = f.statistics;
  const first = { allocationMilliseconds: 1, uvSplitMilliseconds: 2, scaleMilliseconds: 3,
    rotationMilliseconds: 4, uvMergeMilliseconds: 0 };
  const second = { allocationMilliseconds: 3, uvSplitMilliseconds: 4, scaleMilliseconds: 5,
    rotationMilliseconds: 6, uvMergeMilliseconds: 2 };
  const record = (total, timing) => s.record(total, 0, 0, 'libyuv', undefined, undefined, timing);
  record(999, second); // baseline frame excluded, including its timing
  f.time(1000); record(10, first);
  f.time(2000); record(20, second);
  const message = f.logs[0].message;
  for (const text of ['平均帧处理：15.00 ms', '输出分配/初始化：平均 2.00 ms',
    'UV 拆分：平均 3.00 ms', '缩放：平均 4.00 ms', '旋转：平均 5.00 ms', 'UV 合并：平均 1.00 ms']) {
    assert.ok(message.includes(text), message);
  }
  assert.doesNotMatch(message, /P95|最大/);
  f.time(3000); record(10, { allocationMilliseconds: 1 }); // scalar fallback: no libyuv stages
  f.time(4000); record(20, second);
  assert.match(f.logs[1].message, /分段平均：不可用（完整样本 1\/2）/);
  f.time(6000); record(6, { ...first, rotationMilliseconds: 0 });
  assert.match(f.logs[2].message, /旋转：平均 0.00 ms/);
  assert.match(f.logs[2].message, /输出分配\/初始化：平均 1.00 ms/);
});

test('invalid stage durations are unavailable instead of zero or NaN', () => {
  const f = fixture(), s = f.statistics;
  s.record(1, 0, 0, 'libyuv');
  f.time(2000);
  s.record(1, 0, 0, 'libyuv', undefined, undefined,
    { allocationMilliseconds: 0, uvSplitMilliseconds: 0, scaleMilliseconds: NaN,
      rotationMilliseconds: 0, uvMergeMilliseconds: -1 });
  assert.match(f.logs[0].message, /分段平均：不可用/);
  assert.doesNotMatch(f.logs[0].message, /NaN/);
});
