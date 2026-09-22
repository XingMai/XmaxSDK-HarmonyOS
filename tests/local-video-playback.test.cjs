const test = require('node:test');
const assert = require('node:assert/strict');
const { loadEts } = require('./ets-loader.cjs');

test('media timeline keeps loop anchors stationary while paused', () => {
  let nowUs = 1_000_000;
  const load = loadEts({
    '@ohos.systemDateTime': {
      default: {
        getUptime: () => nowUs * 1000,
        TimeType: { ACTIVE: 0 }
      }
    }
  });
  const { MediaTimeline } = load('media/MediaTimeline.ets');
  const timeline = new MediaTimeline(0, 1_005_000);
  assert.equal(timeline.playbackAnchorForLoop(0), 1_100_000);
  assert.equal(timeline.playbackAnchorForLoop(1), 2_110_000);

  nowUs = 1_200_000;
  timeline.pause();
  nowUs = 1_700_000;
  assert.equal(timeline.resume(), 500_000);
  assert.equal(timeline.playbackAnchorForLoop(0), 1_600_000);
  assert.equal(timeline.playbackAnchorForLoop(1), 2_610_000);
});

test('manager controls playback and notifies listeners without a video view', async () => {
  let Track, Stream, State;
  const renderCalls = [];
  class FakeMediaController {
    constructor() {
      this.currentTrack = null;
      this.localVideoPlaybackState = undefined;
    }
    setCameraPreviewReadyHandler() {}
    async createLocalVideoStream() {
      this.currentTrack = new Track('video0');
      this.localVideoPlaybackState = State.PLAYING;
      return new Stream('local', this.currentTrack);
    }
    async pauseLocalVideoStream() { this.localVideoPlaybackState = State.PAUSE; }
    resumeLocalVideoStream() { this.localVideoPlaybackState = State.PLAYING; }
    async stopLocalVideoStream() {
      this.currentTrack = null;
      this.localVideoPlaybackState = undefined;
    }
  }
  const load = loadEts({
    '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
    '@ohos.systemDateTime': { default: { getUptime: () => 0, TimeType: { ACTIVE: 0 } } },
    XmaxLogger: { XmaxLogger: { error() {} } },
    RtcManager: { RtcManager: class {} },
    MediaService: { MediaService: class {} },
    MediaController: { MediaController: FakeMediaController },
    StreamController: { StreamController: class { setRemoteAudioVolume() {} } },
    RenderController: { RenderController: class {
      async freezeRemoteVideo() {
        renderCalls.push('freeze');
        if (renderCalls.length === 1) {
          // UI receives PAUSE before the native snapshot has completed.
          assert.deepEqual(states, [State.PLAYING, State.PAUSE]);
        }
      }
      async resumeRemoteVideo() { renderCalls.push('resume'); }
    } },
    XmaxRealtimeConnectionManager: { XmaxRealtimeConnectionManager: class {
      get currentSessionId() { return ''; }
    } },
    XmaxRealtimeGenerationManager: { XmaxRealtimeGenerationManager: class {} }
  });
  ({ RealtimeVideoTrack: Track } = load('service/realtime/RealtimeVideoTrack.ets'));
  ({ RealtimeMediaStream: Stream } = load('service/realtime/RealtimeMediaStream.ets'));
  ({ LocalVideoPlaybackState: State } = load('service/realtime/LocalVideoPlaybackState.ets'));
  const { XmaxRealtimeManager } = load('core/realtime/XmaxRealtimeManager.ets');
  const { RealtimeConnectionState } = load('service/realtime/RealtimeState.ets');
  const manager = new XmaxRealtimeManager({}, { model: {} }, {});
  const states = [];
  manager.setLocalVideoPlaybackStateListener(state => states.push(state));
  assert.equal(manager.localVideoPlaybackState, undefined);
  assert.deepEqual(states, []);
  await assert.rejects(manager.pauseLocalVideoStream(), { code: 'INVALID_CONFIGURATION' });

  await manager.createLocalVideoStream('video.mp4');
  assert.deepEqual(states, [State.PLAYING]);
  await manager.toggleLocalVideoStreamPlayback();
  assert.equal(manager.localVideoPlaybackState, State.PAUSE);
  assert.equal(manager.currentState.connectionState, RealtimeConnectionState.READY);
  await manager.toggleLocalVideoStreamPlayback();
  assert.deepEqual(states, [State.PLAYING, State.PAUSE, State.PLAYING]);
  assert.deepEqual(renderCalls, ['freeze', 'resume']);

  const replacementStates = [];
  manager.setLocalVideoPlaybackStateListener(state => replacementStates.push(state));
  assert.deepEqual(replacementStates, [State.PLAYING]);
  await manager.pauseLocalVideoStream();
  assert.deepEqual(replacementStates, [State.PLAYING, State.PAUSE]);
  assert.equal(states.length, 3);

  manager.setLocalVideoPlaybackStateListener(null);
  await manager.resumeLocalVideoStream();
  assert.equal(replacementStates.length, 2);
  await manager.stopLocalVideoStream();
  assert.equal(manager.localVideoPlaybackState, undefined);
  assert.equal(manager.currentState.connectionState, RealtimeConnectionState.IDLE);
  await assert.rejects(manager.resumeLocalVideoStream(), { code: 'INVALID_CONFIGURATION' });

  manager.setLocalVideoPlaybackStateListener(state => { throw new Error(`Consumer failed: ${state}`); });
  await manager.createLocalVideoStream('another-video.mp4');
  await manager.pauseLocalVideoStream();
  assert.equal(manager.localVideoPlaybackState, State.PAUSE);
  await manager.stopLocalVideoStream();
});

test('video pause freezes source position while publishing repeated video and silent audio', async () => {
  let nowUs = 2_000_000;
  let source;
  class FakeMediaSourceController {
    constructor(_service, _audio, videoListener, audioListener) {
      this.videoListener = videoListener;
      this.audioListener = audioListener;
      this.hasAudio = true;
      this.volume = 0.45;
      this.pauseCalls = 0;
      this.resumeCalls = 0;
      source = this;
    }
    async prepare() { return { videoFormat: { width: 2, height: 2, fps: 30 }, hasAudio: true }; }
    async start() {}
    async pause() { this.pauseCalls++; }
    resume() { this.resumeCalls++; }
    async stop() {}
    setLocalAudioPreviewEnabled() {}
    get localAudioVolume() { return this.volume; }
    async setLocalAudioVolume(value) { this.volume = value; }
  }
  class FakeAudioManager {}
  class FakePermissionManager { async ensureMicrophonePermission() {} }
  class FakeMediaService {}
  class FakeVideoRenderBinding { constructor() {} }
  const renderBindings = new Map();
  const videoFrames = [];
  const audioFrames = [];
  const streamController = {
    setVideoEncoderConfig() {},
    pushLocalVideoFrame: frame => videoFrames.push(frame),
    pushLocalAudioFrame: frame => audioFrames.push(frame)
  };
  const rtc = {
    useExternalVideoSource() {}, startExternalAudioSource() {}, stopExternalAudioSource() {},
    renderLibraryName: () => 'rtc', bindLocalVideo() {}, unbindLocalVideo() {}
  };
  const load = loadEts({
    '@kit.AbilityKit': { common: {} },
    '@ohos.systemDateTime': {
      default: {
        getUptime: () => nowUs * 1000,
        TimeType: { ACTIVE: 0 }
      }
    },
    '@kit.ArkUI': { UIUtils: { getTarget: value => value } },
    XmaxLogger: { XmaxLogger: {
      localized: (chinese, _english) => chinese,
      error() {}
    } },
    AudioManager: { AudioManager: FakeAudioManager },
    PermissionManager: { PermissionManager: FakePermissionManager },
    MediaService: { MediaService: FakeMediaService },
    MediaSourceController: { MediaSourceController: FakeMediaSourceController },
    VideoRenderRegistry: {
      VideoRenderBinding: FakeVideoRenderBinding,
      VideoRenderRegistry: {
        register: (track, binding) => renderBindings.set(track, binding),
        unregister: track => renderBindings.delete(track)
      }
    }
  });
  const { VideoController } = load('media/video/VideoController.ets');
  const { BufferVideoFrame } = load('foundation/media/video/BufferVideoFrame.ets');
  const { VideoFormat } = load('foundation/media/video/VideoFormat.ets');
  const { VideoFramePlane } = load('foundation/media/video/VideoFramePlane.ets');
  const { VideoPixelFormat } = load('foundation/media/video/VideoPixelFormat.ets');
  const { VideoRotation } = load('foundation/media/video/VideoRotation.ets');
  const { AudioFrame } = load('foundation/media/audio/AudioFrame.ets');
  const { LocalVideoPlaybackState: State } = load('service/realtime/LocalVideoPlaybackState.ets');
  const controller = new VideoController({}, rtc, streamController, error => { throw error; });
  await controller.createLocalVideoStream('video.mp4');

  const pixels = new ArrayBuffer(6);
  const frame = new BufferVideoFrame(
    new VideoFormat(2, 2, VideoPixelFormat.NV12),
    nowUs,
    [new VideoFramePlane(pixels, 2, 0, 4), new VideoFramePlane(pixels, 2, 4, 2)],
    VideoRotation.ROTATION_0
  );
  source.videoListener(frame);
  source.audioListener(new AudioFrame(new Uint8Array([1, 2]), nowUs));
  nowUs += 10_000;
  await controller.pauseLocalVideoStream();

  assert.equal(source.pauseCalls, 1);
  assert.equal(controller.playbackState, State.PAUSE);
  assert.ok(videoFrames.length >= 2);
  assert.equal(videoFrames.at(-1).planes[0].data, pixels);
  assert.ok(videoFrames.at(-1).timestampUs > frame.timestampUs);
  assert.ok(audioFrames.length >= 2);
  assert.ok(audioFrames.at(-1).data.every(value => value === 0));

  controller.resumeLocalVideoStream();
  assert.equal(source.resumeCalls, 1);
  assert.equal(controller.playbackState, State.PLAYING);
  await controller.stopLocalVideoStream();
});

test('remote freeze snapshot converts and rotates I420 into an owned RGBA pixel map', async () => {
  let captured;
  const load = loadEts({
    '@kit.ImageKit': { image: {
      PixelMapFormat: { RGBA_8888: 0 },
      createPixelMap: async (data, options) => {
        captured = { data: new Uint8Array(data.slice(0)), options };
        return captured;
      }
    } }
  });
  const { RealtimeVideoFramePixelMap } =
    load('rendering/video/RealtimeVideoFramePixelMap.ets');
  const { RealtimeVideoFrame } = load('service/realtime/RealtimeVideoFrame.ets');
  const { VideoFramePlane } = load('foundation/media/video/VideoFramePlane.ets');
  const { VideoPixelFormat } = load('foundation/media/video/VideoPixelFormat.ets');
  const { VideoRotation } = load('foundation/media/video/VideoRotation.ets');
  const y = Uint8Array.from([16, 82, 145, 235, 41, 210, 100, 180]);
  const u = Uint8Array.from([128, 128]);
  const v = Uint8Array.from([128, 128]);
  const cases = [
    [VideoRotation.ROTATION_0, 2, 4, [0, 77, 150, 255, 29, 226, 98, 191]],
    [VideoRotation.ROTATION_90, 4, 2, [98, 29, 150, 0, 191, 226, 255, 77]],
    [VideoRotation.ROTATION_180, 2, 4, [191, 98, 226, 29, 255, 150, 77, 0]],
    [VideoRotation.ROTATION_270, 4, 2, [77, 255, 226, 191, 0, 150, 29, 98]]
  ];
  for (const [rotation, width, height, expected] of cases) {
    const frame = new RealtimeVideoFrame(2, 4, VideoPixelFormat.I420, [
      new VideoFramePlane(y.buffer, 2),
      new VideoFramePlane(u.buffer, 1),
      new VideoFramePlane(v.buffer, 1)
    ], 1, rotation);

    const pixelMap = await RealtimeVideoFramePixelMap.create(frame);
    assert.equal(pixelMap, captured);
    assert.deepEqual(captured.options.size, { width, height });
    const red = Array.from(captured.data).filter((_, index) => index % 4 === 0);
    assert.deepEqual(red, expected, `rotation ${rotation}`);
    const alpha = Array.from(captured.data).filter((_, index) => index % 4 === 3);
    assert.deepEqual(alpha, Array(8).fill(255));
  }
});
