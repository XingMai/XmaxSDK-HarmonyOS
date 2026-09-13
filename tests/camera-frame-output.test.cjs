const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

function fixture() {
  let callback;
  const frames = [], errors = [], logs = [];
  const load = loadEts({
    '@kit.CameraKit': { camera: {} },
    '@kit.ArkUI': { display: {} },
    XmaxLogger: { XmaxLogger: { error: message => logs.push(message) } },
    'libxmax_video.so': { default: { createFrameReceiver(_w, _h, listener) {
      callback = listener;
      return { getSurfaceId: () => 'surface', release() {} };
    } } }
  });
  const { CameraFrameOutput } = load('media/camera/CameraFrameOutput.ets');
  const output = CameraFrameOutput.create({ createPreviewOutput: () => ({ async release() {} }) },
    { size: { width: 1920, height: 1080 } }, 'front', frame => frames.push(frame), error => errors.push(error));
  return { output, frames, errors, logs, deliver: (...args) => callback(...args) };
}

test('camera callback delivers NV12 planes and timestamps without performance fields', async () => {
  const f = fixture(), data = new ArrayBuffer(12);
  try {
    f.deliver(data, 2, 4, 123456);
    const frame = f.frames[0];
    assert.equal(frame.timestampUs, 123456);
    assert.equal(frame.format.width, 2);
    assert.equal(frame.format.height, 4);
    assert.equal(frame.format.pixelFormat, 'nv12');
    assert.equal(frame.planes.length, 2);
    assert.equal(frame.planes[0].data, data);
    assert.equal(frame.planes[1].data, data);
    assert.equal(frame.planes[0].byteLength, 8);
    assert.equal(frame.planes[1].byteOffset, 8);
    assert.equal(frame.planes[1].byteLength, 4);
    assert.deepEqual(f.errors, []);
    assert.deepEqual(f.logs, []);
  } finally { await f.output.release(); }
});

test('camera callback still forwards native errors and ignores empty frames', async () => {
  const f = fixture();
  try {
    f.deliver(undefined, 0, 0, 0, 'native capture failed');
    assert.equal(f.errors.length, 1);
    assert.equal(f.errors[0].code, 'MEDIA_ERROR');
    assert.equal(f.errors[0].message, 'native capture failed');
    f.deliver(undefined, 2, 4, 123);
    assert.equal(f.frames.length, 0);
    assert.match(f.logs[0], /native capture failed/);
  } finally { await f.output.release(); }
});
