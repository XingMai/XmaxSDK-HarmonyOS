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
  let media;
  const renderCalls = [];
  class FakeMediaController {
    constructor(_context, _rtc, _stream, _error, _service, _format, ended) {
      media = this;
      this.ended = ended;
      this.currentTrack = null;
      this.localVideoPlaybackState = undefined;
    }
    setCameraPreviewReadyHandler() {}
    async createLocalVideoStream(_path, _format, loop) {
      this.loop = loop;
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
  assert.equal(media.loop, true);
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
  const completionStates = [];
  manager.setLocalVideoPlaybackStateListener(state => completionStates.push(state));
  await manager.createLocalVideoStream('once.mp4', undefined, false);
  assert.equal(media.loop, false);
  media.localVideoPlaybackState = State.ENDED;
  media.ended();
  assert.deepEqual(completionStates, [State.PLAYING, State.ENDED]);
  assert.equal(manager.currentState.connectionState, RealtimeConnectionState.READY);
  await assert.rejects(manager.resumeLocalVideoStream(), { code: 'INVALID_CONFIGURATION' });
  await assert.rejects(manager.pauseLocalVideoStream(), { code: 'INVALID_CONFIGURATION' });
  await assert.rejects(manager.toggleLocalVideoStreamPlayback(), { code: 'INVALID_CONFIGURATION' });
  manager.setLocalVideoPlaybackStateListener(state => { completionStates.push(state); });
  assert.equal(completionStates.at(-1), State.ENDED);
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
    constructor(_service, _audio, videoListener, audioListener, _error, ended) {
      this.ended = ended;
      this.videoListener = videoListener;
      this.audioListener = audioListener;
      this.hasAudio = true;
      this.volume = 0.45;
      this.pauseCalls = 0;
      this.resumeCalls = 0;
      source = this;
    }
    async prepare(_path, _format, loop) {
      this.loop = loop;
      return { videoFormat: { width: 2, height: 2, fps: 30 }, hasAudio: true };
    }
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
  let endedCount = 0;
  const controller = new VideoController({}, rtc, streamController, error => { throw error; }, undefined,
    () => { endedCount++; });
  await controller.createLocalVideoStream('video.mp4', undefined, false);
  assert.equal(source.loop, false);

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
  source.ended();
  source.ended();
  assert.equal(controller.playbackState, State.ENDED);
  assert.equal(endedCount, 1);
  assert.equal(videoFrames.at(-1).planes[0].data, pixels);
  assert.ok(audioFrames.at(-1).data.every(value => value === 0));
  assert.throws(() => controller.resumeLocalVideoStream(), { code: 'INVALID_CONFIGURATION' });
  await controller.stopLocalVideoStream();
  source.ended();
  assert.equal(endedCount, 1);
});
