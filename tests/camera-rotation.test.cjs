const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

function fixture(position = 'back') {
  let displayRotation = 0;
  let listener;
  let configureFailure = false;
  let offFailure = false;
  const configurations = [], calls = [], errors = [];
  const load = loadEts({
    '@kit.CameraKit': { camera: { CameraPosition: { CAMERA_POSITION_FRONT: 'front', CAMERA_POSITION_BACK: 'back' }, ImageRotation: {
      ROTATION_90: 90, ROTATION_180: 180, ROTATION_270: 270
    } } },
    '@kit.ArkUI': { display: {
      Orientation: { PORTRAIT: 0, LANDSCAPE: 1, PORTRAIT_INVERTED: 2, LANDSCAPE_INVERTED: 3 },
      getDefaultDisplaySync: () => ({ id: 1, rotation: displayRotation,
        orientation: displayRotation % 2 ? 1 : 0,
        width: displayRotation % 2 ? 1920 : 1080, height: displayRotation % 2 ? 1080 : 1920 }),
      on(event, callback) { assert.equal(event, 'change'); calls.push('on'); listener = callback; },
      off(event, callback) {
        assert.equal(event, 'change'); assert.equal(callback, listener); calls.push('off');
        if (offFailure) throw new Error('off failed');
      }
    } },
    XmaxLogger: { XmaxLogger: { error: message => errors.push(message) } },
    'libxmax_video.so': { default: {
      createFrameReceiver: () => ({
        getSurfaceId: () => 'surface',
        configure(...args) {
          if (configureFailure) throw new Error('configure failed');
          configurations.push(args);
        },
        release() { calls.push('release receiver'); }
      })
    } }
  });
  const { CameraFrameOutput } = load('media/camera/CameraFrameOutput.ets');
  const output = CameraFrameOutput.create({
    createPreviewOutput: () => ({
      getPreviewRotation: angle => (position === 'front' ? [270, 180, 90, 0] : [90, 180, 270, 0])[angle / 90],
      async release() { calls.push('release output'); }
    })
  }, { size: { width: 1920, height: 1440 } }, position, () => {});
  const { RealtimeVideoFormat: Format } = load('service/realtime/RealtimeVideoFormat.ets');
  const format = new Format(1024, 1920, 30, 1500, 4000, 'MaintainQuality');
  return { output, format, Format, configurations, calls, errors,
    rotate(value, id = 1) { displayRotation = value; listener?.(id); },
    failConfigure(value) { configureFailure = value; },
    failOff() { offFailure = true; }
  };
}

test('display rotation updates native pixels in both camera orientations and swaps output dimensions while preserving fps', async () => {
  for (const position of ['back', 'front']) {
    const f = fixture(position);
    const expectedAngles = position === 'front' ? [270, 0, 90, 180] : [90, 180, 270, 0];
    try {
      f.output.configure(f.format, 30);
      for (const rotation of [1, 2, 3, 0]) {
        f.rotate(rotation);
        const actual = f.output.currentVideoFormat;
        assert.equal(actual.minimumBitrate, 1500);
        assert.equal(actual.maximumBitrate, 4000);
        assert.equal(actual.encoderPreference, 'MaintainQuality');
      }
      assert.deepEqual(f.configurations, [0, 1, 2, 3, 0].map(rotation =>
        [rotation % 2 ? 1920 : 1024, rotation % 2 ? 1024 : 1920, expectedAngles[rotation], 30, 30]));
      f.rotate(0); // A display change without a new angle must not reset the pipeline.
      f.rotate(1, 2); // Another display must not reconfigure this camera.
      assert.equal(f.configurations.length, 5);
      const updated = new f.Format(832, 1472, 24);
      f.output.configure(updated, 30);
      f.rotate(2);
      assert.deepEqual(f.configurations.at(-1), [832, 1472, expectedAngles[2], 24, 30]);
      assert.equal(f.calls.filter(call => call === 'on').length, 1);
    } finally {
      await f.output.release();
    }
  }
});

test('release removes only its own listener and ignores queued rotation callbacks', async () => {
  const f = fixture();
  f.output.configure(f.format, 30);
  await f.output.release();
  f.rotate(1);
  f.output.configure(f.format, 30);
  await f.output.release();
  assert.equal(f.configurations.length, 1);
  assert.deepEqual(f.calls, ['on', 'off', 'release output', 'release receiver']);
});

test('a failed rotation update is logged and the same angle can be retried', async () => {
  const f = fixture();
  try {
    f.output.configure(f.format, 30);
    f.failConfigure(true);
    assert.doesNotThrow(() => f.rotate(1));
    assert.equal(f.configurations.length, 1);
    assert.match(f.errors[0], /更新相机帧旋转角度失败/);
    f.failConfigure(false);
    f.rotate(1);
    assert.deepEqual(f.configurations.at(-1), [1920, 1024, 180, 30, 30]);
  } finally {
    await f.output.release();
  }
});

test('startup failure and listener removal failure still allow camera resources to be released', async () => {
  const f = fixture();
  f.failConfigure(true);
  assert.throws(() => f.output.configure(f.format, 30), /configure failed/);
  f.failOff();
  await f.output.release();
  assert.doesNotThrow(() => f.rotate(1));
  assert.deepEqual(f.calls, ['on', 'off', 'release output', 'release receiver']);
  assert.match(f.errors[0], /移除相机屏幕变化监听失败/);
});

// Starting directly in landscape must use the same correction as rotating after startup.
test('front camera landscape correction applies on startup in either landscape direction', async () => {
  for (const [displayRotation, expected] of [[1, 0], [3, 180]]) {
    const f = fixture('front');
    try {
      f.rotate(displayRotation);
      f.output.configure(f.format, 30);
      assert.deepEqual(f.configurations[0], [1920, 1024, expected, 30, 30]);
    } finally {
      await f.output.release();
    }
  }
});

// Disabling display observation must skip listener registration and keep the startup format on rotation.
test('configure with display observation disabled ignores rotation and never registers a listener', async () => {
  const f = fixture();
  try {
    f.output.configure(f.format, 30, false);
    f.rotate(1); // No listener registered; rotation must not reconfigure the pipeline.
    f.rotate(2);
    assert.equal(f.calls.filter(call => call === 'on').length, 0);
    assert.deepEqual(f.configurations, [[1024, 1920, 90, 30, 30]]);
    // A one-time reconfigure still adapts to the display current at that moment.
    f.output.configure(f.format, 30, false);
    assert.deepEqual(f.configurations.at(-1), [1024, 1920, 270, 30, 30]);
    assert.equal(f.calls.filter(call => call === 'on').length, 0);
  } finally {
    await f.output.release();
  }
  assert.equal(f.calls.filter(call => call === 'off').length, 0);
});
