const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { loadEts } = require('./ets-loader.cjs');

function fixture() {
  const calls = [], errors = [];
  let nextId = 0, completion = null, nativeFailure, copyFailure = false;
  const sdk = loadEts();
  const { RealtimeAudioFrame: Audio } = sdk('service/realtime/RealtimeMediaFrame.ets');
  const helper = {
    async showAssetsCreationDialog(...args) { calls.push(['dialog', ...args]); return this.destinations; },
    destinations: ['photo://video'], async release() { calls.push(['releaseHelper']); }
  };
  const load = loadEts({
    '@kit.AbilityKit': {}, '@kit.ArkTS': { util: { generateRandomUUID: () => 'test-only' } },
    '@kit.CoreFileKit': {
      fileUri: { getUriFromPath: value => `file://${value}` },
      fileIo: { OpenMode: { READ_ONLY: 1, WRITE_ONLY: 2 },
        async unlink(value) { calls.push(['unlink', value]); },
        async open(uri, mode) { calls.push(['open', uri, mode]); return { fd: mode }; },
        async close(file) { calls.push(['close', file.fd]); },
        async copyFile(...args) { calls.push(['copy', ...args]); if (copyFailure) throw new Error('copy failed'); }
      }
    },
    '@kit.MediaLibraryKit': { photoAccessHelper: { PhotoType: { VIDEO: 2 }, getPhotoAccessHelper: () => helper } },
    '@xmax/sdk': { RealtimeAudioFrame: Audio },
    'libxlab_recorder.so': {
      create(file, onError) { nativeFailure = onError; calls.push(['create', file]); return ++nextId; },
      appendAudio(...args) { calls.push(['audio', ...args]); },
      appendVideo(...args) { calls.push(['video', ...args]); },
      finish(id, cancel) { calls.push(['finish', id, cancel]); return completion ?? Promise.resolve('video.mp4'); }
    }
  });
  const { RealtimeVideoRecorder: Recorder } = load(path.resolve(__dirname,
    '../examples/XLab/entry/src/main/ets/modules/xlrealtime/recording/RealtimeVideoRecorder.ets'));
  const recorder = new Recorder({ cacheDir: '/cache' });
  return { calls, errors, Audio, recorder, helper,
    start() { recorder.start(message => errors.push(message)); },
    fail(message) { nativeFailure(message); },
    holdFinish() { let resolve; completion = new Promise(yes => { resolve = yes; }); return resolve; },
    failCopy() { copyFailure = true; }
  };
}

test('XLab forwards owned audio/video only during recording and rejects a different result binding', async () => {
  const f = fixture(), audio = new f.Audio(new Uint8Array(960), 48000, 1, 480, 1000000);
  const video = { width: 2, height: 2, rotation: 0, timestampUs: 990000, planes: [] };
  f.recorder.append({ streamId: 'first', content: audio });
  assert.deepEqual(f.calls, []);
  f.start();
  f.recorder.append({ streamId: 'first', content: audio });
  f.recorder.append({ streamId: 'first', content: video });
  assert.equal(f.calls[1][0], 'audio'); assert.equal(f.calls[1][2], audio);
  assert.equal(f.calls[2][0], 'video'); assert.equal(f.calls[2][2], video);
  assert.throws(() => f.recorder.append({ streamId: 'other', content: video }), /result changed/);
  assert.throws(() => f.start(), /already started/);
  const first = f.recorder.stop(), second = f.recorder.stop();
  assert.equal(first, second); await first;
  f.recorder.append({ streamId: 'first', content: video }); f.fail('obsolete');
  assert.deepEqual(f.errors, []);
  assert.equal(f.calls.filter(call => call[0] === 'finish').length, 1);
});

test('XLab cancellation shares in-flight finalization and removes only its own output', async () => {
  const f = fixture(); f.start();
  const finish = f.holdFinish();
  const stopping = f.recorder.stop(), cancelling = f.recorder.cancel();
  assert.equal(f.calls.filter(call => call[0] === 'finish').length, 1);
  finish('video.mp4'); await stopping; await cancelling;
  assert.deepEqual(f.calls.at(-1), ['unlink', '/cache/xlab-recording-test-only.mp4']);
  const g = fixture(); g.start(); await g.recorder.cancel();
  assert.deepEqual(g.calls.find(call => call[0] === 'finish'), ['finish', 1, true]);
});

test('XLab saves through user consent without opening library files when consent is declined', async () => {
  const f = fixture();
  f.helper.destinations = [];
  assert.equal(await f.recorder.saveToAlbum({}), false);
  assert.equal(f.calls.some(call => call[0] === 'open'), false);
  assert.equal(f.calls.at(-1)[0], 'releaseHelper');
  f.helper.destinations = ['photo://video'];
  assert.equal(await f.recorder.saveToAlbum({}), true);
  assert.deepEqual(f.calls.find(call => call[0] === 'copy'), ['copy', 1, 2]);
  assert.deepEqual(f.calls.slice(-3), [['close', 2], ['close', 1], ['releaseHelper']]);
});

test('XLab closes both file descriptors and the photo helper after save failure', async () => {
  const f = fixture(); f.failCopy();
  await assert.rejects(f.recorder.saveToAlbum({}), /copy failed/);
  assert.deepEqual(f.calls.slice(-3), [['close', 2], ['close', 1], ['releaseHelper']]);
});

test('public video-only callback and its unbounded dispatcher have been removed', () => {
  const root = path.resolve(__dirname, '../xmax_sdk');
  for (const file of ['Index.ets', 'src/main/ets/core/realtime/XmaxRealtimeManaging.ets',
    'src/main/ets/core/realtime/XmaxRealtimeManager.ets', 'src/main/ets/rendering/RenderControlling.ets']) {
    assert.doesNotMatch(fs.readFileSync(path.join(root, file), 'utf8'), /setRemoteVideoFrameListener|RealtimeVideoFrameListener/);
  }
  assert.equal(fs.existsSync(path.join(root, 'src/main/ets/rendering/video/RealtimeVideoFrameDispatcher.ets')), false);
});
