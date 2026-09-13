const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

function fixture() {
  const calls = [];
  const load = loadEts();
  const { RealtimeVideoFormat: Format, RealtimeVideoEncoderPreference: Preference } =
    load('service/realtime/RealtimeVideoFormat.ets');
  const { EncodingController } = load('stream/encoding/EncodingController.ets');
  const { VideoEncoderPreference: Internal } = load('foundation/rtc/VideoEncodingConfiguration.ets');
  const rtc = { configureVideoEncoding: config => calls.push(config) };
  return { Format, Preference, Internal, calls, rtc, controller: new EncodingController(rtc) };
}

test('explicit and partial bitrate overrides and all preferences reach RTC', () => {
  const f = fixture();
  for (const [min, max, pref, expectedMin, expectedMax, expectedPref] of [
    [1500, 3000, f.Preference.AUTO, 1500, 3000, f.Internal.AUTO],
    [0, 500, f.Preference.MAINTAIN_QUALITY, 0, 500, f.Internal.MAINTAIN_QUALITY],
    [undefined, 4000, f.Preference.MAINTAIN_FRAMERATE, 1805, 4000, f.Internal.MAINTAIN_FRAMERATE],
    [1500, undefined, undefined, 1500, 3611, f.Internal.AUTO],
    [2000, 2000, undefined, 2000, 2000, f.Internal.AUTO],
    [undefined, undefined, undefined, 1805, 3611, f.Internal.AUTO]
  ]) {
    f.controller.configure(new f.Format(832, 1472, 24, min, max, pref));
    assert.deepEqual({ ...f.calls.at(-1) }, { width: 832, height: 1472, frameRate: 24,
      minimumBitrate: expectedMin, maximumBitrate: expectedMax, encoderPreference: expectedPref });
  }
});

test('invalid bitrate values and default-merged ranges fail before RTC', () => {
  const f = fixture();
  for (const [min, max] of [[-1, undefined], [undefined, 0], [3000, 1500],
    [4000, undefined], [undefined, 1000], [NaN, 4000], [0, Infinity],
    [0.5, 4000], [0, 4000.5], [0, Number.MAX_SAFE_INTEGER + 1]]) {
    assert.throws(() => f.controller.configure(new f.Format(832, 1472, 24, min, max)),
      { code: 'INVALID_CONFIGURATION' });
  }
  for (const format of [new f.Format(1023, 768, 30), new f.Format(1024, 768, NaN),
    new f.Format(1024, 768, Infinity), new f.Format(1024, 768, 29.5),
    new f.Format(1024, 768, 30, 0, 4000, 'invalid'),
    new f.Format(Number.MAX_SAFE_INTEGER - 1, Number.MAX_SAFE_INTEGER - 1, 30)]) {
    assert.throws(() => f.controller.configure(format), { code: 'INVALID_CONFIGURATION' });
  }
  assert.equal(f.calls.length, 0);
});

test('default bitrates match iOS references, interpolation and extrapolation', () => {
  const f = fixture();
  for (const [w, h, fps, min, max] of [
    [120,120,15,50,100], [640,480,10,400,800], [640,480,15,500,1000],
    [640,480,30,750,1500], [1280,720,30,1710,3420], [1920,1080,30,3150,6300],
    [1920,1080,60,4780,6500], [832,1472,24,1805,3611], [1472,832,24,1805,3611],
    [1024,1920,30,3016,6031], [1024,768,24,1310,2620], [1920,1080,120,9560,13000],
    [3840,2160,30,12600,25200], [120,120,30,77,154], [1920,1080,1,166,333], [2,2,1,1,2]
  ]) {
    f.controller.configure(new f.Format(w, h, fps));
    const actual = f.calls.at(-1);
    assert.deepEqual([actual.minimumBitrate, actual.maximumBitrate], [min, max], `${w}x${h}@${fps}`);
  }
});

test('default bitrate ranges remain ordered and monotonic at frame-rate boundaries', () => {
  const f = fixture();
  for (const [w, h] of [[120, 120], [320, 240], [832, 1472], [1920, 1080], [3840, 2160]]) {
    let previousMin = 0, previousMax = 0;
    for (const fps of [1, 9, 10, 11, 14, 15, 16, 24, 29, 30, 31, 59, 60, 61, 120]) {
      f.controller.configure(new f.Format(w, h, fps));
      const { minimumBitrate: min, maximumBitrate: max } = f.calls.at(-1);
      assert.ok(min > 0 && max > min && min >= previousMin && max >= previousMax);
      previousMin = min; previousMax = max;
    }
  }
});

test('encoding preserves the original RTC error', () => {
  const f = fixture(), expected = new Error('RTC failed');
  f.rtc.configureVideoEncoding = () => { throw expected; };
  assert.throws(() => f.controller.configure(new f.Format(1024, 1920, 30)), error => error === expected);
});

test('public encoding preferences and kbps values reach the actual engine config', () => {
  const configs = [];
  const load = loadEts({
    '@kit.ArkTS': { util: {} },
    '@bytertc/volcenginertc': { MirrorType: { kMirrorTypeNone: 0 }, VideoEncodePreference: {
      kVideoEncodePreferenceBalance: 3, kVideoEncodePreferenceFramerate: 1, kVideoEncodePreferenceQuality: 2
    } },
    XmaxLogger: { XmaxLogger: {} }, RtcEngineManager: {}, RtcStatsLogger: { RtcStatsLogger: class {} }
  });
  const { RtcManager } = load('foundation/rtc/RtcManager.ets');
  const { EncodingController } = load('stream/encoding/EncodingController.ets');
  const { RealtimeVideoFormat: Format, RealtimeVideoEncoderPreference: P } = load('service/realtime/RealtimeVideoFormat.ets');
  const rtc = new RtcManager({});
  rtc.engineLease = { engine: { setVideoEncoderConfig: config => { configs.push(config); return 0; } } };
  const controller = new EncodingController(rtc);
  for (const [preference, expected] of [[P.AUTO, 3], [P.MAINTAIN_FRAMERATE, 1], [P.MAINTAIN_QUALITY, 2]]) {
    controller.configure(new Format(1024, 1920, 30, 1500, 6000, preference));
    assert.deepEqual(configs.at(-1), { width: 1024, height: 1920, frame_rate: 30,
      min_bitrate: 1500, max_bitrate: 6000, encoder_preference: expected });
  }
});
