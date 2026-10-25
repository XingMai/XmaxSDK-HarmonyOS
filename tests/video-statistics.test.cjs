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
    RtcEngineManager: {}, RtcStatsLogger: { RtcStatsLogger: { logUplinkVideoStatistics() {}, logDownlinkVideoStatistics() {} } }
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

function loggingFixture() {
  const logs = [];
  const load = loadEts({
    '@kit.PerformanceAnalysisKit': { hilog: { debug: (_domain, _tag, _format, message) => logs.push(message) } },
    '@kit.ArkTS': {},
    '@bytertc/volcenginertc': { MirrorType: { kMirrorTypeNone: 0 }, NetworkQuality: {}, PerformanceAlarmReason: {} },
    RtcEngineManager: {}, RtcVideoConverter: {}
  });
  const { XmaxLogger: Logger } = load('foundation/logging/XmaxLogger.ets');
  const { XmaxLoggerOption: Option } = load('foundation/logging/XmaxLoggerOption.ets');
  const { XmaxLogLanguage: Language } = load('foundation/logging/XmaxLogger.ets');
  const { RtcStatsLogger: Common } = load('foundation/rtc/RtcStatsLogger.ets');
  const { RtcQualityConverter: Converter } = load('foundation/rtc/RtcQualityConverter.ets');
  const { RtcManager } = load('foundation/rtc/RtcManager.ets');
  const handlers = new Map(), rtc = new RtcManager({});
  const room = { on(name, handler) { handlers.set(name, handler); } };
  rtc.room = room; rtc.bindRoomEvents(room);
  Logger.configure(Option.PERFORMANCE, Language.ENGLISH);
  return { load, logs, Logger, Option, Language, Common, Converter, rtc, handlers };
}

function nativeVideoSamples() {
  return {
    up: { is_screen: false,
      audio_stats: { send_kbitrate: 48, record_sample_rate: 48000, sent_sample_rate: 48000, num_channels: 2 },
      video_stats: { encoded_frame_width: 0, encoded_frame_height: -1, input_frame_rate: 0,
        encoder_output_frame_rate: -1, sent_frame_rate: 23.5, sent_kbitrate: 0, video_loss_rate: 0.0125,
        rtt: 21, jitter: 3 } },
    down: { uid: 'bot', is_screen: false,
      video_stats: { width: 640, height: 360, decoder_output_frame_rate: 24, renderer_output_frame_rate: 23,
        received_kbitrate: 600, video_loss_rate: 0, e2e_delay: 42, rtt: 20, jitter: 6, stall_count: 2, stall_duration: 50 } }
  };
}

test('native events convert once and share the exact normalized object between video logs and callbacks', () => {
  const f = loggingFixture(), samples = nativeVideoSamples(), logged = [], received = [], conversions = [0, 0];
  const convertUp = f.Converter.uplinkVideoStatistics, convertDown = f.Converter.downlinkVideoStatistics;
  const logUp = f.Common.logUplinkVideoStatistics, logDown = f.Common.logDownlinkVideoStatistics;
  f.Converter.uplinkVideoStatistics = raw => { conversions[0]++; return convertUp(raw); };
  f.Converter.downlinkVideoStatistics = (user, raw) => { conversions[1]++; return convertDown(user, raw); };
  f.Common.logUplinkVideoStatistics = stats => { logged.push(stats); logUp(stats); };
  f.Common.logDownlinkVideoStatistics = stats => { logged.push(stats); logDown(stats); };
  f.rtc.setQualityListener({ onUplinkVideoStatistics: stats => received.push(stats), onDownlinkVideoStatistics: stats => received.push(stats) });
  f.handlers.get('onLocalStreamStats')(samples.up);
  f.handlers.get('onRemoteStreamStats')(samples.down);
  assert.deepEqual(conversions, [1, 1]);
  assert.equal(received.length, 2);
  for (let i = 0; i < 2; i++) assert.equal(logged[i], received[i]);
  assert.equal(received[0].width, undefined); assert.equal(received[0].height, undefined);
  assert.equal(received[0].captureFrameRate, 0); assert.equal(received[0].encodeFrameRate, undefined);
  assert.equal(received[0].sendFrameRate, 23.5); assert.equal(received[0].packetLossPercent, 1.25);
  const common = f.logs.filter(log => log.startsWith('[Xmax][RTC]'));
  assert.equal(common.length, 2);
  assert.match(common[0], /Resolution: —/);
  assert.match(common[0], /Capture Frame Rate: 0 fps/);
  assert.match(common[0], /Encode Frame Rate: —/);
  assert.match(common[0], /Send Frame Rate: 23.5 fps/);
  assert.match(common[0], /Send Bitrate: 0 kbps/);
  assert.match(common[0], /Video Packet Loss: 1.25 %/);
  assert.match(common[1], /Resolution: 640 × 360/);
  assert.match(common[1], /Receive Bitrate: 600 kbps/);
  assert.match(common[1], /End-to-End Delay: 42 ms/);
  assert.doesNotMatch(common.join('\n'), /NaN|undefined|RTT|Jitter|Audio|Stall/);
  assert.equal(f.logs.length, 2); // Each event emits only its common video log.
  assert.doesNotMatch(f.logs.join('\n'), /VolcEngine|Extras|RTT|Jitter|Audio|Stall/);
});

test('video statistics never read removed native diagnostic fields, regardless of the logging switch', () => {
  for (const enabled of [false, true]) {
    const f = loggingFixture(), samples = nativeVideoSamples(), received = [];
    f.Logger.configure(enabled ? f.Option.PERFORMANCE : f.Option.BUSINESS);
    for (const sample of [samples.up, samples.down]) {
      Object.defineProperty(sample, 'audio_stats', { get() { throw new Error('audio diagnostics accessed'); } });
      for (const field of ['rtt', 'jitter', 'stall_count', 'stall_duration']) {
        Object.defineProperty(sample.video_stats, field, { get() { throw new Error('removed video diagnostic accessed'); } });
      }
    }
    f.rtc.setQualityListener({ onUplinkVideoStatistics: stats => received.push(stats), onDownlinkVideoStatistics: stats => received.push(stats) });
    f.handlers.get('onLocalStreamStats')(samples.up);
    f.handlers.get('onRemoteStreamStats')(samples.down);
    assert.equal(received.length, 2);
    assert.equal(received[0].packetLossPercent, 1.25);
    assert.equal(received[1].endToEndDelayMs, 42);
    assert.equal(f.logs.length, enabled ? 2 : 0);
  }
});

test('screen stream statistics emit neither main-stream video logs nor callbacks', () => {
  const f = loggingFixture(), samples = nativeVideoSamples(), received = [];
  f.rtc.setQualityListener({ onUplinkVideoStatistics: stats => received.push(stats), onDownlinkVideoStatistics: stats => received.push(stats) });
  for (const sample of [samples.up, samples.down]) {
    sample.is_screen = true;
    Object.defineProperty(sample, 'video_stats', { get() { throw new Error('screen video stats accessed'); } });
  }
  f.handlers.get('onLocalStreamStats')(samples.up);
  f.handlers.get('onRemoteStreamStats')(samples.down);
  assert.deepEqual(f.logs, []); assert.deepEqual(received, []);
});

test('public video log fields follow localization while missing values remain placeholders', () => {
  const f = loggingFixture();
  const { UplinkVideoStatistics: Up, DownlinkVideoStatistics: Down } = f.load('foundation/rtc/VideoStatistics.ets');
  f.Logger.configure(f.Option.PERFORMANCE, f.Language.CHINESE);
  f.Common.logUplinkVideoStatistics(new Up());
  f.Common.logDownlinkVideoStatistics(new Down('bot'));
  assert.match(f.logs[0], /视频上行统计 \(Video Uplink Statistics\)/);
  assert.match(f.logs[0], /采集帧率：—/);
  assert.match(f.logs[1], /端到端时延：—/);
  assert.doesNotMatch(f.logs.join('\n'), /undefined|NaN|0 × 0/);
});
