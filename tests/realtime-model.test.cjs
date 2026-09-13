const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { loadEts } = require('./ets-loader.cjs');
const { createCameraKitFixture } = require('./camera-kit-fixture.cjs');

function fixture(stubs = {}, globals = {}) {
  const load = loadEts({
    '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
    XmaxLogger: { XmaxLogger: { configure() {}, debug() {}, error() {} } },
    ...stubs
  }, globals);
  const { RealtimeModel: Model, RealtimeModels: Models } = load('core/realtime/RealtimeModel.ets');
  const { MediaService } = load('service/media/MediaService.ets');
  const { ImageSize: Size } = load('service/media/ImageSize.ets');
  const { RealtimeVideoFormat: Format } = load('service/realtime/RealtimeVideoFormat.ets');
  return { load, Model, Models, MediaService, Size, Format };
}

test('model defaults and resolution buckets match iOS without media-source restrictions', () => {
  const f = fixture();
  for (const [name, buckets, maximum, fps, width, height] of [
    [f.Model.X2_0, [], 1280000, 30, 832, 1472],
    [f.Model.X2_0_PRO, [[1024, 1920], [1920, 1024]], 2100000, 30, 1024, 1920]
  ]) {
    const model = f.Models.realtime(name);
    assert.equal(model.name, name);
    assert.equal(model.minimumInputPixels, 600000);
    assert.equal(model.maximumInputPixels, maximum);
    assert.equal(model.inputSizeAlignment, 32);
    assert.equal(model.defaultFrameRate, fps);
    assert.deepEqual(model.defaultCameraVideoFormat, new f.Format(width, height, fps));
    assert.deepEqual(model.resolutionBuckets.map(size => [size.width, size.height]), buckets);
    model.resolutionBuckets.splice(0);
    assert.deepEqual(model.resolutionBuckets.map(size => [size.width, size.height]), buckets);
    assert.equal(model.supportedMediaSources, undefined);
  }
  for (const name of ['unknown-model', 'x2.0-sla']) {
    assert.throws(() => f.Models.realtime(name), { code: 'INVALID_CONFIGURATION' });
  }
});

test('Pro accepts only exact buckets in either orientation without rounding or resizing', () => {
  const f = fixture(), service = new f.MediaService(f.Models.realtime(f.Model.X2_0_PRO));
  for (const [width, height] of [[1024, 1920], [1920, 1024]]) {
    const size = new f.Size(width, height);
    assert.deepEqual(service.resolveModelInputSize(size), size);
  }
  for (const [width, height] of [[832, 1472], [1920, 1080], [512, 960], [2048, 3840],
    [1120, 1120], [1024, 1919.9], [1023.9, 1920], [0, 1920], [NaN, 1920], [Infinity, 1920]]) {
    assert.throws(() => service.resolveModelInputSize(new f.Size(width, height)), { code: 'INVALID_CONFIGURATION' });
  }
  assert.throws(() => service.resolveModelInputSize(new f.Size(1920, 1080)), error => {
    assert.match(error.message, /x2.0-pro/);
    assert.match(error.message, /1024×1920, 1920×1024/);
    return true;
  });
});

test('models without fixed buckets resolve aligned input sizes within pixel bounds, including rounding and extreme aspect ratios', () => {
  const f = fixture();
  const sizes = [[799, 751], [1130, 1130], [1445, 1445], [1024, 1920], [1920, 1024], [832, 1472], [1472, 832],
    [3840, 2160], [1, 100000], [100000, 1], [1, 1], [32, 32], [640, 480]];
  for (const name of Object.values(f.Model)) {
    const service = new f.MediaService(f.Models.realtime(name)), model = service.model;
    if (model.resolutionBuckets.length > 0) continue;
    for (const [width, height] of sizes) {
      const result = service.resolveModelInputSize(new f.Size(width, height));
      const pixels = result.width * result.height;
      assert.ok(pixels >= model.minimumInputPixels && pixels <= model.maximumInputPixels,
        `${name}: ${width}x${height} resolved to ${JSON.stringify(result)}`);
      assert.equal(result.width % 32, 0);
      assert.equal(result.height % 32, 0);
      assert.deepEqual(service.resolveModelInputSize(result), result);
    }
  }
  const x2 = new f.MediaService();
  assert.equal(x2.model.name, f.Model.X2_0);
  assert.deepEqual(x2.resolveModelInputSize(new f.Size(799, 751)), new f.Size(800, 768));
  assert.deepEqual(x2.resolveModelInputSize(new f.Size(1130, 1130)), new f.Size(1120, 1120));
  const pro = new f.MediaService(f.Models.realtime(f.Model.X2_0_PRO));
  assert.deepEqual(pro.resolveModelInputSize(new f.Size(1024, 1920)), new f.Size(1024, 1920));
  assert.deepEqual(x2.resolveModelInputSize(new f.Size(1024, 1920)), new f.Size(800, 1536));
  assert.throws(() => x2.resolveModelInputSize(new f.Size(1e308, 1e308)), { code: 'INVALID_CONFIGURATION' });
});

test('the public media-service factory accepts a model and defaults to x2.0', () => {
  const f = fixture({
    ApiService: { ApiService: class {} }, XmaxRealtimeManager: {}, XmaxStorageManager: {}
  });
  const { XmaxClient } = f.load('core/XmaxClient.ets');
  const client = new XmaxClient({ apiKey: 'test-only', loggerOptions: 0 });
  assert.equal(client.createMediaService().model.name, f.Model.X2_0);
  const service = client.createMediaService(f.Model.X2_0_PRO);
  assert.deepEqual(service.resolveModelInputSize(new f.Size(1024, 1920)), new f.Size(1024, 1920));
});

function mediaFixture() {
  const calls = [], intervals = new Map();
  const cameraKit = createCameraKitFixture(calls);
  const f = fixture({
    '@kit.CameraKit': cameraKit.kit,
    CameraFrameOutput: cameraKit.frameOutput,
    '@kit.CoreFileKit': { fileIo: {
      OpenMode: { READ_ONLY: 0 }, openSync: () => ({ fd: 1 }),
      statSync: () => ({ size: 100 }), closeSync() {}
    } },
    '@kit.MediaKit': { media: { async createAVMetadataExtractor() {
      return { async fetchMetadata() { return { videoWidth: '1920', videoHeight: '1024',
        videoOrientation: '90', duration: '1000', hasAudio: 'false' }; }, async release() {} };
    } } },
    PermissionManager: { PermissionManager: class { async ensureCameraPermission() {} } },
    ImageManager: { ImageManager: class { async decodeFile() {
      return { width: 1024, height: 1920, async release() {}, async makeVideoFrameData(width, height) {
        calls.push(['image', width, height]);
        return { width, height, pixelFormat: 'RGBA', bytesPerRow: width * 4,
          data: new ArrayBuffer(width * height * 4) };
      } };
    } } },
    VideoSourceController: { VideoSourceController: class {
      configure(...args) { calls.push(['video', ...args]); } start() {} async stop() {}
    } },
    AudioSourceController: { AudioSourceController: class { stop() {} } },
    AudioManager: { AudioManager: class { setPlaybackEnabled() {} async stop() {} } },
    MediaTimeline: { MediaTimeline: class { static currentTimestampUs() { return 0; } } }
  }, {
    setInterval: (callback, milliseconds) => { intervals.set(1, { callback, milliseconds }); return 1; },
    clearInterval: id => intervals.delete(id)
  });
  const { MediaController } = f.load('media/MediaController.ets');
  const rtc = {
    async initialize() {}, async destroy() {}, useExternalVideoSource() {},
    configureLocalVideoMirror() {}, renderLibraryName: () => 'rtc', unbindLocalVideo() {}
  };
  return { ...f, calls, intervals, createMedia(model) {
    return new MediaController({}, rtc, { setVideoEncoderConfig() {}, pushLocalVideoFrame() {} },
      error => { throw error; }, new f.MediaService(f.Models.realtime(model)));
  } };
}

for (const name of ['x2.0', 'x2.0-pro']) {
  test(`shared ${name} rules reach camera capture, image frames and rotated video playback`, async () => {
    const f = mediaFixture(), media = f.createMedia(name);
    const model = f.Models.realtime(name), service = new f.MediaService(model);
    const expected = service.resolveModelInputSize(new f.Size(1024, 1920));
    const camera = await media.createLocalCameraStream(new f.Format(1024, 1920, 25), 'front');
    assert.deepEqual(camera.videoTrack.videoFormat, new f.Format(expected.width, expected.height, 25));
    assert.deepEqual(f.calls.find(call => call[0] === 'camera'), ['camera', expected.width, expected.height, 30]);
    await media.stopLocalStream();
    for (const source of ['Image', 'Video']) {
      for (const fps of [undefined, 20]) {
        const stream = await media[`createLocal${source}Stream`]('source',
          fps === undefined ? undefined : new f.Format(1024, 1920, fps));
        assert.deepEqual(stream.videoTrack.videoFormat,
          new f.Format(expected.width, expected.height, fps ?? model.defaultFrameRate));
        if (source === 'Image') {
          assert.equal(f.intervals.get(1).milliseconds, 1000 / (fps ?? model.defaultFrameRate));
          assert.deepEqual(f.calls.at(-1), ['image', expected.width, expected.height]);
        } else {
          assert.deepEqual(f.calls.at(-1), ['video', 'source', 90, expected.width, expected.height,
            fps ?? model.defaultFrameRate]);
        }
        await media.stopLocalStream();
        assert.equal(f.intervals.size, 0);
      }
    }
    assert.equal(media.currentTrack, null);
  });
}

test('Pro rejects unsupported camera input before permission or capture, and rejects image/video output sizes', async () => {
  const calls = [];
  const kit = createCameraKitFixture(calls);
  const f = fixture({
    '@kit.CameraKit': kit.kit, CameraFrameOutput: kit.frameOutput,
    PermissionManager: { PermissionManager: class { async ensureCameraPermission() { calls.push('permission'); } } }
  });
  const { CameraController } = f.load('media/camera/CameraController.ets');
  const camera = new CameraController({}, {}, {}, new f.MediaService(f.Models.realtime(f.Model.X2_0_PRO)));
  await assert.rejects(camera.createLocalCameraStream(new f.Format(1920, 1080, 30), 'front'),
    { code: 'INVALID_CONFIGURATION' });
  assert.deepEqual(calls, []);
  assert.equal(camera.currentTrack, null);
  for (const source of ['Image', 'Video']) {
    const mf = mediaFixture(), media = mf.createMedia('x2.0-pro');
    await assert.rejects(media[`createLocal${source}Stream`]('source', new mf.Format(1920, 1080, 30)),
      { code: 'INVALID_CONFIGURATION' });
    assert.equal(media.currentTrack, null);
    assert.equal(mf.intervals.size, 0);
    assert.equal(mf.calls.some(call => call[0] === 'image' || call[0] === 'video'), false);
  }
});

test('XLab lists iOS models and migrates a persisted SLA selection to Pro', () => {
  const f = fixture();
  let selected;
  const load = loadEts({ '@xmax/sdk': { RealtimeModel: f.Model } }, {
    AppStorage: { get: () => selected, set: (_key, value) => { selected = value; } },
    PersistentStorage: { persistProp: (_key, value) => { selected ??= value; } }
  });
  const { XLabModelSelection: selection } = load(path.resolve(__dirname,
    '../examples/XLab/entry/src/main/ets/modules/xlrealtime/config/XLabModelSelection.ets'));
  assert.deepEqual(selection.OPTIONS.map(option => option.model), ['x2.0', 'x2.0-pro']);
  for (const [saved, expected] of [['x2.0', 'x2.0'], ['x2.0-pro', 'x2.0-pro'],
    ['x2.0-sla', 'x2.0-pro'], ['unknown', 'x2.0'], [undefined, 'x2.0']]) {
    selected = saved;
    assert.equal(selection.current(), expected);
  }
  selected = 'x2.0-sla';
  selection.initialize();
  assert.equal(selected, 'x2.0-pro');
});

for (const name of ['x2.0', 'x2.0-pro']) {
  test(`${name} camera/image/video resolved formats preserve upload encoding settings`, async () => {
    const f = mediaFixture(), media = f.createMedia(name);
    const expected = new f.MediaService(f.Models.realtime(name)).resolveModelInputSize(new f.Size(1024, 1920));
    const requested = new f.Format(1024, 1920, 30, 1500, 6000, 'MaintainQuality');
    for (const source of ['Camera', 'Image', 'Video']) {
      const stream = source === 'Camera' ? await media.createLocalCameraStream(requested, 'front') :
        await media[`createLocal${source}Stream`]('source', requested);
      assert.deepEqual(stream.videoTrack.videoFormat,
        new f.Format(expected.width, expected.height, 30, 1500, 6000, 'MaintainQuality'));
      await media.stopLocalStream();
    }
  });
}
