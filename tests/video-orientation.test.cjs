const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

function query(matches = false) {
  const listeners = new Set(), removed = [];
  return { matches, listeners, removed,
    on(_event, listener) { listeners.add(listener); },
    off(_event, listener) { listeners.delete(listener); removed.push(listener); },
    rotate(value) { this.matches = value; [...listeners].forEach(fn => fn({ matches: value })); }
  };
}
function fixture() {
  const load = loadEts({ '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
    DefaultTrajectoryEffectRenderer: { DefaultTrajectoryEffectRenderer: class {} },
    TrajectoryOverlayView: { TrajectoryOverlayView: class {} },
    XmaxLogger: { XmaxLogger: { error() {} } } });
  return { load, ...load('service/realtime/RealtimeVideoTrack.ets'),
    ...load('rendering/video/VideoOrientationObserver.ets') };
}

test('first attachment sets a baseline and repeated/same-axis events do not notify', () => {
  const f = fixture(), track = new f.RealtimeVideoTrack('local'), changes = [];
  f.setRealtimeVideoTrackOrientationHandler(track, () => changes.push('changed'));
  const observer = new f.VideoOrientationObserver(), window = query(true);
  observer.start(track, window);
  window.rotate(true); window.rotate(true);
  assert.deepEqual(changes, []);
  window.rotate(false); window.rotate(false);
  assert.deepEqual(changes, ['changed']);
  observer.stop();
  assert.equal(window.listeners.size, 0);
  window.removed[0]({ matches: true });
  assert.equal(changes.length, 1);
  observer.start(track, query(true)); // Remounting is a baseline, not a rotation event.
  assert.equal(changes.length, 1);
  observer.stop();
});

test('ArkUI copies and multiple views share track orientation, while stale listeners cannot affect replacement', () => {
  const f = fixture(), track = new f.RealtimeVideoTrack('local'), next = new f.RealtimeVideoTrack('local');
  const copy = Object.assign(Object.create(Object.getPrototypeOf(track)), track);
  const counts = [0, 0];
  f.setRealtimeVideoTrackOrientationHandler(track, () => counts[0]++);
  f.setRealtimeVideoTrackOrientationHandler(next, () => counts[1]++);
  const a = new f.VideoOrientationObserver(), b = new f.VideoOrientationObserver();
  const qa = query(), qb = query();
  a.start(track, qa); b.start(copy, qb);
  qa.rotate(true); qb.rotate(true);
  assert.deepEqual(counts, [1, 0]);
  a.start(next, query());
  qa.removed[0]({ matches: false });
  assert.deepEqual(counts, [1, 0]);
  f.setRealtimeVideoTrackOrientationHandler(track);
  qb.rotate(false);
  assert.deepEqual(counts, [1, 0]);
  a.stop(); b.stop();
});

test('the video component installs window observation on appearance and removes it on replacement/disappearance', () => {
  const f = fixture(), windows = [], changes = [];
  const { XmaxVideoView } = f.load('rendering/video/XmaxVideoView.ets');
  const a = new f.RealtimeVideoTrack('a'), b = new f.RealtimeVideoTrack('b');
  f.setRealtimeVideoTrackOrientationHandler(a, () => changes.push('a'));
  f.setRealtimeVideoTrackOrientationHandler(b, () => changes.push('b'));
  const view = new XmaxVideoView();
  view.getUIContext = () => ({ getMediaQuery: () => ({ matchMediaSync: expression => {
    assert.equal(expression, '(orientation: landscape)');
    const q = query(); windows.push(q); return q;
  } }) });
  view.track = a; view.aboutToAppear();
  windows[0].rotate(true);
  view.track = b; view.onTrackChanged();
  assert.equal(windows[0].listeners.size, 0);
  windows[0].removed[0]({ matches: false });
  windows[1].rotate(true);
  assert.deepEqual(changes, ['a', 'b']);
  view.aboutToDisappear();
  assert.equal(windows[1].listeners.size, 0);
  windows[1].removed[0]({ matches: false });
  assert.deepEqual(changes, ['a', 'b']);
});
