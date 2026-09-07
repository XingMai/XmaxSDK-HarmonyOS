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
- [Start generation in one call](#start-generation-in-one-call)
- [Touch Interaction](#touch-interaction)
- [Adjust playback volume](#adjust-playback-volume)
- [Switch cameras or change capture specifications](#switch-cameras-or-change-capture-specifications)
- [Stop and release resources](#stop-and-release-resources)
- [Handle recoverable and fatal errors](#handle-recoverable-and-fatal-errors)
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

For `x2.0`, still images and local video files can also be used as input sources:

```ts
const imageStream = await realtime.createLocalImageStream(imageFilePath);
const videoStream = await realtime.createLocalVideoStream(videoFilePath);
```

Only one local input stream may be active at a time.

## Model capabilities

`RealtimeModels.realtime(model)` returns a `ModelDefinition` describing the model's
supported media sources, input pixel bounds, alignment, default frame rate and
default camera format.

| Model | Media sources | Input pixels | Alignment | Default FPS | Default camera |
| --- | --- | --- | --- | --- | --- |
| `x2.0` | Camera, video, image | 600,000–1,280,000 | 32 | 24 | 832 × 1472 |
| `x2.0-sla` | Camera only | 600,000–2,100,000 | 32 | 30 | 1024 × 1920 |

```ts
import { ImageSize, RealtimeMediaSource } from '@xmax/sdk';

const model = RealtimeModels.realtime(RealtimeModel.X2_0_SLA);
const realtime = client.createRealtimeManager(new RealtimeConfiguration(model));
const localStream = await realtime.createLocalCameraStream();
const supportsImage = model.supportedMediaSources.has(RealtimeMediaSource.IMAGE);

const mediaService = client.createMediaService(RealtimeModel.X2_0_SLA);
const inputSize = mediaService.resolveModelInputSize(new ImageSize(1024, 1920));
```

`createMediaService()` defaults to `x2.0`; pass the model when calculating sizes
for another model. The realtime manager shares its model's media rules across
camera, image and video preparation. Alignment is checked against pixel bounds
again so rounding cannot produce an out-of-range input size.

Unsupported sources reject with `INVALID_CONFIGURATION` and `RECOVERABLE`
severity before media preparation begins, preserving any active input and session.
Use `supportedMediaSources` to configure your UI. XLab dims unsupported entries
and prompts the user to switch models when they are tapped.

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
an active generation, a new context updates the current task. After
`stopGeneration()`, omit the context to reuse the last successful context in that
connection:

```ts
await realtime.stopGeneration();
this.remoteVideoTrack = undefined;

const resumedStream = await realtime.startGeneration(localStream);
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
`stopGeneration()` only acts when a session exists and the state is `CONNECTED`
or `GENERATING`. It can cancel a pending generation start on that connection.
In `CONNECTING` or any other state, it returns immediately; an in-flight one-call
generation still continues after connecting. Use `disconnect()` or `close()` to
cancel that workflow. A cancelled operation rejects with
`XmaxErrorCode.CANCELLED`.

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
await realtime.setRemoteAudioVolume(1);   // Generated audio; default 100%.
```

Both methods accept finite values from `0` (mute) to `1` (original volume) and reject invalid values with `INVALID_CONFIGURATION`. Settings persist across stream replacement and reconnection on the same manager. Local volume does not affect uploaded audio or override automatic preview muting during generation. XLab's video input page exposes both sliders and a shared mute switch in its top bar.

## Switch cameras or change capture specifications

`switchCamera()` changes front/back position while preserving the local track and
its dimensions/frame rate. During generation, the SDK stops the current task,
switches cameras, waits 500 ms for capture to settle, then starts a new task with
the latest successful context. The connection and remote track are retained.
Do not switch while a connection or generation start is pending. Calling
`stopGeneration()` or `disconnect()` during the switch prevents automatic restart.

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
retained for `x2.0-sla` and reduced to `800 × 1536` for `x2.0`.

## Stop and release resources

```ts
// Pause generation while retaining the connection:
await realtime.stopGeneration();

// Or end the remote session while retaining local preview:
await realtime.disconnect();

// Or leave the screen and release all resources:
await realtime.close();
```

`stopGeneration()` terminates the active generation task while retaining the
remote connection and local preview. `disconnect()` closes the remote session
while preserving the local preview. `close()` releases all local media and RTC
resources and should be called when the realtime workflow is no longer required.

When applicable, these methods wait for affected operations and resource cleanup to finish.
For example, closing while a session request is pending waits for the late session
to be rolled back. Concurrent stop/disconnect/close requests share a cleanup task
and expand its scope as needed. Cleanup failures are logged while the remaining
resources continue to be released.

A fatal generation-start failure enters `ERROR` after generation cleanup, then
notifies the error listener. If the connection is still open, generation can be
retried on the same connection. Heartbeat failures clean up the connection before
reporting the error. Recoverable input errors leave the current lifecycle intact.

## Handle recoverable and fatal errors

`XmaxError.severity` distinguishes recoverable and fatal errors:

- `RECOVERABLE`: the operation did not complete, but the SDK can still be used.
  Invalid configuration, permission denial, cancellation, and failed generation
  condition/trajectory updates belong here. Handle a failed asynchronous call in
  its `catch`; it does not trigger `setErrorListener`.
- `FATAL`: the current realtime workflow cannot continue normally. Connection,
  generation-start, subscription and media failures are fatal by default, and
  session heartbeat failure is always fatal. The realtime error listener receives
  these failures so the host can recover or leave the workflow.

An awaited operation still rejects when it fails, including fatal failures already
sent to the listener. Avoid showing the same fatal error from both places:

```ts
import { XmaxError, XmaxErrorCode, XmaxErrorSeverity } from '@xmax/sdk';

try {
  const remoteStream = await realtime.startGeneration(localStream, generationContext);
  this.remoteVideoTrack = remoteStream.videoTrack;
} catch (error) {
  const sdkError = XmaxError.from(error);
  if (sdkError.code !== XmaxErrorCode.CANCELLED &&
    sdkError.severity === XmaxErrorSeverity.RECOVERABLE) {
    console.error(`Operation failed: ${sdkError.message}`);
  }
}
```

The listener is independent of logging. Passing `null` removes it. The same error
instance propagating through multiple SDK layers is logged and forwarded once.
Best-effort stop-signal and cleanup failures are logged without invoking the fatal
listener; shutdown continues. Cancellation is recoverable and only appears in SDK
logs when business logging is enabled.

The existing `XmaxError(code, message, apiCode?, httpStatus?)` constructor remains
compatible. An optional fifth `severity` argument overrides the default; API and
HTTP error details are preserved when the SDK changes an error's severity for a
specific operation.

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
| `PERFORMANCE` | Generation startup timing, RTC stream statistics, network quality, CPU/memory and performance alarms |
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

Generation task IDs use `task-harmonyos-` followed by the full 16 UUID bytes encoded
as 22 unpadded Base64URL characters. The room event's `uid` and video-frame SEI use
the same complete task ID; SEI contains its UTF-8 bytes. The encoding matches iOS,
with a HarmonyOS platform prefix.
