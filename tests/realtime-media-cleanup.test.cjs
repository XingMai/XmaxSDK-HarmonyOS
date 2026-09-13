const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

const settle = async () => { for (let i = 0; i < 30; i++) await Promise.resolve(); };
function gate() {
  let resolve;
  const promise = new Promise(yes => { resolve = yes; });
  return { promise, resolve };
}

for (const source of ['Camera', 'Image', 'Video']) {
  test(`close during ${source.toLowerCase()} creation releases the late media before destroying RTC`, async () => {
    const creation = gate(), release = gate(), events = [], instances = [];
    let nativeRunning = false;
    class Controller {
      constructor() { instances.push(this); this.currentTrack = null; }
      async create() {
        await creation.promise;
        nativeRunning = true;
        this.currentTrack = {};
        events.push('created');
        return { videoTrack: this.currentTrack };
      }
      async stop() {
        events.push('stopping');
        await release.promise;
        nativeRunning = false;
        this.currentTrack = null;
        events.push('stopped');
      }
      createLocalCameraStream() { return this.create(); }
      createLocalImageStream() { return this.create(); }
      createLocalVideoStream() { return this.create(); }
      stopLocalCameraStream() { return this.stop(); }
      stopLocalImageStream() { return this.stop(); }
      stopLocalVideoStream() { return this.stop(); }
      prepareForStop() { events.push('prepare'); }
    }
    const load = loadEts({
      '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
      CameraController: { CameraController: Controller },
      ImageController: { ImageController: Controller },
      VideoController: { VideoController: Controller },
      InteractionController: { InteractionController: class {} },
      XmaxLogger: { XmaxLogger: { error() {} } }
    });
    const { MediaController } = load('media/MediaController.ets');
    const { RealtimeCoordinator, RealtimeOperationKind: Kind, RealtimeTerminationScope: Scope } =
      load('core/realtime/RealtimeCoordinator.ets');
    const { XmaxRealtimeErrorManager } = load('core/realtime/XmaxRealtimeErrorManager.ets');
    const media = new MediaController({}, {
      async initialize() { events.push('initialize'); },
      async destroy() { assert.equal(nativeRunning, false); events.push('destroy'); }
    }, {}, () => {});
    const coordinator = new RealtimeCoordinator(new XmaxRealtimeErrorManager(), async () => {
      await media.stopLocalStream();
    });
    const running = coordinator.run(Kind.MEDIA, null, async token => {
      const stream = await media[`createLocal${source}Stream`]('test');
      token.ensureCurrent();
      token.setFailureScope(Scope.ALL);
      return stream;
    }).then(() => null, error => error);
    await settle();
    const closing = coordinator.terminate(Scope.ALL);
    media.prepareForClose();
    let closed = false;
    closing.then(() => { closed = true; });
    creation.resolve();
    await settle();
    assert.equal(closed, false);
    assert.equal(nativeRunning, true);
    assert.equal(events.includes('destroy'), false);
    release.resolve();
    await closing;
    assert.equal((await running).code, 'CANCELLED');
    assert.equal(nativeRunning, false);
    assert.equal(media.currentTrack, null);
    assert.deepEqual(events.filter(event => event !== 'prepare'),
      ['initialize', 'created', 'stopping', 'stopped', 'destroy']);
    assert.ok(instances.every(controller => controller.currentTrack === null));
  });
}

for (const source of ['Camera', 'Image', 'Video']) {
  test(`${source} preparation rollback finishes before IDLE and preserves the original error`, async () => {
    const release = gate(), states = [], events = [];
    let original, nativeRunning = false;
    class Controller {
      constructor() { this.currentTrack = null; }
      async create() { nativeRunning = true; this.currentTrack = {}; throw original; }
      async stop() {
        events.push('stopping');
        await release.promise;
        nativeRunning = false;
        this.currentTrack = null;
        events.push('stopped');
      }
      createLocalCameraStream() { return this.create(); }
      createLocalImageStream() { return this.create(); }
      createLocalVideoStream() { return this.create(); }
      stopLocalCameraStream() { return this.stop(); }
      stopLocalImageStream() { return this.stop(); }
      stopLocalVideoStream() { return this.stop(); }
    }
    const load = loadEts({
      '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
      CameraController: { CameraController: Controller },
      ImageController: { ImageController: Controller },
      VideoController: { VideoController: Controller },
      InteractionController: { InteractionController: class {} },
      XmaxLogger: { XmaxLogger: { error() {} } }
    });
    const { XmaxError, XmaxErrorCode: Code } = load('foundation/errors/XmaxError.ets');
    original = new XmaxError(Code.MEDIA_ERROR, 'partial creation failed', 123, 503);
    const { MediaController } = load('media/MediaController.ets');
    const { RealtimeCoordinator, RealtimeOperationKind: Kind } = load('core/realtime/RealtimeCoordinator.ets');
    const { RealtimeState, RealtimeConnectionState: State } = load('service/realtime/RealtimeState.ets');
    const { XmaxRealtimeErrorManager } = load('core/realtime/XmaxRealtimeErrorManager.ets');
    const media = new MediaController({}, {
      async initialize() {},
      async destroy() { assert.equal(nativeRunning, false); events.push('destroy'); }
    }, {}, () => {});
    const coordinator = new RealtimeCoordinator(new XmaxRealtimeErrorManager(), async () => {
      assert.fail('Creation owns its rollback; no lifecycle cleanup should be requested');
    });
    coordinator.setStateListener(state => {
      states.push(state);
      if (state.connectionState === State.IDLE) assert.equal(nativeRunning, false);
    });
    const running = coordinator.run(Kind.MEDIA, null, async token => {
      coordinator.commit(new RealtimeState(State.PREPARING), token);
      return await media[`createLocal${source}Stream`]('input');
    }).then(() => null, error => error);
    await settle();
    assert.equal(nativeRunning, true);
    assert.equal(coordinator.currentState.connectionState, State.PREPARING);
    release.resolve();
    assert.equal(await running, original);
    assert.equal(media.currentTrack, null);
    assert.deepEqual(events, ['stopping', 'stopped', 'destroy']);
    assert.deepEqual(states.map(state => state.connectionState), [State.IDLE, State.PREPARING, State.IDLE]);
    assert.ok(states.every(state => state.reason === undefined));
  });
}
