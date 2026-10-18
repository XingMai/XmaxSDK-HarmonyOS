const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

function fixture() {
  const load = loadEts({
    '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
    XmaxLogger: { XmaxLogger: { error() {} } },
    DefaultTrajectoryEffectRenderer: { DefaultTrajectoryEffectRenderer: class {} }
  }, { setInterval: () => 1, clearInterval() {} });
  const { ImageSize: Size } = load('service/media/ImageSize.ets');
  const { RealtimeVideoFormat: Format } = load('service/realtime/RealtimeVideoFormat.ets');
  const { RealtimeVideoTrack: Track, updateRealtimeVideoTrackFormat } = load('service/realtime/RealtimeVideoTrack.ets');
  const { VideoContentMode: Mode } = load('foundation/media/video/VideoContentMode.ets');
  const { InteractionCoordinateMapper: Mapper } = load('media/interaction/InteractionCoordinateMapper.ets');
  return { load, Size, Format, Track, Mode, Mapper, updateRealtimeVideoTrackFormat };
}

const close = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-12, `${actual} != ${expected}`);

test('normalized interaction preserves fractional precision and clips to unit bounds', () => {
  const { Mapper, Size, Mode } = fixture();
  const point = Mapper.map({ x: 0.431231 * 300, y: 0.56931 * 400 }, 300, 400, new Size(1248, 1664), Mode.FIT);
  close(point.x, 0.431231);
  close(point.y, 0.56931);
  for (const [x, y, expected] of [[-10, -10, { x: 0, y: 0 }], [250, 150, { x: 1, y: 1 }],
    [200, 100, { x: 1, y: 1 }]]) {
    assert.deepEqual({ ...Mapper.map({ x, y }, 200, 100, new Size(200, 100), Mode.FILL) }, expected);
  }
  const cropped = Mapper.map({ x: 0, y: 0 }, 320, 480, new Size(720, 1280), Mode.FILL);
  close(cropped.x, 0);
  close(cropped.y, 0.078125);
});

test('equivalent processed media aspect ratios use the same fixed coordinate basis', () => {
  const { Mapper, Size, Mode } = fixture();
  for (const [width, height] of [[1920, 1080], [1536, 864], [960, 540]]) {
    assert.deepEqual({ ...Mapper.map({ x: 120, y: 202.5 }, 480, 270, new Size(width, height), Mode.FIT) },
      { x: 0.25, y: 0.75 });
  }
});

function overlayFixture(mode) {
  const f = fixture();
  const { InteractionController } = f.load('media/interaction/InteractionController.ets');
  const { TrajectoryBinding } = f.load('rendering/trajectory/TrajectoryBinding.ets');
  const { TrajectoryRegistry } = f.load('rendering/trajectory/TrajectoryRegistry.ets');
  const { TrajectoryOverlayView } = f.load('rendering/trajectory/TrajectoryOverlayView.ets');
  const sent = [], began = [], moved = [];
  const interaction = new InteractionController((task, points) => sent.push({ task, points }));
  interaction.start('task', new f.Format(200, 100, 30));
  const track = new f.Track('remote', new f.Format(800, 600, 30));
  const binding = new TrajectoryBinding(interaction, new f.Size(200, 100));
  TrajectoryRegistry.register(track, binding);
  const overlay = new TrajectoryOverlayView();
  overlay.track = track;
  overlay.contentMode = mode ?? f.Mode.FIT;
  overlay.renderer = {
    renderBegan: points => began.push(...points), renderMoved: points => moved.push(...points),
    renderEnded() {}, reset() {}, resize() {}, isAnimating: () => false
  };
  overlay.aboutToAppear();
  overlay.updateArea({ width: 400, height: 400 });
  return { ...f, overlay, track, binding, sent, began, moved, close() {
    overlay.aboutToDisappear();
    TrajectoryRegistry.unregister(track);
  } };
}

test('effect coordinates and emitted tracks share processed media geometry despite remote format changes', () => {
  const f = overlayFixture();
  try {
    f.overlay.beginTouch({ id: 1, x: 100, y: 150 });
    assert.equal(f.began.length, 1);
    assert.equal(f.began[0].x, 100);
    assert.equal(f.began[0].y, 150);
    assert.equal(f.began[0].normalizedX, 0.25);
    assert.equal(f.began[0].normalizedY, 0.25);
    assert.deepEqual(f.sent[0].points.map(point => ({ ...point })), [{ x: 0.25, y: 0.25 }]);
    f.updateRealtimeVideoTrackFormat(f.track, new f.Format(684, 1216, 30));
    f.overlay.moveTouch({ id: 1, x: 300, y: 250 });
    f.overlay.submitInteraction();
    assert.equal(f.moved[0].normalizedX, 0.75);
    assert.equal(f.moved[0].normalizedY, 0.75);
    assert.deepEqual(f.sent.at(-1).points.map(point => ({ ...point })), [{ x: 0.75, y: 0.75 }]);
  } finally { f.close(); }
});

test('fit overlay ignores letterbox starts and clamps movement to the visible media region', () => {
  const f = overlayFixture();
  try {
    f.overlay.beginTouch({ id: 1, x: 100, y: 50 });
    assert.equal(f.began.length, 0);
    assert.equal(f.sent.length, 0);
    f.overlay.beginTouch({ id: 2, x: 100, y: 150 });
    f.overlay.moveTouch({ id: 2, x: 100, y: 50 });
    f.overlay.submitInteraction();
    assert.equal(f.moved[0].y, 100);
    assert.equal(f.moved[0].normalizedY, 0);
    assert.deepEqual(f.sent.at(-1).points.map(point => ({ ...point })), [{ x: 0.25, y: 0 }]);
  } finally { f.close(); }
});

test('fill overlay includes the cropped media offset in both visual and signaling coordinates', () => {
  const f = overlayFixture(fixture().Mode.FILL);
  try {
    f.overlay.beginTouch({ id: 1, x: 0, y: 100 });
    assert.equal(f.began[0].normalizedX, 0.25);
    assert.equal(f.began[0].normalizedY, 0.25);
    assert.deepEqual(f.sent[0].points.map(point => ({ ...point })), [{ x: 0.25, y: 0.25 }]);
  } finally { f.close(); }
});

test('same-track ArkUI property copies cannot interrupt a held drag or its sampling timer', () => {
  const f = overlayFixture();
  try {
    f.overlay.beginTouch({ id: 1, x: 100, y: 150 });
    const sampleTimer = f.overlay.sampleTimer;
    const touch = f.overlay.activeTouches.get(1);
    for (let i = 0; i < 5; i++) {
      f.updateRealtimeVideoTrackFormat(f.track, new f.Format(640 + i * 4, 480, 24));
      f.overlay.track = Object.assign(Object.create(Object.getPrototypeOf(f.track)), f.track);
      f.overlay.onTrackChanged(); // Periodic statistics/layout updates can pass a fresh @Prop copy.
      assert.equal(f.overlay.activeTouches.get(1), touch);
      assert.equal(f.overlay.sampleTimer, sampleTimer);
      f.overlay.moveTouch({ id: 1, x: 110 + i * 10, y: 150 });
      f.overlay.submitInteraction();
    }
    assert.equal(f.began.length, 1);
    assert.equal(f.moved.length, 5);
    assert.equal(f.sent.length, 6);
  } finally { f.close(); }
});

test('a different track with the same ID still cancels the previous drag', () => {
  const f = overlayFixture();
  try {
    f.overlay.beginTouch({ id: 1, x: 100, y: 150 });
    f.overlay.track = new f.Track(f.track.id, f.track.videoFormat);
    f.overlay.onTrackChanged();
    assert.equal(f.overlay.activeTouches.size, 0);
    assert.equal(f.overlay.sampleTimer, -1);
    assert.equal(f.overlay.tickTimer, -1);
  } finally { f.close(); }
});
