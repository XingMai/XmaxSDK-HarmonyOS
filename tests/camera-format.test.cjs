const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { loadEts } = require('./ets-loader.cjs');
const { createCameraKitFixture } = require('./camera-kit-fixture.cjs');

function fixture() {
  const calls = [], frames = [], errors = [], notifications = [];
  const kit = createCameraKitFixture(calls);
  const load = loadEts({
    '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
    '@kit.CameraKit': kit.kit, CameraFrameOutput: kit.frameOutput,
    PermissionManager: { PermissionManager: class {
      async ensureCameraPermission() {} async ensureMicrophonePermission() {}
    } },
    VideoController: { VideoController: class {} },
    ImageController: { ImageController: class {} },
    InteractionController: { InteractionController: class {} },
    XmaxLogger: { XmaxLogger: { info() {}, debug() {}, error() {} } }
  });
  const { MediaController } = load('media/MediaController.ets');
  const { MediaService } = load('service/media/MediaService.ets');
  const { RealtimeModels } = load('service/realtime/RealtimeModel.ets');
  const { RealtimeVideoFormat: Format } = load('service/realtime/RealtimeVideoFormat.ets');
  const { VideoRenderRegistry: Registry } = load('rendering/video/VideoRenderRegistry.ets');
  let failEncoding;
  const rtc = {
    async initialize() { calls.push(['initialize']); }, async destroy() { calls.push(['destroy']); },
    useExternalVideoSource() {}, configureLocalVideoMirror() {}, renderLibraryName: () => 'rtc',
    bindLocalVideo() { calls.push(['bind']); }, unbindLocalVideo() { calls.push(['unbind']); }
  };
  const model = RealtimeModels.realtime('x2.0-sla');
  const media = new MediaController({}, rtc, {
    setVideoEncoderConfig(format) {
      if (failEncoding) { const error = failEncoding; failEncoding = null; throw error; }
      calls.push(['encode', format]);
    },
    pushLocalVideoFrame(frame) { frames.push(frame); }
  }, error => errors.push(error), new MediaService(model), format => notifications.push(format));
  return { media, kit, calls, frames, errors, notifications, Format, Registry, model,
    failEncoding(error) { failEncoding = error; },
    create: () => media.createLocalCameraStream(new Format(1080, 1920, 24, 1500, 6000, 'MaintainQuality'), 'front', true)
  };
}

test('camera format changes preserve capture, microphone configuration, track, and bound views for all five ratios', async () => {
  const f = fixture(), local = await f.create(), track = local.videoTrack, observed = [];
  f.Registry.attach(track, 'view', 'fit', () => {}, () => {}, undefined,
    () => observed.push(track.videoFormat));
  const captureCalls = f.calls.filter(call => call[0].startsWith('camera-'));
  try {
    for (const size of f.model.resolutionBuckets) {
      const format = track.videoFormat.resized(size.width, size.height);
      await f.media.updateCameraFormat(format);
      assert.equal(f.media.currentTrack, track);
      assert.deepEqual(track.videoFormat, format);
      assert.deepEqual(observed.at(-1), format);
      assert.equal(f.media.hasAudio, true);
      assert.equal(f.Registry.libraryName(track), 'rtc');
      assert.equal(f.calls.filter(call => call[0] === 'bind').length, 1);
      assert.equal(f.calls.some(call => ['unbind', 'destroy'].includes(call[0])), false);
      assert.equal(f.kit.outputs.length, 1);
    }
    assert.deepEqual(f.calls.filter(call => call[0].startsWith('camera-')), captureCalls);
    assert.deepEqual(f.errors, []);
  } finally { await f.media.stopLocalCameraStream(); }
});

test('old-size queued camera frames are dropped after a ratio change without reverting track metadata', async () => {
  const f = fixture(), local = await f.create();
  try {
    await f.media.updateCameraFormat(local.videoTrack.videoFormat.resized(1920, 1080));
    f.kit.emit({ format: { width: 1080, height: 1920 } });
    assert.equal(f.frames.length, 0);
    assert.equal(local.videoTrack.videoFormat.width, 1920);
    f.kit.emit({ format: { width: 1920, height: 1080 } });
    assert.equal(f.frames.length, 1);
    assert.equal(f.frames[0].format.width, 1920);
    assert.deepEqual(f.errors, []);
  } finally { await f.media.stopLocalCameraStream(); }
});

test('camera rejects invalid dimensions and frame rates before changing live output', async () => {
  const f = fixture();
  await assert.rejects(f.media.updateCameraFormat(new f.Format(1408, 1408, 30)), { code: 'INVALID_CONFIGURATION' });
  const local = await f.create(), original = local.videoTrack.videoFormat;
  try {
    for (const format of [new f.Format(1024, 1920, 30), new f.Format(1408, 1408, 31),
      new f.Format(1408, 1408, 0), new f.Format(1408, 1408, 30, 6000, 100)]) {
      const before = f.calls.length;
      await assert.rejects(f.media.updateCameraFormat(format), { code: 'INVALID_CONFIGURATION' });
      assert.equal(local.videoTrack.videoFormat, original);
      assert.equal(f.kit.outputs[0].currentVideoFormat, original);
      assert.equal(f.calls.length, before);
    }
  } finally { await f.media.stopLocalCameraStream(); }
});

test('failed camera encoding updates restore output and retain the previous preview binding', async () => {
  const f = fixture(), local = await f.create(), original = local.videoTrack.videoFormat;
  f.failEncoding(new Error('encoder configuration failed'));
  try {
    await assert.rejects(f.media.updateCameraFormat(original.resized(1408, 1408)), /encoder configuration failed/);
    assert.equal(f.media.currentTrack, local.videoTrack);
    assert.equal(local.videoTrack.videoFormat, original);
    assert.equal(f.kit.outputs[0].currentVideoFormat, original);
    f.kit.emit({ format: { width: 1080, height: 1920 } });
    assert.equal(f.frames.length, 1);
    assert.equal(f.calls.some(call => ['destroy', 'unbind'].includes(call[0])), false);
    assert.deepEqual(f.errors, []);
    await f.media.updateCameraFormat(original.resized(1408, 1408));
    assert.equal(local.videoTrack.videoFormat.width, 1408);
  } finally { await f.media.stopLocalCameraStream(); }
});

test('camera format updates preserve bitrate-only changes and the chosen ratio across lens switches', async () => {
  const f = fixture(), local = await f.create();
  try {
    const format = new f.Format(1920, 1080, 24, 100, 5000, 'MaintainFramerate');
    await f.media.updateCameraFormat(format);
    const encoding = new f.Format(1920, 1080, 24, 200, 7000, 'MaintainQuality');
    await f.media.updateCameraFormat(encoding);
    assert.deepEqual(local.videoTrack.videoFormat, encoding);
    const switched = await f.media.switchCamera();
    assert.equal(switched.videoTrack, local.videoTrack);
    assert.equal(switched.videoTrack.position, 'back');
    assert.deepEqual(switched.videoTrack.videoFormat, encoding);
  } finally { await f.media.stopLocalCameraStream(); }
});

test('XLab ratio controls use model formats and are disabled during format or camera switching', () => {
  const root = path.resolve(__dirname, '../examples/XLab/entry/src/main');
  const button = fs.readFileSync(path.join(root,
    'ets/modules/xlrealtime/mvvm/view/RealtimeCameraFormatButton.ets'), 'utf8');
  const page = fs.readFileSync(path.join(root, 'ets/modules/xlrealtime/RealtimePage.ets'), 'utf8');
  assert.match(button, /ForEach\(this\.state\.supportedCameraFormats/);
  assert.match(button, /\.enabled\(this\.state\.canUpdateCameraFormat && !this\.isCameraSwitching\)/);
  assert.match(page, /\.enabled\(!this\.isCameraSwitchTransitionActive && !this\.state\.isCameraFormatUpdating\)/);
  assert.match(page, /\.enabled\(!this\.state\.isCameraFormatUpdating\)/);
  assert.match(page, /supportedCameraFormats\.length > 1/);
  for (const locale of ['base', 'zh_Hans']) {
    const strings = JSON.parse(fs.readFileSync(path.join(root, 'resources', locale, 'element/string.json'))).string;
    assert.equal(strings.filter(value => value.name === 'camera_format').length, 1);
  }
  assert.ok(fs.existsSync(path.join(root, 'resources/base/media/realtime_camera_format.svg')));
});
