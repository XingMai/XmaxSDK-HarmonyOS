<h1 align="center">XmaxSDK for HarmonyOS</h1>

<p align="center">
  <a href="https://developer.huawei.com/consumer/en/"><img src="https://img.shields.io/badge/HarmonyOS-5.1.0%2B-F05138" alt="HarmonyOS 5.1.0+"></a>
  <a href="https://developer.huawei.com/consumer/en/arkts/"><img src="https://img.shields.io/badge/ArkTS-native-007AFF" alt="ArkTS native"></a>
  <a href="https://platform.xmaxai.com/"><img src="https://img.shields.io/badge/Realtime-AI-FF9500" alt="Realtime AI"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-4C9A2A" alt="MIT License"></a>
</p>

Native HarmonyOS SDK, providing access to the real-time interactive video generation
models from Xmax AI. It supports low latency, high fidelity video transformations
driven by live video streams, reference images, and user interactions. With just a few
lines of code, developers can integrate features such as real-time character swap,
virtual try-on, mixed reality companions, and interactive image animation directly
into their apps.

<p align="center"><img src="./docs/images/xlab/generation-demo.gif" alt="X-Lab realtime generation demo" width="33%" /><img src="./docs/images/xlab/index-demo.gif" alt="X-Lab index demo" width="33%" /><img src="./docs/images/xlab/storage-demo.gif" alt="X-Lab storage demo" width="33%" /></p>

<br>

## Features

- Real-time video generation from live camera streams, still images, and local video
  files, guided by prompts, reference images, and user interactions
- In-application rendering of local media input and generated output
- Multi-touch trajectory input for controlling subject movement in generated video
  streams
- Image and video transfer through Xmax-managed object storage
- ArkTS language support with Promise-based asynchronous APIs

## Requirements

- HarmonyOS 5.1.0 (API 18) or later
- An Xmax API key from the [Xmax Platform](https://platform.xmaxai.com/api-keys)

> [!WARNING]
> Do not commit an Xmax API key to version control. Supply credentials securely at
> runtime, or use a temporary key issued by the Xmax API. See
> [Authentication](https://platform.xmaxai.com/docs/authentication) for details.

## Installation

The current release is distributed as a Harmony Archive (HAR). XmaxSDK depends on
the VolcEngine RTC SDK for HarmonyOS, which is not currently available through the
official OHPM Registry; both archives must therefore be integrated manually.

Download the following files:

- [`xmaxsdk-1.0.3.har`](https://github.com/XingMai/XmaxSDK-HarmonyOS/releases/download/1.0.3/xmaxsdk-1.0.3.har)
  from the XmaxSDK GitHub Release
- The VolcEngine RTC HAR from the
  [HarmonyOS integration guide](https://bytedance.larkoffice.com/docx/VCVzduvzioORCixDKzEcMt9Fnof?from=from_copylink)

Add both files to the application module's `libs` directory:

```text
entry/libs/xmaxsdk-1.0.3.har
entry/libs/VolcEngineRTCToB-Release.har
```

Declare XmaxSDK in the module-level `oh-package.json5`:

```json5
{
  "dependencies": {
    "@xmax/sdk": "file:./libs/xmaxsdk-1.0.3.har"
  }
}
```

Override the VolcEngine dependency in the project-level `oh-package.json5`:

```json5
{
  "modelVersion": "6.1.1",
  "dependencies": {},
  "devDependencies": {},
  "overrides": {
    "@bytertc/volcenginertc": "file:./entry/libs/VolcEngineRTCToB-Release.har"
  }
}
```

Install the dependencies:

```bash
ohpm install
```

## Permissions

For camera-based input, declare the following permissions in the application
module's `module.json5`:

```json5
{
  "module": {
    "requestPermissions": [
      {
        "name": "ohos.permission.INTERNET"
      },
      {
        "name": "ohos.permission.GET_NETWORK_INFO"
      },
      {
        "name": "ohos.permission.CAMERA",
        "reason": "$string:reason_camera",
        "usedScene": {
          "abilities": [
            "EntryAbility"
          ],
          "when": "inuse"
        }
      }
    ]
  }
}
```

Replace `EntryAbility` with the UIAbility that uses XmaxSDK when the application
uses a different ability name. Define the permission reason in
`resources/base/element/string.json`:

```json
{
  "string": [
    {
      "name": "reason_camera",
      "value": "Camera access is required for realtime video input."
    }
  ]
}
```

If an input source contains audio, also declare `ohos.permission.MICROPHONE` with
an appropriate permission reason and `usedScene` configuration. XmaxSDK checks and
requests the required runtime permissions when a local media stream is created. If
permission is unavailable, the SDK reports an `XmaxError`.

Before deploying to a device, configure application signing in DevEco Studio under
**File > Project Structure > Signing Configs**.

## Getting Started

### Create a client

Within an ArkUI component, obtain the `UIAbilityContext` required by the SDK and
create a realtime manager:

```ts
import { common } from '@kit.AbilityKit';
import {
  RealtimeConfiguration,
  RealtimeModel,
  RealtimeModels,
  XmaxClient,
  XmaxConfiguration
} from '@xmax/sdk';

const context = this.getUIContext().getHostContext() as common.UIAbilityContext;

const client = new XmaxClient(
  new XmaxConfiguration('YOUR_API_KEY'),
  context
);

const realtime = client.createRealtimeManager(
  new RealtimeConfiguration(
    RealtimeModels.realtime(RealtimeModel.X2_0)
  )
);
```

Realtime operations return promises and should be invoked from a lifecycle-aware
component owned by the host application.

Connection-state and fatal-error listeners may be registered on the realtime manager:

```ts
realtime.setStateListener((state) => {
  this.connectionState = state.connectionState;
  console.info(
    `Xmax realtime state: ${state.connectionState}, session: ${state.sessionId}, task: ${state.taskId}`
  );
});

realtime.setErrorListener((error) => {
  // Only FATAL errors reach this listener, even when SDK logging is disabled.
  console.error(`Xmax realtime error: ${error.code} ${error.severity} ${error.message}`);
});
```

### Configure SDK logging

SDK logging is **off by default**, in both debug and release builds. Set
`loggerOptions` when creating a client to opt in:

```ts
import { XmaxClient, XmaxConfiguration, XmaxLoggerOption } from '@xmax/sdk';

const client = new XmaxClient(
  new XmaxConfiguration(
    'YOUR_API_KEY',
    XmaxLoggerOption.BUSINESS | XmaxLoggerOption.PERFORMANCE
  ),
  context
);
```

| Option | Output |
| --- | --- |
| `NONE` | No SDK logs (default) |
| `BUSINESS` | API, Room, Realtime, Storage and other operation logs, including errors |
| `PERFORMANCE` | RTC stream statistics, network quality, CPU/memory and performance alarms |
| `ALL` | Both business and performance logs |

As on iOS, this is an SDK-global setting: the most recently created client's
configuration replaces the previous setting, including `NONE`. Use consistent
options across clients. The XLab example explicitly enables `ALL` for diagnostics.
The switch controls XmaxSDK's HiLog output; host-application logging and the
third-party RTC SDK's own logs have separate controls. Network-quality and
performance-alarm listeners continue to work when their logs are disabled.

### Handle recoverable and fatal errors

`XmaxError.severity` follows the iOS error model:

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

### Runtime information and task IDs

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
with a HarmonyOS platform prefix. The `x2.0-sla` model and its input-size rules remain
unchanged.

### Create an input stream

Create a live camera stream after declaring the required permissions:

```ts
import {
  CameraPosition,
  RealtimeVideoFormat
} from '@xmax/sdk';

const localStream = await realtime.createLocalCameraStream(
  new RealtimeVideoFormat(832, 1472, 24),
  CameraPosition.FRONT
);
```

Still images and local video files can also be used as input sources:

```ts
const imageStream = await realtime.createLocalImageStream(imageFilePath);
const videoStream = await realtime.createLocalVideoStream(videoFilePath);
```

Only one local input stream may be active at a time.

### Adjust playback volume

Control local video preview and generated audio separately, including before creating a stream or connecting:

```ts
await realtime.setLocalAudioVolume(0.45); // Local video preview; default 45%.
await realtime.setRemoteAudioVolume(1);   // Generated audio; default 100%.
```

Both methods accept finite values from `0` (mute) to `1` (original volume) and reject invalid values with `INVALID_CONFIGURATION`. Settings persist across stream replacement and reconnection on the same manager. Local volume does not affect uploaded audio or override automatic preview muting during generation. XLab's video input page exposes both sliders and a shared mute switch in its top bar.

### Render local preview and generated video

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

### Start generation in one call

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

As on iOS, the SDK matches the task's SEI, waits for a usable remote video frame,
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

### Switch cameras or change capture specifications

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

The old local stream is no longer valid after stopping it. HarmonyOS retains its
`x2.0-sla` support and existing model input sizing: 32-pixel alignment with the
600,000–2,100,000 pixel scaling thresholds. These rules are independent of the
iOS lifecycle alignment above; use the returned track's `videoFormat` to inspect
the resolved dimensions.

### Stop and release resources

```ts
await realtime.stopGeneration();
await realtime.disconnect();
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

## Touch Interaction

During an active generation task, the remote view in `XmaxRealtimeVideoView` (or
a standalone `XmaxVideoView`) captures multi-touch trajectories
over the generated video and submits them to the active task. The host application
does not need to implement gesture tracking or coordinate conversion.

Trajectory interaction is enabled by default. Disable it when touch input must be
handled by the surrounding user interface:

```ts
XmaxVideoView({
  track: this.remoteVideoTrack,
  contentMode: VideoContentMode.FILL,
  isInteractionEnabled: false
})
```

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

## Example Project

A runnable ArkUI reference application is available in
[`examples/XLab`](https://github.com/XingMai/XmaxSDK-HarmonyOS/tree/main/examples/XLab).
The application demonstrates realtime generation with camera, image, and local
video inputs, together with custom prompts, reference image selection, and
trajectory rendering.

<p align="center"><img src="./docs/images/xlab/home.jpg" alt="X-Lab home" width="20%" /><img src="./docs/images/xlab/features.jpg" alt="X-Lab SDK features" width="20%" /><img src="./docs/images/xlab/storage.jpg" alt="X-Lab storage service" width="20%" /><img src="./docs/images/xlab/realtime-generation.jpg" alt="X-Lab realtime generation" width="20%" /><img src="./docs/images/xlab/trajectory-generation.jpg" alt="X-Lab trajectory generation" width="20%" /></p>

## Dependencies

- VolcEngine RTC SDK for HarmonyOS provides real-time audio and video communication.
- Tencent Cloud COS SDK provides image and video transfer through object storage.

## Feedback

For bug reports and feature requests, use
[GitHub Issues](https://github.com/XingMai/XmaxSDK-HarmonyOS/issues). For integration
questions and technical support, contact [sdk@xmax.ai](mailto:sdk@xmax.ai).

## License

XmaxSDK is available under the terms of the [MIT License](LICENSE).

## Development validation

Run the source-level lifecycle, rendering-state, error/logging, and runtime/SEI
regression tests on Node 18+:

```bash
node --test tests/*.test.cjs
```

The tests use the TypeScript compiler bundled with DevEco Studio on macOS. Set
`TYPESCRIPT_PATH` to another compatible TypeScript installation when needed. They
execute SDK lifecycle methods with platform doubles; they do not emulate ArkUI or
native RTC rendering. Build both `xmax_sdk` (`assembleHar`) and the XLab `entry`
module (`assembleHap`) with Hvigor after changing ArkUI components.

On an API 18+ device, verify local preview, remote first-frame fade-in, clearing
and reassigning remote tracks, repeated camera switches, and resolution/frame-rate
recreation. Include camera, image and video-file inputs; cancel during connection
and camera switching to confirm local preview remains usable.
