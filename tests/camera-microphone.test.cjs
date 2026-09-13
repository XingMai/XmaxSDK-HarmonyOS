const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');
const { createCameraKitFixture } = require('./camera-kit-fixture.cjs');

function fixture() {
  const events = [], cameraCalls = [], kit = createCameraKitFixture(cameraCalls);
  const controls = { denied: false, startFailure: null, stopFailure: null };
  let XmaxError, Code;
  const load = loadEts({
    '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
    '@kit.CameraKit': kit.kit, CameraFrameOutput: kit.frameOutput,
    PermissionManager: { PermissionManager: class {
      async ensureCameraPermission() { events.push('camera-permission'); }
      async ensureMicrophonePermission() {
        events.push('microphone-permission');
        if (controls.denied) throw new XmaxError(Code.MICROPHONE_PERMISSION_DENIED, 'denied');
      }
    } },
    VideoController: { VideoController: class { hasAudio = true; } },
    ImageController: { ImageController: class {} },
    InteractionController: { InteractionController: class {} },
    XmaxLogger: { XmaxLogger: { info() {}, debug() {}, error() {} } }
  });
  ({ XmaxError, XmaxErrorCode: Code } = load('foundation/errors/XmaxError.ets'));
  const { MediaController } = load('media/MediaController.ets');
  const { RealtimeVideoFormat: Format } = load('service/realtime/RealtimeVideoFormat.ets');
  const rtc = {
    async initialize() {}, async destroy() { events.push('destroy'); },
    useExternalVideoSource() {}, configureLocalVideoMirror() {},
    renderLibraryName() { return 'rtc'; }, unbindLocalVideo() {},
    startMicrophoneCapture() { events.push('start-microphone'); if (controls.startFailure) throw controls.startFailure; },
    stopMicrophoneCapture() { events.push('stop-microphone'); if (controls.stopFailure) throw controls.stopFailure; }
  };
  const media = new MediaController({}, rtc, { setVideoEncoderConfig() {} }, () => {});
  return { media, events, cameraCalls, controls, XmaxError, Code,
    create: enabled => media.createLocalCameraStream(new Format(1024, 1920, 30), 'front', enabled) };
}

test('camera microphone defaults off and creates no permission or capture side effects', async () => {
  const f = fixture();
  await f.create();
  assert.equal(f.media.hasAudio, false);
  f.media.startMicrophoneCapture();
  f.media.stopMicrophoneCapture();
  await f.media.stopLocalStream();
  assert.deepEqual(f.events, ['camera-permission', 'destroy']);
});

test('enabled camera checks permission at creation, captures only on request and preserves configuration across switch/reconnect', async () => {
  const f = fixture();
  await f.create(true);
  assert.equal(f.media.hasAudio, true);
  assert.deepEqual(f.events, ['camera-permission', 'microphone-permission']);
  f.media.startMicrophoneCapture();
  f.media.startMicrophoneCapture();
  await f.media.switchCamera();
  assert.equal(f.media.hasAudio, true);
  assert.equal(f.events.filter(e => e === 'start-microphone').length, 1);
  assert.equal(f.events.includes('stop-microphone'), false);
  f.media.stopMicrophoneCapture();
  f.media.stopMicrophoneCapture();
  assert.equal(f.media.hasAudio, true);
  f.media.startMicrophoneCapture();
  f.media.prepareForClose();
  assert.deepEqual(f.events.slice(2), ['start-microphone', 'stop-microphone', 'start-microphone', 'stop-microphone']);
  await f.media.stopLocalStream();
  assert.equal(f.media.hasAudio, false);
  await f.create(false);
  f.media.startMicrophoneCapture();
  assert.equal(f.events.filter(e => e === 'start-microphone').length, 2);
  await f.media.stopLocalStream();
});

test('microphone permission denial rolls back creation before camera capture and permits retry', async () => {
  const f = fixture();
  f.controls.denied = true;
  await assert.rejects(f.create(true), { code: 'MICROPHONE_PERMISSION_DENIED' });
  assert.equal(f.media.currentTrack, null);
  assert.equal(f.media.hasAudio, false);
  assert.equal(f.cameraCalls.some(call => call[0] === 'camera-open'), false);
  assert.equal(f.events.includes('start-microphone'), false);
  f.controls.denied = false;
  await f.create(true);
  await f.media.stopLocalStream();
});

test('partial microphone startup failure is still stopped; a failed stop remains retryable', async () => {
  const f = fixture();
  await f.create(true);
  const original = new f.XmaxError(f.Code.RTC_ERROR, 'start failed');
  f.controls.startFailure = original;
  assert.throws(() => f.media.startMicrophoneCapture(), error => error === original);
  f.controls.stopFailure = new f.XmaxError(f.Code.RTC_ERROR, 'stop failed');
  assert.throws(() => f.media.stopMicrophoneCapture(), error => error === f.controls.stopFailure);
  f.controls.stopFailure = null;
  f.media.stopMicrophoneCapture();
  f.controls.startFailure = null;
  f.media.startMicrophoneCapture();
  await f.media.stopLocalStream();
  assert.deepEqual(f.events.slice(2), ['start-microphone', 'stop-microphone', 'stop-microphone', 'start-microphone', 'stop-microphone', 'destroy']);
});

test('RTC explicitly selects internal microphone or external PCM input and checks native failures', () => {
  const events = [];
  const load = loadEts({
    '@kit.ArkTS': { util: {} },
    '@bytertc/volcenginertc': { MirrorType: { kMirrorTypeNone: 0 },
      AudioSourceType: { kAudioSourceTypeInternal: 1, kAudioSourceTypeExternal: 0 } },
    XmaxLogger: { XmaxLogger: {} }, RtcEngineManager: {}
  });
  const { RtcManager } = load('foundation/rtc/RtcManager.ets');
  const rtc = new RtcManager({});
  const engine = {
    setAudioSourceType(type) { events.push(['source', type]); return 0; },
    startAudioCapture() { events.push(['start']); return 0; },
    stopAudioCapture() { events.push(['stop']); return 0; }
  };
  rtc.engineLease = { engine };
  rtc.startMicrophoneCapture(); rtc.stopMicrophoneCapture();
  rtc.startExternalAudioSource(); rtc.stopExternalAudioSource();
  rtc.startMicrophoneCapture();
  assert.deepEqual(events, [['source', 1], ['start'], ['stop'], ['source', 0], ['start'], ['stop'], ['source', 1], ['start']]);
  engine.startAudioCapture = () => -1;
  assert.throws(() => rtc.startMicrophoneCapture(), { code: 'RTC_ERROR' });
  engine.stopAudioCapture = () => -1;
  assert.throws(() => rtc.stopMicrophoneCapture(), { code: 'RTC_ERROR' });
  rtc.engineLease = null;
  assert.doesNotThrow(() => rtc.stopMicrophoneCapture());
});

test('failed camera switch and restoration stop the microphone when the local track is lost', async () => {
  const f = fixture();
  await f.create(true);
  f.media.startMicrophoneCapture();
  f.media.cameraController.startCamera = async () => { throw new f.XmaxError(f.Code.MEDIA_ERROR, 'capture unavailable'); };
  await assert.rejects(f.media.switchCamera(), { code: 'MEDIA_ERROR' });
  assert.equal(f.media.currentTrack, null);
  assert.equal(f.media.hasAudio, false);
  assert.equal(f.events.at(-1), 'stop-microphone');
  await f.media.stopLocalStream();
});
