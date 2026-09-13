const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

function fixture(extra = {}, globals = {}) {
  const logs = [], hilog = {};
  for (const level of ['debug', 'info', 'warn', 'error']) {
    hilog[level] = (_domain, _tag, format, message) => logs.push({ level, format, message });
  }
  const load = loadEts({
    '@ohos.systemDateTime': { default: { TimeType: { ACTIVE: 0 }, getUptime: () => 0 } },
    '@kit.PerformanceAnalysisKit': { hilog },
    '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
    '@kit.BasicServicesKit': { deviceInfo: { distributionOSVersion: '5.1.0', productModel: 'Test model' } },
    '@kit.ArkTS': { util: { TextEncoder: class { encodeInto(value) { return Buffer.from(value); } } } },
    ...extra
  }, globals);
  const { XmaxLogger: Logger } = load('foundation/logging/XmaxLogger.ets');
  const { XmaxLoggerOption: Option } = load('foundation/logging/XmaxLoggerOption.ets');
  const { XmaxError, XmaxErrorCode: Code } = load('foundation/errors/XmaxError.ets');
  return { load, logs, Logger, Option, XmaxError, Code };
}

function imageFixture(t) {
  const intervals = new Map(), received = [];
  let failure, intervalId = 0;
  const f = fixture({
    ImageManager: { ImageManager: class {
      async decodeFile() {
        return { width: 2, height: 2, async release() {},
          async makeVideoFrameData(width, height) {
            return { width, height, pixelFormat: 'RGBA', bytesPerRow: width * 4,
              data: new ArrayBuffer(width * height * 4) };
          }
        };
      }
    } },
    MediaService: { MediaService: class { model = { defaultFrameRate: 24 }; resolveModelInputSize(size) { return size; } } },
    MediaTimeline: { MediaTimeline: { currentTimestampUs: () => 1000 } }
  }, {
    setInterval: callback => { intervals.set(++intervalId, callback); return intervalId; },
    clearInterval: id => intervals.delete(id)
  });
  const { XmaxRealtimeErrorManager } = f.load('core/realtime/XmaxRealtimeErrorManager.ets');
  const errorManager = new XmaxRealtimeErrorManager();
  const { ImageController } = f.load('media/image/ImageController.ets');
  const controller = new ImageController({
    useExternalVideoSource() {}, renderLibraryName: () => 'rtc', unbindLocalVideo() {}
  }, {
    setVideoEncoderConfig() {}, pushLocalVideoFrame() { if (failure !== undefined) throw failure; }
  }, error => { received.push(error); errorManager.handle(error); });
  t.after(async () => { await controller.stopLocalImageStream(); assert.equal(intervals.size, 0); });
  return { ...f, controller, received, intervals,
    start: () => controller.createLocalImageStream('test-image'),
    failWith(error) { failure = error; },
    tick() { assert.equal(intervals.size, 1); [...intervals.values()][0](); }
  };
}

test('image push errors preserve their identity, code and details through the internal error router', async t => {
  const f = imageFixture(t);
  await f.start();
  const rtcError = new f.XmaxError(f.Code.RTC_ERROR, 'retry frame', 1003, 503);
  const apiError = new f.XmaxError(f.Code.API_ERROR, 'API frame failure', 1004, 500);
  const cancelled = new f.XmaxError(f.Code.CANCELLED, 'stopped');
  for (const error of [rtcError, apiError, cancelled]) {
    f.failWith(error);
    f.tick(); f.tick();
    assert.equal(f.received.at(-1), error);
    assert.equal(f.received.at(-2), error);
  }
  assert.equal(f.logs.length, 0); // Error forwarding does not depend on logging.
});

test('ordinary image push exceptions use the shared XmaxError conversion instead of MEDIA_ERROR', async t => {
  const f = imageFixture(t);
  await f.start();
  f.failWith(new Error('native frame failure')); f.tick();
  const error = f.received[0];
  assert.ok(error instanceof f.XmaxError);
  assert.equal(error.code, f.Code.INTERNAL_ERROR);

  assert.equal(error.message, 'native frame failure');
});

test('first image push failure rejects creation with the original error and does not start the frame timer', async t => {
  const f = imageFixture(t);
  const error = new f.XmaxError(f.Code.RTC_ERROR, 'first frame rejected', undefined, undefined);
  f.failWith(error);
  await assert.rejects(f.start(), actual => actual === error);
  assert.equal(f.intervals.size, 0);
  assert.deepEqual(f.received, []); // Synchronous creation failure is returned by the operation promise.
});

test('errors retain identity and API/HTTP details without a severity API', () => {
  const f = fixture();
  assert.equal(f.load('foundation/errors/XmaxError.ets').XmaxErrorSeverity, undefined);
  for (const code of Object.values(f.Code)) {
    const error = new f.XmaxError(code, 'message', 1003, 503);
    assert.equal(error.code, code);
    assert.equal(error.apiCode, 1003);
    assert.equal(error.httpStatus, 503);
    assert.equal(f.XmaxError.from(error), error);
    assert.equal('severity' in error, false);
    assert.equal(typeof error.withSeverity, 'undefined');
  }
  const converted = f.XmaxError.from(new Error('platform'));
  assert.equal(converted.code, f.Code.INTERNAL_ERROR);
  assert.equal(converted.message, 'platform');
});

test('error logging preserves original errors and deduplicates each object without a public callback', () => {
  const f = fixture();
  const { XmaxRealtimeErrorManager } = f.load('core/realtime/XmaxRealtimeErrorManager.ets');
  const handler = new XmaxRealtimeErrorManager();
  f.Logger.configure(f.Option.ALL);
  const error = new f.XmaxError(f.Code.RTC_ERROR, 'lost', 123, 503);
  assert.equal(handler.handle(error), error);
  handler.handle(error);
  assert.equal(f.logs.length, 1);
  assert.match(f.logs[0].message, /123/);
  assert.match(f.logs[0].message, /503/);
});

test('logging defaults off for every level, filters options independently and skips lazy formatting', () => {
  const f = fixture(); let formatted = 0;
  const message = () => { formatted++; return 'message'; };
  for (const level of ['debug', 'info', 'warn', 'error']) f.Logger[level](message);
  assert.equal(f.logs.length, 0); assert.equal(formatted, 0);
  f.Logger.configure(f.Option.BUSINESS);
  f.Logger.error(message, 'API'); f.Logger.debug(message, 'RTC', f.Option.PERFORMANCE);
  assert.equal(f.logs.length, 1); assert.equal(formatted, 1);
  f.Logger.configure(f.Option.PERFORMANCE);
  f.Logger.error(message, 'API'); f.Logger.debug(message, 'RTC', f.Option.PERFORMANCE);
  assert.equal(f.logs.length, 2); assert.equal(formatted, 2);
  f.Logger.configure(f.Option.BUSINESS | f.Option.PERFORMANCE);
  assert.equal(f.Logger.isEnabled(f.Option.ALL), true);
  assert.equal(f.Logger.isEnabled(f.Option.NONE), false);
  f.Logger.configure(f.Option.NONE); f.Logger.error(message);
  assert.equal(f.logs.length, 2);
});

test('client applies environment and global loggerOptions; defaults remain China and logging off', () => {
  const services = [];
  const f = fixture({
    ApiService: { ApiService: class {
      constructor(apiKey, baseURL) { services.push({ apiKey, baseURL }); }
    } }, XmaxRealtimeManager: {}, XmaxStorageManager: {}
  });
  const { XmaxConfiguration } = f.load('core/XmaxConfiguration.ets');
  const { XmaxEnvironment, apiBaseURL } = f.load('core/XmaxEnvironment.ets');
  const { XmaxClient } = f.load('core/XmaxClient.ets');
  const config = new XmaxConfiguration('  test-key\n', XmaxEnvironment.CHINA, f.Option.ALL);
  assert.equal(config.apiKey, 'test-key');
  assert.equal(config.environment, XmaxEnvironment.CHINA);
  new XmaxClient(config);
  assert.deepEqual(services[0], {
    apiKey: 'test-key', baseURL: 'https://cloud.xmax.22duck.cn/open/api/v1'
  });
  assert.equal(f.Logger.isEnabled(f.Option.PERFORMANCE), true);
  assert.equal(f.Logger.isEnabled(f.Option.BUSINESS), true);
  const defaultConfiguration = new XmaxConfiguration('test-key');
  assert.equal(defaultConfiguration.environment, XmaxEnvironment.CHINA);
  new XmaxClient(defaultConfiguration);
  assert.equal(f.Logger.isEnabled(f.Option.BUSINESS), false);
  const legacyConfiguration = new XmaxConfiguration('legacy-key', f.Option.ALL);
  assert.equal(legacyConfiguration.environment, XmaxEnvironment.CHINA);
  assert.equal(legacyConfiguration.loggerOptions, f.Option.ALL);
  const globalConfiguration = new XmaxConfiguration('global-key', XmaxEnvironment.GLOBAL);
  new XmaxClient(globalConfiguration);
  assert.equal(f.Logger.localized('中文', 'English'), 'English');
  assert.deepEqual(services[2], {
    apiKey: 'global-key', baseURL: 'https://api.xmax.cloud/open/api/v1'
  });
  assert.equal(apiBaseURL(XmaxEnvironment.GLOBAL), 'https://api.xmax.cloud/open/api/v1');
  new XmaxClient(defaultConfiguration);
  assert.equal(f.Logger.localized('中文', 'English'), '中文');
  assert.throws(() => new XmaxConfiguration(' ').validate(), { code: 'INVALID_API_KEY' });
});

test('logs prefix each line, omit blank categories and retain credential redaction', () => {
  const f = fixture(); f.Logger.configure(f.Option.ALL);
  f.Logger.info('first\nsecond', '  Storage ');
  f.Logger.info('ready', '   ');
  assert.equal(f.logs[0].message, '[Xmax][Storage] first\n[Xmax][Storage] second');
  assert.equal(f.logs[1].message, '[Xmax] ready');
  f.Logger.error('Authorization: Bearer bearer-credential\n{"token":"json-credential"}\napi_key=plain-credential');
  assert.doesNotMatch(f.logs[2].message, /bearer-credential|json-credential|plain-credential/);
});

test('RTC statistics/alarm logging is performance-only and does no formatting when disabled', () => {
  const f = fixture({ '@bytertc/volcenginertc': { PerformanceAlarmReason: {}, NetworkQuality: {} } });
  const { RtcStatsLogger } = f.load('foundation/rtc/RtcStatsLogger.ets');
  const inaccessible = new Proxy({}, { get() { throw new Error('formatting ran'); } });
  f.Logger.configure(f.Option.BUSINESS);
  assert.doesNotThrow(() => {
    RtcStatsLogger.logLocalStreamStats(inaccessible);
    RtcStatsLogger.logRemoteStreamStats(inaccessible);
    RtcStatsLogger.logNetworkQuality(inaccessible, []);
    RtcStatsLogger.logPerformanceAlarm(0, inaccessible);
  });
  f.Logger.configure(f.Option.PERFORMANCE);
  RtcStatsLogger.logPerformanceAlarm(0, { width: 1024, height: 1920, frame_rate: 30 });
  assert.equal(f.logs.length, 1);
  assert.match(f.logs[0].message, /RTC.*性能告警/);
});

test('API response logging uses business option only', () => {
  const f = fixture();
  const { ApiLogger } = f.load('service/network/ApiLogger.ets');
  f.Logger.configure(f.Option.PERFORMANCE);
  ApiLogger.logResponse('POST', '/session', 500, '{"token":"test-secret"}', 12, false);
  assert.equal(f.logs.length, 0);
  f.Logger.configure(f.Option.BUSINESS);
  ApiLogger.logResponse('POST', '/session', 500, '{"token":"test-secret"}', 12, false);
  assert.equal(f.logs.length, 1);
  assert.doesNotMatch(f.logs[0].message, /test-secret/);
});

function roomFixture() {
  const f = fixture({ RoomHeartbeat: { RoomHeartbeat: class {} } });
  const { RoomController } = f.load('stream/room/RoomController.ets');
  const failure = new f.XmaxError(f.Code.RTC_ERROR, 'send failed', 1003, 500);
  const room = new RoomController({ sendRoomMessage() { throw failure; } });
  room.localUserId = 'user';
  return { ...f, room, failure };
}

test('start, condition and trajectory failures preserve identity; stop failures only log', () => {
  const f = roomFixture(), format = { width: 1024, height: 1920, fps: 30 }, context = { prompt: 'test' };
  assert.throws(() => f.room.startGeneration('task', format, context), error => error === f.failure);
  assert.throws(() => f.room.changeGenerationCondition('task', format, context), error => error === f.failure);
  assert.throws(() => f.room.sendTracks('task', [{ x: 0, y: 0 }]), error => error === f.failure);
  f.Logger.configure(f.Option.BUSINESS);
  assert.doesNotThrow(() => f.room.stopGeneration('task'));
  assert.match(f.logs.at(-1).message, /send failed/);
  assert.doesNotMatch(f.logs.at(-1).message, /级别/);
});

test('session close failures preserve the original error', async () => {
  const f = fixture();
  const { RealtimeSessionService } = f.load('service/realtime/RealtimeSessionService.ets');
  const original = new f.XmaxError(f.Code.API_ERROR, 'close failed', 1003, 500);
  const service = new RealtimeSessionService({ async delete() { throw original; } });
  await assert.rejects(service.closeSession('test'), error => error === original);
});

function streamFixture() {
  const f = fixture({
    RoomController: { RoomController: class { startGeneration() {} stopGeneration() {} } },
    QualityController: { QualityController: class {} }, EncodingController: { EncodingController: class {} }
  });
  const { StreamController } = f.load('stream/StreamController.ets');
  const received = [];
  const rtc = { setEventListener() {}, setRemoteAudioVolume() {},
    subscribeRemoteVideo() { throw new f.XmaxError(f.Code.RTC_ERROR, 'video subscription failed'); },
    subscribeRemoteAudio() { throw new f.XmaxError(f.Code.RTC_ERROR, 'audio subscription failed'); }
  };
  const stream = new StreamController(rtc, () => {}, error => received.push(error));
  stream.botName = 'bot';
  return { ...f, stream, rtc, received };
}

test('subscription failure rejects startup promptly, or forwards a running failure once', async () => {
  const f = streamFixture();
  const starting = f.stream.beginGeneration('task', {}, {});
  assert.doesNotThrow(() => f.stream.onRemoteVideoPublished('bot', true));
  await assert.rejects(starting, { message: 'video subscription failed' });
  assert.equal(f.received.length, 0);
  f.stream.stopGeneration('task');
  f.stream.onRemoteVideoPublished('other-user', true);
  assert.equal(f.received.length, 0);
  f.stream.onRemoteVideoPublished('bot', true);
  assert.equal(f.received.length, 1);

  f.Logger.configure(f.Option.BUSINESS);
  f.stream.subscribedRemoteAudioUsers.add('bot');
  f.stream.onRemoteAudioPublished('bot', false);
  assert.equal(f.received.length, 1);
  assert.match(f.logs.at(-1).message, /取消远端音频订阅失败/);

});

test('synchronous start signal failure returns one rejected promise with the original failure', async () => {
  const f = streamFixture();
  f.stream.roomController.startGeneration = () => { throw new f.XmaxError(f.Code.RTC_ERROR, 'start failed'); };
  let starting;
  assert.doesNotThrow(() => { starting = f.stream.beginGeneration('task', {}, {}); });
  await assert.rejects(starting, { message: 'start failed' });
  f.stream.stopGeneration('task');
});

test('audio volume callback errors are forwarded for an activated remote stream', () => {
  const f = streamFixture();
  f.stream.remoteAudioActive = true;
  f.stream.activeRemoteStream = { roomId: 'room', userId: 'bot' };
  f.rtc.setRemoteAudioVolume = () => { throw new f.XmaxError(f.Code.RTC_ERROR, 'volume failed'); };
  assert.doesNotThrow(() => f.stream.onRemoteAudioPublished('bot', true));
  assert.equal(f.received.length, 1);

});

test('remote surface bind failure reaches the runtime failure listener without escaping the UI callback', () => {
  const f = fixture(), received = [];
  const { RenderController } = f.load('rendering/RenderController.ets');
  const { RealtimeVideoTrack } = f.load('service/realtime/RealtimeVideoTrack.ets');
  const { RemoteStream } = f.load('foundation/rtc/RemoteStream.ets');
  const { VideoRenderRegistry } = f.load('rendering/video/VideoRenderRegistry.ets');
  const render = new RenderController({
    setRemoteVideoFrameListener() {}, observeRemoteVideoFrames() {},
    setRemoteVideoRenderedListener() {}, renderLibraryName() { return 'rtc'; },
    bindRemoteVideo() { throw new f.XmaxError(f.Code.RTC_ERROR, 'bind failed'); },
    unbindRemoteVideo() {}
  }, error => received.push(error));
  const track = new RealtimeVideoTrack('remote');
  render.registerRemoteTrack(track, {});
  render.setRemoteStream(new RemoteStream('room', 'bot'));
  assert.doesNotThrow(() => VideoRenderRegistry.attach(track, 'surface', 0, () => {}, () => {}));
  assert.equal(received.length, 1);

  render.resetRemoteTrack(track);
});

test('cleanup failures do not reject generation startup or reenter runtime error handling', async () => {
  const f = streamFixture();
  f.Logger.configure(f.Option.BUSINESS);
  const starting = f.stream.beginGeneration('task', {}, {});
  let completed = false;
  starting.then(() => { completed = true; }, () => { completed = true; });
  f.stream.subscribedRemoteAudioUsers.add('bot');
  f.stream.onRemoteAudioPublished('bot', false);
  f.stream.activeRemoteStream = { roomId: 'room', userId: 'bot' };
  f.stream.remoteStreamListener = () => { throw new f.XmaxError(f.Code.RTC_ERROR, 'clear stream failed'); };
  f.stream.onRemoteVideoPublished('bot', false);
  await Promise.resolve();
  assert.equal(completed, false);
  assert.deepEqual(f.received, []);
  assert.match(f.logs.at(-1).message, /clear stream failed/);
  f.stream.remoteStreamListener = () => {};
  f.stream.stopGeneration('task');
  await assert.rejects(starting, { code: f.Code.CANCELLED });
});

test('stopping frame observation only logs failures and leaves no frame waiters', () => {
  const f = fixture(), failures = [];
  f.Logger.configure(f.Option.BUSINESS);
  const { RenderController } = f.load('rendering/RenderController.ets');
  const { RemoteStream } = f.load('foundation/rtc/RemoteStream.ets');
  const render = new RenderController({
    setRemoteVideoFrameListener() {}, setRemoteVideoRenderedListener() {}, unbindRemoteVideo() {},
    observeRemoteVideoFrames(_stream, enabled) { if (!enabled) throw new Error('stop observation failed'); }
  }, error => failures.push(error));
  render.setRemoteStream(new RemoteStream('room', 'bot'));
  render.setRemoteStream(null);
  assert.deepEqual(failures, []);
  assert.match(f.logs.at(-1).message, /stop observation failed/);
  assert.equal(render.remoteFrameWaiters.size, 0);
});

test('global log details are English while raw payloads, error codes and redaction are preserved', () => {
  const f = fixture();
  const { XmaxEnvironment: Environment } = f.load('core/XmaxEnvironment.ets');
  const { ApiLogger } = f.load('service/network/ApiLogger.ets');
  const { ErrorMessageFormatter } = f.load('foundation/errors/ErrorMessageFormatter.ets');
  f.Logger.configure(f.Option.ALL, Environment.GLOBAL);
  assert.equal(f.Logger.localized('中文', 'English'), 'English');
  const error = new f.XmaxError(f.Code.API_ERROR, '原始错误', 1003, 503);
  const detail = ErrorMessageFormatter.format(error);
  assert.equal(detail, '原始错误 (API_ERROR, API Code 1003, HTTP 503)');
  assert.equal(error.message, '原始错误');
  assert.equal(ErrorMessageFormatter.format({ code: 42, message: 'platform' }), 'platform (Platform Error Code: 42)');
  ApiLogger.logResponse('POST', '/session', 503, '{"message":"原始数据","token":"secret-value"}', 12, false);
  const log = f.logs.at(-1).message;
  assert.match(log, /Status: 503/); assert.match(log, /Duration: 12 ms/);
  assert.match(log, /原始数据/); assert.doesNotMatch(log, /secret-value/);
  f.Logger.configure(f.Option.NONE, Environment.GLOBAL);
  ApiLogger.logFailure('POST', '/session', error, 10);
  assert.equal(f.logs.length, 1);
  f.Logger.configure(f.Option.ALL);
  assert.equal(f.Logger.localized('中文', 'English'), '中文');
});

test('RTC performance details follow the global log language and retain bilingual headings', () => {
  const f = fixture({ '@bytertc/volcenginertc': { PerformanceAlarmReason: {}, NetworkQuality: { kNetworkQualityGood: 1 } } });
  const { XmaxEnvironment: Environment } = f.load('core/XmaxEnvironment.ets');
  const { RtcStatsLogger } = f.load('foundation/rtc/RtcStatsLogger.ets');
  f.Logger.configure(f.Option.PERFORMANCE, Environment.GLOBAL);
  RtcStatsLogger.logNetworkQuality({ tx_quality: 1, fraction_lost: 0, total_bandwidth: 1000, rtt: 20 }, []);
  const log = f.logs.at(-1).message;
  assert.match(log, /网络质量 \(Network Quality\)/);
  assert.match(log, /Quality: Good/);
  assert.match(log, /RTT 20 ms, Bandwidth/);
  assert.doesNotMatch(log.split('\n').slice(1).join('\n'), /[\u4e00-\u9fff]/);
});
