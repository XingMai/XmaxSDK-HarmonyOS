const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

function fixture() {
  const errors = [];
  const load = loadEts({
    '@bytertc/volcenginertc': {},
    QualityClock: { QualityClock: { now: () => 1 } },
    XmaxLogger: { XmaxLogger: { error: message => errors.push(message) } }
  });
  const { QualityController } = load('stream/quality/QualityController.ets');
  const { UplinkVideoStatistics: Up, DownlinkVideoStatistics: Down } = load('foundation/rtc/VideoStatistics.ets');
  const { RtcQualityConverter: Converter } = load('foundation/rtc/RtcQualityConverter.ets');
  const controller = new QualityController({ setQualityListener() {} });
  return { load, controller, Up, Down, Converter, errors };
}

test('Volc statistics convert actual encoding metrics, fractional packet loss and RTC latency', () => {
  const { Converter: C, Up, Down } = fixture();
  assert.deepEqual(C.uplinkVideoStatistics({ encoded_frame_width: 832, encoded_frame_height: 1472,
    input_frame_rate: 30, encoder_output_frame_rate: 24, sent_frame_rate: 23.5, sent_kbitrate: 800, video_loss_rate: 0.0125 }),
  new Up(832, 1472, 30, 24, 23.5, 800, 1.25));
  assert.deepEqual(C.downlinkVideoStatistics('bot', { width: 640, height: 360,
    decoder_output_frame_rate: 24, renderer_output_frame_rate: 23, received_kbitrate: 600,
    video_loss_rate: 0.025, e2e_delay: 123 }), new Down('bot', 640, 360, 24, 23, 600, 2.5, 123));
});

test('unavailable or invalid metrics stay absent while legitimate zero rates and loss survive', () => {
  const { Converter: C, Up, Down } = fixture();
  assert.deepEqual(C.uplinkVideoStatistics({ encoded_frame_width: 0, encoded_frame_height: NaN,
    input_frame_rate: -1, encoder_output_frame_rate: Infinity, sent_frame_rate: 0,
    sent_kbitrate: 0, video_loss_rate: 0 }), new Up(undefined, undefined, undefined, undefined, 0, 0, 0));
  assert.deepEqual(C.downlinkVideoStatistics('bot', { width: 3.5, height: -1,
    decoder_output_frame_rate: undefined, renderer_output_frame_rate: -1,
    received_kbitrate: NaN, video_loss_rate: 2, e2e_delay: -1 }), new Down('bot'));
});

test('uplink statistics follow publication and clear asynchronously on stop', async () => {
  const { controller: c, Up } = fixture(), received = [], stats = new Up(640, 360);
  c.setUplinkVideoStatisticsListener(value => received.push(value));
  c.onUplinkVideoStatistics(stats); await Promise.resolve(); assert.deepEqual(received, []);
  c.setUplinkVideoStatisticsEnabled(true); await Promise.resolve();
  c.onUplinkVideoStatistics(stats); assert.deepEqual(received, [undefined]);
  await Promise.resolve(); assert.deepEqual(received, [undefined, stats]);
  c.setUplinkVideoStatisticsEnabled(false);
  c.onUplinkVideoStatistics(stats); await Promise.resolve();
  assert.deepEqual(received, [undefined, stats, undefined]);
});

test('downlink statistics follow only the matched generation stream and drop queued old streams', async () => {
  const { controller: c, Down } = fixture(), received = [], a = new Down('a'), b = new Down('b');
  c.setDownlinkVideoStatisticsListener(value => received.push(value));
  c.onDownlinkVideoStatistics(a); await Promise.resolve(); assert.deepEqual(received, []);
  c.setDownlinkVideoStatisticsUser('a'); await Promise.resolve();
  c.onDownlinkVideoStatistics(b); c.onDownlinkVideoStatistics(a);
  c.setDownlinkVideoStatisticsUser('b'); await Promise.resolve();
  assert.deepEqual(received, [undefined, undefined]);
  c.onDownlinkVideoStatistics(a); c.onDownlinkVideoStatistics(b); await Promise.resolve();
  assert.deepEqual(received, [undefined, undefined, b]);
  c.setDownlinkVideoStatisticsUser(undefined); c.onDownlinkVideoStatistics(b);
  await Promise.resolve(); assert.equal(received.at(-1), undefined);
});

test('replacement and removal invalidate pending statistics and clear callbacks in both directions', async () => {
  const { controller: c, Up, Down } = fixture();
  for (const [set, enable, emit, stats] of [
    ['setUplinkVideoStatisticsListener', 'setUplinkVideoStatisticsEnabled', 'onUplinkVideoStatistics', new Up()],
    ['setDownlinkVideoStatisticsListener', 'setDownlinkVideoStatisticsUser', 'onDownlinkVideoStatistics', new Down('bot')]
  ]) {
    const old = [], latest = [];
    c[set](s => old.push(s)); c[enable](set.includes('Uplink') ? true : 'bot'); c[emit](stats);
    c[set](s => latest.push(s)); await Promise.resolve();
    assert.deepEqual(old, []); assert.deepEqual(latest, []);
    c[emit](stats); await Promise.resolve(); assert.deepEqual(latest, [stats]);
    c[emit](stats); c[set](null); await Promise.resolve(); assert.deepEqual(latest, [stats]);
  }
});

test('listener exceptions are contained and cannot stop later statistics delivery', async () => {
  const { controller: c, Up, Down, errors } = fixture();
  c.setUplinkVideoStatisticsListener(() => { throw new Error('uplink app error'); });
  c.setDownlinkVideoStatisticsListener(() => { throw new Error('downlink app error'); });
  c.setUplinkVideoStatisticsEnabled(true); c.setDownlinkVideoStatisticsUser('bot'); await Promise.resolve();
  errors.length = 0;
  c.onUplinkVideoStatistics(new Up()); c.onDownlinkVideoStatistics(new Down('bot')); await Promise.resolve();
  assert.equal(errors.length, 2);
  let count = 0; c.setUplinkVideoStatisticsListener(() => count++);
  c.onUplinkVideoStatistics(new Up()); await Promise.resolve(); assert.equal(count, 1);
});

test('native statistics callbacks work without RTC logging, exclude screen streams and ignore former rooms', () => {
  const handlers = new Map(), received = [];
  const load = loadEts({
    '@bytertc/volcenginertc': { MirrorType: { kMirrorTypeNone: 0 } },
    '@kit.ArkTS': {},
    XmaxLogger: { XmaxLogger: {} },
    RtcEngineManager: {}, RtcStatsLogger: { RtcStatsLogger: { logLocalStreamStats() {}, logRemoteStreamStats() {} } }
  });
  const { RtcManager } = load('foundation/rtc/RtcManager.ets');
  const rtc = new RtcManager({}), room = { on(name, callback) { handlers.set(name, callback); } };
  rtc.room = room; rtc.bindRoomEvents(room);
  rtc.setQualityListener({ onUplinkVideoStatistics: s => received.push(s), onDownlinkVideoStatistics: s => received.push(s) });
  const up = { video_stats: { sent_kbitrate: 42 }, is_screen: false };
  const down = { video_stats: { e2e_delay: 90 }, uid: 'bot', is_screen: false };
  handlers.get('onLocalStreamStats')(up); handlers.get('onRemoteStreamStats')(down);
  assert.equal(received.length, 2); assert.equal(received[0].bitrateKbps, 42);
  assert.equal(received[1].userId, 'bot'); assert.equal(received[1].endToEndDelayMs, 90);
  handlers.get('onLocalStreamStats')({ ...up, is_screen: true });
  handlers.get('onRemoteStreamStats')({ ...down, is_screen: true });
  rtc.room = null;
  handlers.get('onLocalStreamStats')(up); handlers.get('onRemoteStreamStats')(down);
  assert.equal(received.length, 2);
});
