<h1 align="center">XmaxSDK for HarmonyOS</h1>

<p align="center">
  <a href="https://developer.huawei.com/consumer/en/"><img src="https://img.shields.io/badge/HarmonyOS-5.1.0%2B-F05138" alt="HarmonyOS 5.1.0+"></a>
  <a href="https://developer.huawei.com/consumer/en/arkts/"><img src="https://img.shields.io/badge/ArkTS-native-007AFF" alt="ArkTS native"></a>
  <a href="https://platform.xmaxai.com/"><img src="https://img.shields.io/badge/Realtime-AI-FF9500" alt="Realtime AI"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-4C9A2A" alt="MIT License"></a>
</p>

Native HarmonyOS SDK, providing access to the real-time interactive video generation
models from Xmax AI. It enables low-latency, high-fidelity video transformations
using live video streams, reference images, and user interactions.
With just a few lines of code, developers can integrate features such as
real-time character swap, virtual try-on, mixed-reality companions,
and interactive image animation directly into their apps.

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

- [`xmaxsdk-1.0.2.har`](https://github.com/XingMai/XmaxSDK-HarmonyOS/releases/download/1.0.2/xmaxsdk-1.0.2.har)
  from the XmaxSDK GitHub Release
- The VolcEngine RTC HAR from the
  [HarmonyOS integration guide](https://bytedance.larkoffice.com/docx/VCVzduvzioORCixDKzEcMt9Fnof?from=from_copylink)

Add both files to the application module's `libs` directory:

```text
entry/libs/xmaxsdk-1.0.2.har
entry/libs/VolcEngineRTCToB-Release.har
```

Declare XmaxSDK in the module-level `oh-package.json5`:

```json5
{
  "dependencies": {
    "@xmax/sdk": "file:./libs/xmaxsdk-1.0.2.har"
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

Connection-state and error listeners may be registered on the realtime manager:

```ts
realtime.setStateListener((state) => {
  this.connectionState = state.connectionState;
  console.info(
    `Xmax realtime state: ${state.connectionState}, session: ${state.sessionId}, task: ${state.taskId}`
  );
});

realtime.setErrorListener((error) => {
  console.error(`Xmax realtime error: ${error.code} ${error.message}`);
});
```

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

### Connect and render the streams

Connect the selected local input stream to the realtime session:

```ts
const remoteStream = await realtime.connect(localStream);
```

Store the local and remote video tracks in component state:

```ts
import {
  RealtimeConnectionState,
  RealtimeVideoTrack
} from '@xmax/sdk';

@State private localVideoTrack: RealtimeVideoTrack | null = null;
@State private remoteVideoTrack: RealtimeVideoTrack | null = null;
@State private connectionState: RealtimeConnectionState =
  RealtimeConnectionState.IDLE;

this.localVideoTrack = localStream.videoTrack ?? null;
this.remoteVideoTrack = remoteStream.videoTrack ?? null;
```

Render the input and generated output with `XmaxVideoView`:

```ts
import {
  VideoContentMode,
  XmaxVideoView
} from '@xmax/sdk';

build() {
  Stack() {
    if (this.localVideoTrack !== null) {
      XmaxVideoView({
        track: this.localVideoTrack,
        contentMode: VideoContentMode.FILL
      })
    }

    if (this.remoteVideoTrack !== null &&
      this.connectionState === RealtimeConnectionState.GENERATING) {
      XmaxVideoView({
        track: this.remoteVideoTrack,
        contentMode: VideoContentMode.FILL
      })
    }
  }
  .width('100%')
  .height('100%')
}
```

Use `VideoContentMode.FIT` to preserve the aspect ratio of image and local video
inputs.

### Start generation

Construct a `RealtimeContext` with a prompt and, when applicable, a remote reference
image URL:

```ts
import { RealtimeContext } from '@xmax/sdk';

await realtime.startGeneration(
  new RealtimeContext(
    '视频中角色替换成参考图中角色',
    referenceImageUrl
  )
);
```

To update an active generation task, submit a new context containing the revised
prompt or reference image:

```ts
await realtime.startGeneration(
  new RealtimeContext(
    '将人物服装替换成参考图中的服装',
    anotherReferenceImageUrl
  )
);
```

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

## Touch Interaction

During an active generation task, `XmaxVideoView` captures multi-touch trajectories
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
