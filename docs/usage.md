# Usage guide

Start with the [Quick Start](../README.md#quick-start) for camera input and ArkUI
rendering. Unless stated otherwise, these examples reuse its `client`, `realtime`
and `localStream`, and the component's local and remote track state. File paths
refer to files supplied by your app. Run realtime operations from a lifecycle-aware
component and handle rejected promises.

- [Create an input stream](#create-an-input-stream)
- [Model capabilities](#model-capabilities)
- [Service environments](#service-environments)
- [Reference Image Upload](#reference-image-upload)
- [Render local preview and generated video](#render-local-preview-and-generated-video)
- [Receive remote video frames](#receive-remote-video-frames)
- [Start generation in one call](#start-generation-in-one-call)
- [Touch Interaction](#touch-interaction)
- [Adjust playback volume](#adjust-playback-volume)
- [Switch cameras or change capture specifications](#switch-cameras-or-change-capture-specifications)
- [Stop and release resources](#stop-and-release-resources)
- [Observe lifecycle and failures](#observe-lifecycle-and-failures)
- [Configure SDK logging](#configure-sdk-logging)
- [Generation startup timing](#generation-startup-timing)
- [Runtime information and task IDs](#runtime-information-and-task-ids)

<br>

## Create an input stream

Create a live camera stream after declaring the required permissions:

```ts
const localStream = await realtime.createLocalCameraStream();
// For explicit capture settings, pass a RealtimeVideoFormat and CameraPosition.
```

Camera microphone input is optional and defaults to `false`. To enable it:

```ts
import { CameraPosition } from '@xmax/sdk';

const localStream = await realtime.createLocalCameraStream(
  undefined, CameraPosition.FRONT, true
);
```

Declare `ohos.permission.MICROPHONE` in the application's permission configuration.
The SDK checks microphone permission when creating the camera stream and rejects
with `MICROPHONE_PERMISSION_DENIED` if permission is unavailable. Local preview
alone does not capture microphone audio. Connecting starts RTC's internal audio
capture and publishes it alongside CameraKit video; disconnecting, connection
failure, or closing stops capture. Reconnecting reuses the microphone setting.
Camera switching preserves it. Microphone audio is not played back locally, and
`localAudioVolume` continues to control file-video preview audio only.


For `x2.0`, still images and local video files can also be used as input sources:

```ts
const imageStream = await realtime.createLocalImageStream(imageFilePath);
const videoStream = await realtime.createLocalVideoStream(videoFilePath);
```

Only one local input stream may be active at a time.

## Model capabilities

`RealtimeModels.realtime(model)` returns a `ModelDefinition` describing supported
input resolutions, pixel bounds, alignment, default frame rate and camera format.
Camera, video and image inputs are available for both models.

| Model | Input resolution rules | Default FPS | Default camera |
| --- | --- | --- | --- |
| `x2.0` | 600,000–1,280,000 pixels, width and height aligned to 32 | 30 | 832 × 1472 |
| `x2.0-pro` | Exactly 1024 × 1920 or 1920 × 1024 | 30 | 1024 × 1920 |

```ts
import { ImageSize } from '@xmax/sdk';

const model = RealtimeModels.realtime(RealtimeModel.X2_0_PRO);
const supportedResolutions = model.resolutionBuckets;
const realtime = client.createRealtimeManager(new RealtimeConfiguration(model));
const localStream = await realtime.createLocalCameraStream();

const mediaService = client.createMediaService(RealtimeModel.X2_0_PRO);
const inputSize = mediaService.resolveModelInputSize(new ImageSize(1024, 1920));
```

A nonempty `resolutionBuckets` list requires an exact width/height match.
Unsupported Pro dimensions reject with `INVALID_CONFIGURATION`; the SDK does not
round or resize them to a supported bucket. An empty list, as in `x2.0`, uses
pixel bounds and alignment to calculate the input size.

`createMediaService()` defaults to `x2.0`; pass the model when calculating sizes
for another model. These rules apply to camera, image and video preparation.
Image and video inputs use their display dimensions unless an explicit
`RealtimeVideoFormat` is supplied; for Pro, supply a supported output format when
the source dimensions do not match a bucket. CameraKit raw capture can still use
16:9 profiles; the fixed-resolution rule applies to the prepared model input.

The former `x2.0-sla` model is replaced by `x2.0-pro`. XLab migrates a saved SLA
selection to Pro and keeps all three media entries available.

## Service environments

The China service environment is used by default. Select the global environment
when creating the client to route realtime-session and storage API requests to
Xmax's global service:

```ts
import { XmaxConfiguration, XmaxEnvironment } from '@xmax/sdk';

const configuration = new XmaxConfiguration(
  'YOUR_API_KEY',
  XmaxEnvironment.GLOBAL
);
```

Use `XmaxEnvironment.CHINA` to select the China service explicitly. RTC room
credentials and storage configuration are returned by the selected service.

SDK log details use Chinese for `CHINA` and English for `GLOBAL`; bilingual log
headings are retained. Logging options and language are global: the most recently
created client's configuration takes effect. Original server/platform error
messages and error codes are preserved, and credential redaction still applies.

The globe button at the top right of XLab's home page offers **System default**,
**简体中文**, and **English**. The
selection persists across launches. System Chinese uses Simplified Chinese;
other system languages fall back to English. Chinese selects the China service
and API-key portal; English selects the global service and portal. Realtime,
reference-image upload, and storage clients use this selection when created.
Changing language updates UI text without rebuilding an active media pipeline.
Preset generation prompts and user/server content are not translated.

Omitting a camera format uses `defaultCameraVideoFormat`. For images and videos,
omitting the format derives dimensions from the source's display size and uses
`defaultFrameRate`; an explicit format preserves the requested frame rate while
resolving dimensions against model bounds. HarmonyOS XLab uses model camera
defaults directly; frame interpolation is not currently supported.

## Reference Image Upload

`RealtimeContext.referencePath` requires a remote image URL. To use an on-device
image, upload it through the storage manager and supply the resulting URL:

```ts
const storage = client.createStorageManager();

const uploaded = await storage.uploadImageFile(
  imageFilePath,
  'image/jpeg'
);

const referenceImageUrl = uploaded.url;
```

The storage manager uses temporary credentials obtained from Xmax. Tencent Cloud
credentials are not embedded in the host application.

## Render local preview and generated video

Store the tracks in component state and render them with `XmaxRealtimeVideoView`:

```ts
import {
  RealtimeVideoTrack,
  VideoContentMode,
  XmaxRealtimeVideoView
} from '@xmax/sdk';

@State private localVideoTrack: RealtimeVideoTrack | undefined = undefined;
@State private remoteVideoTrack: RealtimeVideoTrack | undefined = undefined;

// After creating the input stream:
this.localVideoTrack = localStream.videoTrack;

build() {
  XmaxRealtimeVideoView({
    localTrack: this.localVideoTrack,
    remoteTrack: this.remoteVideoTrack,
    contentMode: VideoContentMode.FILL
  })
    .width('100%')
    .height('100%')
}
```

The component keeps the local preview underneath the remote video. A new remote
track fades in over 300 ms after RTC reports its first rendered frame. Clearing
`remoteTrack` to `undefined` immediately restores the local preview. For a reused
RTC stream, the component can reuse its existing rendered-frame readiness; this
state is cleared when the remote publisher stops or the session ends.

Use `VideoContentMode.FIT` to preserve the aspect ratio of image and local video
inputs. `isInteractionEnabled` controls remote touch interaction; a custom
`trajectoryRenderer` may be supplied when creating the component. The existing
`XmaxVideoView` remains available for displaying one track. Both components react
to track replacements, including streams recreated with different dimensions.

## Receive remote video frames

Register a listener before or during generation to receive RTC post-processed
video frames. No public listener means no pixel copy for frame delivery.

```ts
import { RealtimeVideoFrame } from '@xmax/sdk';

realtime.setRemoteVideoFrameListener((frame: RealtimeVideoFrame): void => {
  // I420 planes are ordered Y, U, V. Each plane exposes data, stride,
  // byteOffset and byteLength. Buffers remain valid after this callback returns.
  const yPlane = frame.planes[0];
  const yBytes = new Uint8Array(yPlane.data, yPlane.byteOffset, yPlane.byteLength);
  // Use frame.width, frame.height, frame.rotation and frame.timestampUs
  // when handing pixels to your recorder or image-processing worker.
});

// Stop public delivery and discard queued frames:
realtime.setRemoteVideoFrameListener(null);
```

`RealtimeVideoFrame` exposes `width`, `height`, `pixelFormat`, `planes`,
`timestampUs` and `rotation`. The current output format is `VideoPixelFormat.I420`.
Dimensions describe the pixel buffer before applying its clockwise rotation.
These frames exclude view-level FIT/FILL cropping, mirroring and UI overlays.
Timestamps are in microseconds and need not start at zero; use the first received
frame as the recording timeline origin.

The SDK copies visible pixels into independent buffers before the RTC callback
returns. Each successfully converted frame is delivered asynchronously in receive
order on the ArkTS event loop; pending frames are not merged or replaced by newer
ones. This does not recover frames dropped upstream by RTC. Keep the callback
short and move expensive processing to a Worker to avoid blocking the event loop
and accumulating queued frames.

Stopping generation, disconnecting, closing, replacing the stream or changing the
listener invalidates pending delivery. The listener remains configured across
sessions until explicitly removed. Sink activation failures throw `XmaxError`
from the setter; exceptions thrown by the listener are logged without stopping
generation.

## Start generation in one call

Pass the local stream and generation context. The SDK establishes a connection on
demand and returns the remote media stream when generation starts:

```ts
import { RealtimeContext } from '@xmax/sdk';

const remoteStream = await realtime.startGeneration(
  localStream,
  new RealtimeContext('视频中角色替换成参考图中角色', referenceImageUrl)
);
this.remoteVideoTrack = remoteStream.videoTrack;
```

The SDK matches the task's SEI, waits for a usable remote video frame,
activates remote audio, and then emits `RealtimeConnectionState.GENERATING` before
the call returns. While waiting for the frame, the state remains `CONNECTED`.
Frame readiness does not require a mounted video view and has a 10-second timeout
after SEI confirmation. Each new generation waits for a new frame, including when
reusing the same RTC stream. A timeout or cancellation stops that generation;
remote audio is also unsubscribed when generation stops.

Creating a local stream only starts local preview. The call above creates the
server session; subsequent calls reuse the connection and remote track. During
an active generation, a new context updates the current task. To cancel generation,
call `disconnect()`. Starting again creates a new session and requires a context:

```ts
await realtime.disconnect();
this.remoteVideoTrack = undefined;

const resumedStream = await realtime.startGeneration(localStream, generationContext);
this.remoteVideoTrack = resumedStream.videoTrack;
```

A new connection requires a context. The local stream must still belong to this
manager. A usable first frame and its actual display are separate events:
assign the returned remote track to the component so RTC can render it.

The explicit connection and context-only generation APIs remain supported:

```ts
const remoteStream = await realtime.connect(localStream);
await realtime.startGeneration(new RealtimeContext('将人物服装替换成参考图中的服装', referenceImageUrl));
this.remoteVideoTrack = remoteStream.videoTrack;
```

Only one local-media, connection, generation, or camera-switch operation may run
at a time. Overlapping operations and new operations during cleanup reject with
`XmaxErrorCode.INVALID_CONFIGURATION`; await the current operation before retrying.
`disconnect()` cancels an in-flight connection or generation, stops microphone
capture and retains local preview. `close()` additionally releases local media.
A cancelled operation rejects with `XmaxErrorCode.CANCELLED`.

## Touch Interaction

During an active generation task, the remote view in `XmaxRealtimeVideoView` (or
a standalone `XmaxVideoView`) captures multi-touch trajectories
over the generated video and submits them to the active task. The host application
does not need to implement gesture tracking or coordinate conversion.

Trajectory interaction is enabled by default. Disable it when touch input must be
handled by the surrounding user interface:

```ts
import { XmaxVideoView } from '@xmax/sdk';

XmaxVideoView({
  track: this.remoteVideoTrack,
  contentMode: VideoContentMode.FILL,
  isInteractionEnabled: false
})
```

## Adjust playback volume

Control local video preview and generated audio separately, including before creating a stream or connecting:

```ts
await realtime.setLocalAudioVolume(0.45); // Local video preview; default 45%.
await realtime.setRemoteAudioVolume(1);   // Set after creating the local stream.
const localVolume: number = realtime.localAudioVolume;
const remoteVolume: number = realtime.remoteAudioVolume;
```

Both methods accept finite values from `0` (mute) to `1` (original volume) and reject invalid values with `INVALID_CONFIGURATION`. Local volume persists across stream replacement and reconnection on the same manager. Remote volume starts at `1`; successfully creating a camera or image stream resets it to `0`, while creating a video stream resets it to `1`. Set custom remote volume after creating the local stream; it persists through camera switching and reconnection. The remote getter returns the applied RTC percentage normalized to `0`–`1` (for example, `0.356` becomes `0.36`). Local volume does not affect uploaded audio or override automatic preview muting during generation. XLab's video input page exposes both sliders and a shared mute switch in its top bar. Camera input exposes a remote-volume slider beneath the camera flip button, initialized from the SDK's current volume.

## Switch cameras or change capture specifications

Camera output follows the current display orientation: the short side is the
width in portrait, and the long side is the width in landscape. For example,
`1024 × 1920` becomes `1920 × 1024`, with the frame rate unchanged. CameraKit
prefers 16:9 YUV capture profiles, starting at `1920 × 1080` and trying smaller
profiles until one supports 30 fps. If none does, it falls back to 4:3 profiles
starting at `1920 × 1440`. A 16:9 capture corresponds to 9:16 in portrait.
Native rotation and cropping still produce the model's required input dimensions.

`XmaxVideoView` and `XmaxRealtimeVideoView` observe the orientation of their
window for camera, image, and video-file input. Switching between portrait and
landscape while `CONNECTING`, `CONNECTED`, or `GENERATING` automatically
disconnects and retains the local preview. The SDK cancels pending operations with
`CANCELLED`, stops the old task, and does not automatically reconnect or send the
new orientation to the old task through `change_condition`. Frames queued with
the previous dimensions are discarded before pushing to RTC.

After cleanup, the state returns to `READY` when local media remains available,
or `IDLE` otherwise. `state.reason` is `RealtimeReason.ORIENTATION_CHANGED` for
orientation changes and `RealtimeReason.NORMAL` for normal cleanup. Applications can
use the existing state listener to clear pending generation intent and display a
message; no app-level rotation listener or disconnect call is required.
`DISCONNECTING` carries no reason. Starting a new operation clears the old reason.

```ts
realtime.setStateListener((state: RealtimeState): void => {
  if (state.reason?.kind === RealtimeReasonKind.ORIENTATION_CHANGED) {
    // Show an app-specific message asking the user to start again.
  }
});
```

Rotation during local preview does not disconnect. Initial view attachment and
rotation within the same portrait/landscape axis do not trigger disconnection.
Camera output dimensions follow the display orientation and are synchronized
before reconnecting; image and video-file input retain their source dimensions.
The camera also detects capture orientation changes without an attached SDK view.

`switchCamera()` changes front/back position while preserving the local track and
its frame rate and orientation-dependent dimensions. During generation, the SDK stops the current task,
switches cameras, waits 500 ms for capture to settle, then starts a new task with
the latest successful context. The connection and remote track are retained.
Do not switch while a connection or generation start is pending. Calling
`disconnect()` during the switch prevents automatic restart.

```ts
const switchedStream = await realtime.switchCamera();
this.localVideoTrack = switchedStream.videoTrack;
```

`replaceLocalCameraStream()` has been removed. To change resolution or frame rate,
recreate the local stream after disconnecting, then start a new session:

```ts
import { CameraPosition, RealtimeVideoFormat } from '@xmax/sdk';

await realtime.disconnect();
this.remoteVideoTrack = undefined;
await realtime.stopLocalCameraStream();
this.localVideoTrack = undefined;

const resizedStream = await realtime.createLocalCameraStream(
  new RealtimeVideoFormat(1024, 1920, 30),
  CameraPosition.FRONT
);
this.localVideoTrack = resizedStream.videoTrack;
const resizedRemoteStream = await realtime.startGeneration(
  resizedStream,
  new RealtimeContext('视频中角色替换成参考图中角色', referenceImageUrl)
);
this.remoteVideoTrack = resizedRemoteStream.videoTrack;
```

The old local stream is no longer valid after stopping it. Input dimensions follow
the selected model's pixel bounds and 32-pixel alignment. Use the returned track's
`videoFormat` to inspect the resolved dimensions; for example, `1024 × 1920` is
retained for `x2.0-pro` and reduced to `800 × 1536` for `x2.0`.

## Upload encoding configuration

`RealtimeVideoFormat` also accepts `minimumBitrate`, `maximumBitrate` (in kbps),
and `encoderPreference`. These settings apply to camera, video and image streams:

```ts
import { RealtimeVideoFormat, RealtimeVideoEncoderPreference } from '@xmax/sdk';

const format = new RealtimeVideoFormat(
  1024, 1920, 30,
  1500, 6000,
  RealtimeVideoEncoderPreference.MAINTAIN_FRAMERATE
);
const stream = await realtime.createLocalCameraStream(format);
```

Omit either bitrate (or pass `undefined`) to calculate that bound from the final
upload dimensions and frame rate, using the same rules as iOS. A minimum of `0`
disables the lower bound; an explicit maximum must be positive. The minimum must
not exceed the maximum, including after SDK defaults are applied. Invalid
configurations throw `INVALID_CONFIGURATION`.

`AUTO` (default) balances frame rate and resolution, `MAINTAIN_FRAMERATE` prioritizes
frame rate, and `MAINTAIN_QUALITY` prioritizes resolution. Resizing and camera
orientation changes preserve these settings. To change encoding settings, recreate
the local stream after disconnecting, as shown above.

## Stop and release resources

```ts
import { RealtimeReason } from '@xmax/sdk';

// Cancel generation and end the remote session while retaining local preview:
await realtime.disconnect();

// Or disconnect with a business reason:
await realtime.disconnect(RealtimeReason.ORIENTATION_CHANGED);

// Or leave the screen and release all resources:
await realtime.close();
```

`disconnect()` ends generation, stops microphone capture and closes the remote
session while preserving local preview. `close()` releases all local media and RTC
resources and should be called when the realtime workflow is no longer required.

`disconnect(reason?: RealtimeReason)` defaults to `RealtimeReason.NORMAL`.
When a disconnection occurs, the final `READY` (or `IDLE` if no local media remains)
state carries the reason in `state.reason`; `DISCONNECTING` has no reason yet.
`RealtimeReason.failure(error)` preserves the supplied `XmaxError` in that state.
Calling disconnect without a connection or an affected operation is a no-op,
including during local media preparation. Concurrent requests retain the first
disconnection reason; late connection errors do not overwrite it. A local media
failure can still require full cleanup and replace the reason with that failure.

When applicable, these methods wait for affected operations and resource cleanup to finish.
For example, closing while a session request is pending waits for the late session
to be rolled back. Concurrent disconnect/close requests share a cleanup task
and expand its scope as needed. Cleanup failures are logged while the remaining
resources continue to be released.

## Observe lifecycle and failures

`setStateListener()` is the single public callback for lifecycle state, local
preview readiness and failures. Register it before creating local media.

| State | Meaning |
| --- | --- |
| `IDLE` | No available local media. |
| `PREPARING` | Preparing local media; camera preview awaits a valid frame and view binding. |
| `READY` | Local media is ready; no active realtime connection. |
| `CONNECTING` | Creating the session and joining the room. |
| `CONNECTED` | Connected without an active generation task. |
| `GENERATING` | The generated stream and a usable remote frame are ready. |
| `DISCONNECTING` | Cleaning up resources. |

Image/video creation enters `READY` when preparation completes. Camera creation
returns a track while `PREPARING`; bind it to a preview view to receive `READY`.
A generation or connection failure closes the connection and returns to `READY`
if local media remains available. Failed local preparation rolls back the partial
media and returns directly from `PREPARING` to `IDLE`, without `DISCONNECTING` or
`state.reason`; catch the original error from the creation call. A local-media
runtime error releases local resources and returns to `IDLE` with a failure reason.

States completing a disconnection or full cleanup carry `reason`: `RealtimeReason.NORMAL`,
`RealtimeReason.ORIENTATION_CHANGED`, or `RealtimeReason.failure(error)`.
Use `reason.kind` to distinguish cases and `reason.error` to read the original
`XmaxError`, including its code, API code and HTTP status.
The SDK finishes internal cleanup before notifying the terminal state, so the
listener can start a new operation or close the manager safely.

```ts
const reportedErrors = new WeakSet<XmaxError>();
realtime.setStateListener((state: RealtimeState): void => {
  const error = state.reason?.error;
  if (error !== undefined) {
    reportedErrors.add(error);
    console.error(`${error.code}: ${error.message}`);
  }
});

try {
  const remoteStream = await realtime.startGeneration(localStream, generationContext);
  this.remoteVideoTrack = remoteStream.videoTrack;
} catch (error) {
  const sdkError = XmaxError.from(error);
  if (sdkError.code !== XmaxErrorCode.CANCELLED && !reportedErrors.has(sdkError)) {
    console.error(`Operation failed: ${sdkError.message}`);
  }
}
```

Awaited operations still reject with the original error. Local preparation, validation
or configuration-update failures that do not end a lifecycle remain on the
operation's rejection path. Cancellation rejects with `CANCELLED`; cleanup
failures are logged while cleanup continues. State notifications work even when
logging is disabled; passing `null` to `setStateListener()` removes the listener.

Errors do not carry a severity level. Cleanup depends on the operation and its
stage: connection and generation-start failures close the connection; preparation
failures roll back partially created media, while local runtime failures release
all media. Validation and configuration
update failures leave the current lifecycle intact. Use the state listener for
lifecycle failures and camera readiness.

## Configure SDK logging

SDK logging is **off by default**, in both debug and release builds. Set
`loggerOptions` when creating a client to opt in:

```ts
import {
  XmaxClient,
  XmaxConfiguration,
  XmaxEnvironment,
  XmaxLoggerOption
} from '@xmax/sdk';

const client = new XmaxClient(
  new XmaxConfiguration(
    'YOUR_API_KEY',
    XmaxEnvironment.CHINA,
    XmaxLoggerOption.BUSINESS | XmaxLoggerOption.PERFORMANCE
  ),
  context
);
```

| Option | Output |
| --- | --- |
| `NONE` | No SDK logs (default) |
| `BUSINESS` | API, Room, Realtime, Storage and other operation logs, including errors |
| `PERFORMANCE` | Generation startup timing, RTC stream statistics, network quality and performance alarms |
| `ALL` | Both business and performance logs |

This is an SDK-global setting: the most recently created client's
configuration replaces the previous setting, including `NONE`. Use consistent
options across clients. The XLab example explicitly enables `ALL` for diagnostics.
The switch controls XmaxSDK's HiLog output; host-application logging and the
third-party RTC SDK's own logs have separate controls. Network-quality and
performance-alarm listeners continue to work when their logs are disabled.

## Generation startup timing

Enable `XmaxLoggerOption.PERFORMANCE` or `ALL` to receive `[Xmax][Timing]` HiLog
reports. XLab uses `ALL`, so timing is already enabled there. The internal
`RealtimeTiming` component measures each admitted generation start with a
monotonic clock, from startup through committing `GENERATING` after a usable
remote frame arrives. This is separate from the frame actually appearing in a view.

Successful reports include total startup time and these stages when applicable:

- Realtime connection, including session creation, RTC room join and connection preparation.
- Waiting for matching task SEI, including local request sending.
- Matching the result stream through first-frame readiness.

Successful reports show only the total and these stage durations, without
substage details. A start using an existing connection omits connection setup.
Updating generation conditions and rejected overlapping calls
do not reset the current measurement or create another startup report.

Failures report elapsed time, the pending stage and the failure reason after
operation cleanup; elapsed failure time therefore includes rollback. Cancelled
starts emit no failure timing report. Retries have independent records, and late
SEI or completion from an old task cannot alter a new task's timing. Timing does
not change the operation's error or connection state.

## Runtime information and task IDs

The SDK automatically adds the same cached runtime information to every Xmax API
request and to the top-level `runtime` object in all five room events: `start`,
`change_condition`, `stop`, `tracks`, and `heartbeat`.

| API header | Room `runtime` field | HarmonyOS value |
| --- | --- | --- |
| `X-Platform` | `platform` | `harmonyos` |
| `X-OS-Version` | `os_version` | Distribution OS version, falling back to the full OS name |
| `X-SDK-Version` | `sdk_version` | HAR version, also exported as `XMAX_SDK_VERSION` |
| `X-Device-Model` | `device_model` | Device product model |

Unavailable OS or device information is reported as `unknown`. No application
configuration is required. Runtime metadata is added to API headers, without
changing API request bodies.

Generation task IDs use `task-<id>?os=harmonyos`, where `<id>` contains the full
16 UUID bytes encoded as 22 unpadded Base64URL characters. Room events use that
complete task ID as their `uid`. During camera, image, and video generation, each
outgoing video frame carries UTF-8 SEI in the form
`task-<id>?os=harmonyos&index=<frame-index>`, with the zero-based frame index reset
for each generation task. Incoming SEI is matched by the task identity before `?`; query parameters such
as `os` and `index` do not affect matching. The bare task identity is also accepted.
