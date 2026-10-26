const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

function fixture(name = 'x2.0-sla') {
  const load = loadEts({
    '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
    XmaxLogger: { XmaxLogger: { error() {} } }
  });
  const { MediaService } = load('service/media/MediaService.ets');
  const { RealtimeModels } = load('service/realtime/RealtimeModel.ets');
  const { ImageSize: Size } = load('service/media/ImageSize.ets');
  const { RealtimeVideoFormat: Format } = load('service/realtime/RealtimeVideoFormat.ets');
  return { load, Size, Format, service: new MediaService(RealtimeModels.realtime(name)) };
}

test('images and videos preserve ratio within the model pixel budget, independently of generation buckets', () => {
  const { service, Size } = fixture();
  const cases = [[3840, 2160, 1920, 1080], [2160, 3840, 1080, 1920],
    [8000, 6000, 1664, 1248], [6000, 8000, 1248, 1664]];
  for (const source of ['image', 'video']) {
    for (const [w, h, width, height] of cases) {
      const result = service.resolveMediaSize(new Size(w, h), source);
      assert.deepEqual(result, new Size(width, height));
      assert.equal(result.width * h, result.height * w);
      assert.ok(result.width * result.height <= 2100000);
      assert.equal(result.width % 4, 0);
      assert.equal(result.height % 4, 0);
      assert.deepEqual(service.resolveMediaSize(result, source), result);
    }
  }
  for (const [width, height, canvasWidth, canvasHeight] of [
    [1920, 1080, 1920, 1080], [1080, 1920, 1080, 1920],
    [1024, 1920, 1080, 1920], [1920, 1024, 1920, 1080],
    [640, 480, 1536, 1152], [1200, 1600, 1152, 1536],
    [1200, 1500, 1152, 1536], [800, 800, 1408, 1408]
  ]) {
    assert.deepEqual(service.resolveGenerationSize(new Size(width, height)), new Size(canvasWidth, canvasHeight));
  }
});

test('media does not inherit generation minimum area or 32 alignment and only camera validates fixed buckets', () => {
  const { service, Size } = fixture();
  for (const source of ['image', 'video']) {
    for (const [w, h, width, height] of [[320, 180, 320, 180], [804, 600, 804, 600],
      [1001, 1000, 1000, 1000], [802, 600, 800, 600]]) {
      assert.deepEqual(service.resolveMediaSize(new Size(w, h), source), new Size(width, height));
    }
  }
  for (const size of [new Size(1920, 1080), new Size(1080, 1920), new Size(1408, 1408),
    new Size(1152, 1536), new Size(1536, 1152)]) {
    assert.deepEqual(service.resolveMediaSize(size, 'camera'), size);
  }
  for (const size of [new Size(1024, 1920), new Size(1920, 1024), new Size(2048, 3840)]) {
    assert.throws(() => service.resolveMediaSize(size, 'camera'), { code: 'INVALID_CONFIGURATION' });
  }
  const x2Fixture = fixture('x2.0'), x2 = x2Fixture.service;
  assert.deepEqual({ ...x2.resolveMediaSize(new Size(320, 180), 'image') }, { width: 320, height: 180 });
  const generation = x2.resolveGenerationSize(new Size(320, 180));
  assert.ok(generation.width * generation.height >= 600000);
  assert.equal(generation.width % 32, 0);
  assert.equal(generation.height % 32, 0);
  const large = x2.resolveMediaSize(new Size(3840, 2160), 'video');
  assert.ok(large.width * large.height <= 1280000);
  assert.equal(large.width * 9, large.height * 16);
});

test('return sizing combines a downlink bound and optional interpolation limit, preserving the media ratio', () => {
  const { service, Size } = fixture();
  const source = new Size(1080, 1920), bound = new Size(864, 1536);
  assert.deepEqual(service.resolveTargetSize(source, bound), bound);
  assert.deepEqual(service.resolveTargetSize(source, bound, true), new Size(684, 1216));
  for (const [w, h, width, height] of [[720, 1280, 684, 1216], [832, 1472, 676, 1196],
    [1024, 1920, 672, 1260], [1120, 1120, 948, 948], [640, 480, 640, 480]]) {
    const size = new Size(w, h);
    const result = service.resolveTargetSize(size, new Size(10000, 10000), true);
    assert.deepEqual(result, new Size(width, height));
    assert.ok(result.width * result.height <= 900000);
    assert.equal(result.width * h, result.height * w);
  }
  assert.deepEqual(service.resolveTargetSize(new Size(802, 600), new Size(802, 600)), new Size(800, 600));
});

test('sizing rejects malformed dimensions and impossible four-pixel frames', () => {
  const { service, Size } = fixture();
  for (const [w, h] of [[0, 100], [-4, 100], [NaN, 100], [Infinity, 100], [100.5, 100], [1e308, 100]]) {
    const size = { width: w, height: h };
    assert.throws(() => service.resolveMediaSize(size, 'image'), { code: 'INVALID_CONFIGURATION' });
    assert.throws(() => service.resolveGenerationSize(size), { code: 'INVALID_CONFIGURATION' });
    assert.throws(() => service.resolveTargetSize(size, new Size(100, 100)), { code: 'INVALID_CONFIGURATION' });
  }
  for (const size of [new Size(1, 100), new Size(100, 3), new Size(1, 1)]) {
    assert.throws(() => service.resolveMediaSize(size, 'image'), { code: 'INVALID_CONFIGURATION' });
  }
  for (const bound of [{ width: 0, height: 100 }, { width: NaN, height: 100 },
    { width: Infinity, height: 100 }, new Size(3, 3)]) {
    assert.throws(() => service.resolveTargetSize(new Size(100, 100), bound), { code: 'INVALID_CONFIGURATION' });
  }
});

test('interaction uses resolved media geometry and normalized coordinates for fit and fill', () => {
  const { load, Size } = fixture();
  const { InteractionCoordinateMapper: Mapper } = load('media/interaction/InteractionCoordinateMapper.ets');
  const { VideoContentMode: Mode } = load('foundation/media/video/VideoContentMode.ets');
  const map = (x, y, mode, size = new Size(200, 100)) =>
    Mapper.map({ x, y }, 400, 400, size, mode);
  assert.deepEqual({ ...map(100, 150, Mode.FIT) }, { x: 0.25, y: 0.25 });
  assert.equal(map(100, 99, Mode.FIT), null);
  assert.deepEqual({ ...map(0, 100, Mode.FILL) }, { x: 0.25, y: 0.25 });
  assert.deepEqual({ ...map(200, 200, Mode.FILL) }, { x: 0.5, y: 0.5 });
  for (const point of [{ x: NaN, y: 20 }, { x: 20, y: Infinity }]) {
    assert.equal(Mapper.map(point, 400, 400, new Size(200, 100), Mode.FIT), null);
  }
  assert.equal(Mapper.map({ x: 10, y: 10 }, Infinity, 400, new Size(200, 100), Mode.FIT), null);
});

test('trajectory binding keeps the media baseline when return dimensions differ', () => {
  const { load, Format, Size } = fixture();
  const { InteractionController } = load('media/interaction/InteractionController.ets');
  const { TrajectoryBinding } = load('rendering/trajectory/TrajectoryBinding.ets');
  const { VideoContentMode: Mode } = load('foundation/media/video/VideoContentMode.ets');
  const sent = [];
  const controller = new InteractionController((task, points) => sent.push({ task, points }));
  controller.start('task', new Format(1080, 1920, 30));
  const binding = new TrajectoryBinding(controller, new Size(1080, 1920));
  binding.submit([{ x: 20, y: 200 }], 400, 400, Mode.FIT);
  assert.equal(sent.length, 0);
  binding.submit([{ x: 200, y: 200 }], 400, 400, Mode.FIT);
  assert.equal(sent[0].task, 'task');
  assert.deepEqual(sent[0].points.map(point => ({ ...point })), [{ x: 0.5, y: 0.5 }]);
  assert.deepEqual({ ...binding.resolvedMediaSize }, { width: 1080, height: 1920 });
  controller.stop();
});
