const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

function fixture(extra = {}) {
  let now = 100, listener;
  const warnings = [];
  const load = loadEts({
    '@ohos.systemDateTime': { default: { TimeType: { ACTIVE: 0 }, getUptime: () => now * 1e9 } },
    XmaxLogger: { XmaxLogger: { error() {}, warn: value => warnings.push(value) } },
    ...extra
  });
  const { RealtimeVideoFormat: Format, RealtimeVideoEncoderPreference: Preference } = load('service/realtime/RealtimeVideoFormat.ets');
  const { QualityVideoFormat } = load('stream/quality/QualityVideoFormat.ets');
  const { QualityDirection } = load('stream/quality/QualityDirection.ets');
  const { QualityHistory, MemoryQualityHistoryStore } = load('stream/quality/QualityHistory.ets');
  const { RealtimeNetworkQualityLevel: Level, RealtimeNetworkQuality: Quality } = load('service/realtime/RealtimeNetworkQuality.ets');
  const { RtcQualityLevel: RtcLevel } = load('foundation/rtc/RtcQualityListener.ets');
  const { QualityController } = load('stream/quality/QualityController.ets');
  const store = new MemoryQualityHistoryStore();
  const controller = new QualityController({ setQualityListener(value) { listener = value; } }, store);
  return { load, Format, Preference, QualityVideoFormat, QualityDirection, QualityHistory, store, Level, Quality,
    controller, RtcLevel, warnings, sample(up, down) { listener.onNetworkQuality(up, down); },
    setTime(value) { now = value; } };
}

test('five transmission tiers preserve media baseline, explicit encoding settings and a minimum short side', () => {
  const f = fixture();
  const baseline = new f.Format(1920, 1080, 30, 500, 3000, f.Preference.MAINTAIN_QUALITY);
  for (const [level, width, height, fps] of [[1, 1920, 1080, 30], [2, 1536, 864, 24],
    [3, 1248, 702, 24], [4, 960, 540, 20], [5, 960, 540, 16]]) {
    assert.deepEqual(f.QualityVideoFormat.resolve(baseline, level, false),
      new f.Format(width, height, fps, 500, 3000, f.Preference.MAINTAIN_QUALITY));
    const down = f.QualityVideoFormat.resolve(baseline, level, true);
    assert.equal(down.fps, 24);
    assert.equal(down.minimumBitrate, undefined);
    assert.equal(down.maximumBitrate, undefined);
    assert.equal(down.width, width);
    assert.equal(down.height, height);
  }
  const small = new f.Format(320, 180, 15);
  for (const level of [1, 2, 3, 4, 5]) assert.deepEqual(f.QualityVideoFormat.resolve(small, level, false), small);
  const limited = f.QualityVideoFormat.resolve(new f.Format(400, 300, 30), 5, false);
  assert.equal(limited.width, 320);
  assert.equal(limited.height, 240);
  assert.equal(baseline.width, 1920);
});

test('three consecutive poor samples propose a downgrade; commits create a four second stability window', () => {
  const f = fixture(), direction = new f.QualityDirection(new f.Format(1920, 1080, 30), 2, false);
  for (const time of [100, 102]) assert.equal(direction.observe(f.Level.BAD, time, time), undefined);
  assert.equal(direction.observe(f.Level.VERY_BAD, 104, 104), 3);
  assert.equal(direction.level, 2);
  direction.complete(3, true, 104);
  assert.equal(direction.level, 3);
  assert.equal(direction.observe(f.Level.BAD, 106, 106), undefined);
  for (const time of [108, 110]) assert.equal(direction.observe(f.Level.BAD, time, time), undefined);
  assert.equal(direction.observe(f.Level.BAD, 112, 112), 4);
});

test('five good samples probe an upgrade and a quick fallback delays further upgrades for sixty seconds', () => {
  const f = fixture(), d = new f.QualityDirection(new f.Format(1920, 1080, 30), 3, false);
  for (const time of [100, 102, 104, 106]) assert.equal(d.observe(f.Level.GOOD, time, time), undefined);
  assert.equal(d.observe(f.Level.EXCELLENT, 108, 108), 2);
  d.complete(2, true, 108);
  for (const time of [112, 114]) assert.equal(d.observe(f.Level.BAD, time, time), undefined);
  assert.equal(d.observe(f.Level.BAD, 116, 116), 3);
  d.complete(3, true, 116);
  for (let time = 120; time < 176; time += 2) assert.equal(d.observe(f.Level.GOOD, time, time), undefined);
  assert.equal(d.observe(f.Level.GOOD, 176, 176), 2);
});

test('unknown, moderate, stale, duplicate and out-of-order samples cannot accumulate a false downgrade', () => {
  const f = fixture(), d = new f.QualityDirection(new f.Format(1920, 1080, 30), 2, false);
  assert.equal(d.observe(f.Level.BAD, 100, 100), undefined);
  assert.equal(d.observe(f.Level.BAD, 100, 100), undefined);
  assert.equal(d.observe(f.Level.BAD, 99, 102), undefined);
  assert.equal(d.observe(f.Level.BAD, 102, 108), undefined);
  for (const time of [110, 112]) assert.equal(d.observe(f.Level.BAD, time, time), undefined);
  assert.equal(d.observe(f.Level.UNKNOWN, 114, 114), undefined);
  assert.equal(d.observe(f.Level.BAD, 116, 116), undefined);
  assert.equal(d.observe(f.Level.POOR, 118, 118), undefined);
  assert.equal(d.observe(f.Level.BAD, 120, 120), undefined);
  assert.equal(d.observe(f.Level.DOWN, 122, 122), undefined);
  for (const time of [124, 126]) assert.equal(d.observe(f.Level.BAD, time, time), undefined);
  assert.equal(d.observe(f.Level.BAD, 128, 128), 3);
});

test('unsupported explicit bitrate ranges and identical terminal downlink formats are skipped', () => {
  const f = fixture();
  const up = new f.QualityDirection(new f.Format(1920, 1080, 30, 2000), 5, false);
  assert.equal(up.level, 2);
  for (const time of [100, 102, 104]) assert.equal(up.observe(f.Level.BAD, time, time), undefined);
  const down = new f.QualityDirection(new f.Format(1920, 1080, 30), 4, true);
  for (const time of [100, 102, 104]) assert.equal(down.observe(f.Level.BAD, time, time), undefined);
});

test('history separates models and directions, expires after one hour and rejects clock rollback', () => {
  const f = fixture(), history = new f.QualityHistory('x2.0-sla', f.store);
  history.write(4, false, 1000);
  assert.equal(history.read(false, 1001), 4);
  assert.equal(history.read(true, 1001), 2);
  assert.equal(new f.QualityHistory('x2.0', f.store).read(false, 1001), 2);
  assert.equal(history.read(false, 4599), 4);
  assert.equal(history.read(false, 4600), 2);
  assert.equal(history.read(false, 999), 2);
  history.write(8, false, 1002);
  assert.equal(history.read(false, 1003), 4);
  assert.equal(f.store.getNumber('xmax.quality.volcengine.x2.0-sla.uplink'), 4);
});

test('Preferences preserves successful history across controller instances; failed applications are never saved', () => {
  const f = fixture();
  const { QualityPreferences } = f.load('stream/quality/QualityPreferences.ets');
  const first = new f.QualityHistory('x2.0-sla', new QualityPreferences({}));
  first.write(3, true);
  const second = new f.QualityHistory('x2.0-sla', new QualityPreferences({}));
  assert.equal(second.read(true), 3);
  assert.equal(second.read(false), 2);
  f.controller.prepareQuality(new f.Format(1920, 1080, 30), 'x2.0');
  f.controller.completeQuality(false, 3, false);
  assert.equal(f.controller.qualityConfiguration.uplinkLevel, 2);
  assert.equal(new f.QualityHistory('x2.0', f.store).read(false), 2);
  f.controller.completeQuality(false, 3, true);
  assert.equal(new f.QualityHistory('x2.0', f.store).read(false), 3);
  f.controller.completeQuality(false, 2, false);
  assert.equal(new f.QualityHistory('x2.0', f.store).read(false), 3);
});

test('adaptive quality is independent of application listeners, and rebase preserves levels on camera rotation', () => {
  const f = fixture(), adaptive = [], app = [];
  f.controller.prepareQuality(new f.Format(1920, 1080, 30), 'x2.0-sla');
  f.controller.setAdaptiveQualityListener((quality, now) => adaptive.push({ quality, now }));
  f.sample(f.RtcLevel.BAD, f.RtcLevel.GOOD);
  assert.equal(adaptive.length, 1);
  assert.equal(adaptive[0].quality.uplink, f.Level.BAD);
  f.controller.setNetworkQualityListener(q => { app.push(q); throw new Error('app callback failed'); });
  f.setTime(102); f.sample(f.RtcLevel.BAD, f.RtcLevel.GOOD);
  assert.equal(adaptive.length, 2);
  assert.equal(app.length, 1);
  f.controller.completeQuality(false, 3, true);
  const rebased = f.controller.rebaseQuality(new f.Format(1080, 1920, 30));
  assert.equal(rebased.uplinkLevel, 3);
  assert.equal(rebased.downlinkLevel, 2);
  assert.equal(rebased.baseline.width, 1080);
  f.controller.resetQuality();
  assert.equal(f.controller.qualityConfiguration, undefined);
  f.sample(f.RtcLevel.BAD, f.RtcLevel.BAD);
  assert.equal(adaptive.length, 2);
});
