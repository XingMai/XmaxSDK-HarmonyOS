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
  const { XmaxError, XmaxErrorCode: Code, XmaxErrorSeverity: Severity } = load('foundation/errors/XmaxError.ets');
  return { load, logs, Logger, Option, XmaxError, Code, Severity };
}

function imageFixture(t) {
  const intervals = new Map(), received = [], fatal = [];
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
  errorManager.setListener(error => fatal.push(error));
  const { ImageController } = f.load('media/image/ImageController.ets');
  const controller = new ImageController({
    useExternalVideoSource() {}, renderLibraryName: () => 'rtc', unbindLocalVideo() {}
  }, {
    setVideoEncoderConfig() {}, pushLocalVideoFrame() { if (failure !== undefined) throw failure; }
  }, error => { received.push(error); errorManager.handle(error); });
  t.after(async () => { await controller.stopLocalImageStream(); assert.equal(intervals.size, 0); });
  return { ...f, controller, received, fatal, intervals,
    start: () => controller.createLocalImageStream('test-image'),
    failWith(error) { failure = error; },
    tick() { assert.equal(intervals.size, 1); [...intervals.values()][0](); }
  };
}

test('image push errors preserve their identity, code, severity and details through the public error router', async t => {
  const f = imageFixture(t);
  await f.start();
  const recoverable = new f.XmaxError(f.Code.RTC_ERROR, 'retry frame', 1003, 503, f.Severity.RECOVERABLE);
  const fatal = new f.XmaxError(f.Code.API_ERROR, 'fatal frame', 1004, 500, f.Severity.FATAL);
  const cancelled = new f.XmaxError(f.Code.CANCELLED, 'stopped');
  for (const error of [recoverable, fatal, cancelled]) {
    f.failWith(error);
    f.tick(); f.tick();
    assert.equal(f.received.at(-1), error);
    assert.equal(f.received.at(-2), error);
  }
  assert.deepEqual(f.fatal, [fatal]); // Recoverable/cancelled stay internal; repeated fatal instance is deduplicated.
  assert.equal(f.logs.length, 0); // Error forwarding does not depend on logging.
});

test('ordinary image push exceptions use the shared XmaxError conversion instead of MEDIA_ERROR', async t => {
  const f = imageFixture(t);
  await f.start();
  f.failWith(new Error('native frame failure')); f.tick();
  const error = f.received[0];
  assert.ok(error instanceof f.XmaxError);
  assert.equal(error.code, f.Code.INTERNAL_ERROR);
  assert.equal(error.severity, f.Severity.FATAL);
  assert.equal(error.message, 'native frame failure');
  assert.equal(f.fatal[0], error);
});

test('first image push failure rejects creation with the original error and does not start the frame timer', async t => {
  const f = imageFixture(t);
  const error = new f.XmaxError(f.Code.RTC_ERROR, 'first frame rejected', undefined, undefined, f.Severity.RECOVERABLE);
  f.failWith(error);
  await assert.rejects(f.start(), actual => actual === error);
  assert.equal(f.intervals.size, 0);
  assert.deepEqual(f.received, []); // Synchronous creation failure is returned by the operation promise.
});

test('error defaults match iOS, with backwards-compatible API and HTTP error details', () => {
  const f = fixture();
  const recoverable = ['INVALID_API_KEY', 'INVALID_CONFIGURATION', 'CAMERA_PERMISSION_DENIED',
    'MICROPHONE_PERMISSION_DENIED', 'CANCELLED'];
  for (const code of Object.values(f.Code)) {
    const error = new f.XmaxError(code, 'message', 1003, 503);
    assert.equal(error.severity, recoverable.includes(code) ? f.Severity.RECOVERABLE : f.Severity.FATAL);
    assert.equal(error.apiCode, 1003); assert.equal(error.httpStatus, 503);
    assert.equal(f.XmaxError.from(error), error);
    const downgraded = error.withSeverity(f.Severity.RECOVERABLE);
    assert.equal(downgraded.code, code); assert.equal(downgraded.message, 'message');
    assert.equal(downgraded.apiCode, 1003); assert.equal(downgraded.httpStatus, 503);
    assert.equal(downgraded.severity, f.Severity.RECOVERABLE);
  }
  assert.equal(new f.XmaxError(f.Code.RTC_ERROR, 'retry', undefined, undefined,
    f.Severity.RECOVERABLE).severity, f.Severity.RECOVERABLE);
  assert.equal(f.XmaxError.from(new Error('platform')).severity, f.Severity.FATAL);
});

test('fatal listener works with logging disabled; recoverable errors and cancellation are not forwarded', () => {
  const f = fixture(), received = [];
  const { XmaxRealtimeErrorManager } = f.load('core/realtime/XmaxRealtimeErrorManager.ets');
  const handler = new XmaxRealtimeErrorManager();
  handler.setListener(error => received.push(error));
  for (const code of [f.Code.INVALID_CONFIGURATION, f.Code.CANCELLED, f.Code.CAMERA_PERMISSION_DENIED]) {
    handler.handle(new f.XmaxError(code, 'recoverable'));
  }
  const fatal = new f.XmaxError(f.Code.RTC_ERROR, 'fatal');
  assert.equal(handler.handle(fatal), fatal);
  handler.handle(fatal); // same failure caught again by an outer SDK operation
  assert.deepEqual(received, [fatal]);
  assert.equal(f.logs.length, 0);
  handler.setListener(null);
  handler.handle(new f.XmaxError(f.Code.MEDIA_ERROR, 'after removal'));
  assert.equal(received.length, 1);
});

test('error logging includes severity once and a throwing listener cannot replace the original failure', () => {
  const f = fixture(); f.Logger.configure(f.Option.BUSINESS);
  const { XmaxRealtimeErrorManager } = f.load('core/realtime/XmaxRealtimeErrorManager.ets');
  const handler = new XmaxRealtimeErrorManager();
  const recoverable = new f.XmaxError(f.Code.RTC_ERROR, 'retry').withSeverity(f.Severity.RECOVERABLE);
  handler.handle(recoverable); handler.handle(recoverable);
  assert.equal(f.logs.length, 1);
  assert.match(f.logs[0].message, /RECOVERABLE/);
  handler.setListener(() => { throw new Error('host callback failure'); });
  const fatal = new f.XmaxError(f.Code.MEDIA_ERROR, 'decoder failed');
  assert.equal(handler.handle(fatal), fatal);
  assert.equal(f.logs.length, 3);
  assert.match(f.logs[1].message, /FATAL/);
  assert.match(f.logs[2].message, /host callback failure/);
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
  assert.deepEqual(services[2], {
    apiKey: 'global-key', baseURL: 'https://api.xmax.cloud/open/api/v1'
  });
  assert.equal(apiBaseURL(XmaxEnvironment.GLOBAL), 'https://api.xmax.cloud/open/api/v1');
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
    RtcStatsLogger.logSystemStats(inaccessible);
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

test('start signal is fatal; condition/trajectory updates and stop failures are recoverable', () => {
  const f = roomFixture(), format = { width: 1024, height: 1920, fps: 30 }, context = { prompt: 'test' };
  assert.throws(() => f.room.startGeneration('task', format, context), { severity: f.Severity.FATAL });
  assert.throws(() => f.room.changeGenerationCondition('task', format, context), {
    severity: f.Severity.RECOVERABLE, apiCode: 1003, httpStatus: 500
  });
  assert.throws(() => f.room.sendTracks('task', [{ x: 0, y: 0 }]), { severity: f.Severity.RECOVERABLE });
  f.Logger.configure(f.Option.BUSINESS);
  assert.doesNotThrow(() => f.room.stopGeneration('task'));
  assert.match(f.logs.at(-1).message, /RECOVERABLE/);
});

test('session close errors keep error details but become recoverable', async () => {
  const f = fixture();
  const { RealtimeSessionService } = f.load('service/realtime/RealtimeSessionService.ets');
  const service = new RealtimeSessionService({ async delete() {
    throw new f.XmaxError(f.Code.API_ERROR, 'close failed', 1003, 500);
  } });
  await assert.rejects(service.closeSession('test'), {
    code: f.Code.API_ERROR, severity: f.Severity.RECOVERABLE, apiCode: 1003, httpStatus: 500
  });
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
  await assert.rejects(starting, { message: 'video subscription failed', severity: f.Severity.FATAL });
  assert.equal(f.received.length, 0);
  f.stream.stopGeneration('task');
  f.stream.onRemoteVideoPublished('other-user', true);
  assert.equal(f.received.length, 0);
  f.stream.onRemoteVideoPublished('bot', true);
  assert.equal(f.received.length, 1);
  assert.equal(f.received[0].severity, f.Severity.FATAL);
  f.stream.subscribedRemoteAudioUsers.add('bot');
  f.stream.onRemoteAudioPublished('bot', false);
  assert.equal(f.received.at(-1).severity, f.Severity.RECOVERABLE);
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
  assert.equal(f.received[0].severity, f.Severity.FATAL);
});

test('remote surface bind failure reaches the fatal listener without escaping the UI callback', () => {
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
  assert.equal(received[0].severity, f.Severity.FATAL);
  render.resetRemoteTrack(track);
});
