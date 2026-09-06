<h1 align="center">XmaxSDK for HarmonyOS</h1>

<p align="center">
  <a href="https://developer.huawei.com/consumer/en/"><img src="https://img.shields.io/badge/HarmonyOS-5.1.0%2B-F05138" alt="HarmonyOS 5.1.0+"></a>
  <a href="https://developer.huawei.com/consumer/en/arkts/"><img src="https://img.shields.io/badge/ArkTS-native-007AFF" alt="ArkTS native"></a>
  <a href="https://platform.xmaxai.com/"><img src="https://img.shields.io/badge/Realtime-AI-FF9500" alt="Realtime AI"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-4C9A2A" alt="MIT License"></a>
</p>

XmaxSDK is a native HarmonyOS SDK that provides access to Xmax's real-time,
interactive video generation models. It enables low-latency, cost-efficiency,
and high-fidelity video transformations, conditioned on reference images, text
prompts, and user interactions. With concise ArkTS APIs, developers can integrate
features such as real-time character swapping, virtual try-on, or AI companions
into HarmonyOS applications.

<p align="center"><img src="./docs/images/xlab/generation-demo.gif" alt="X-Lab realtime generation demo" width="33%" /><img src="./docs/images/xlab/index-demo.gif" alt="X-Lab index demo" width="33%" /><img src="./docs/images/xlab/storage-demo.gif" alt="X-Lab storage demo" width="33%" /></p>

<br>

## What XmaxSDK does

XmaxSDK gives an end-to-end pipeline covering media capture, low-latency video
communication, frame-by-frame generation, and in-app rendering. Whether
processing live camera feeds, pre-recorded video, or still images, the SDK streams
input to our cloud AI engine and renders the result. Developers can manage the
workflow through Promise-based ArkTS APIs, with built-in touch interaction and
media upload and download.

<br>

## What you can build with XmaxSDK

| Realtime Use Case | Description |
| --- | --- |
| **Character Swapping** | Replace anyone in your live feed with a designated avatar in real time. |
| **Virtual Try-On** | Change outfits using a reference image of the target clothing. |
| **Video Restyling** | Transform your video using a reference image of the desired artistic style. |
| **AI Companions** | Bring virtual characters into your live camera feed and interact through gestures. |
| **Live Photo** | Animate characters in images by drawing motion trajectories. |

<br>

## Prerequisites
- HarmonyOS 5.1.0 (API 18) or later
- An Xmax API key from the [Xmax Platform](https://platform.xmaxai.com/api-keys)

> [!WARNING]
> Do not commit an Xmax API key to version control. Supply credentials securely at
> runtime, or use a temporary key issued by the Xmax API. See
> [Authentication](https://platform.xmaxai.com/docs/authentication) for details.

<br>

## Installation

XmaxSDK currently supports manual integration with Harmony Archive (HAR) files.
Download
[`xmaxsdk-1.0.3.har`](https://github.com/XingMai/XmaxSDK-HarmonyOS/releases/download/1.0.3/xmaxsdk-1.0.3.har),
then follow the [manual integration guide](./docs/installation.md#manual-integration)
to add XmaxSDK and the required VolcEngine RTC dependency to your application.

<br>

## Quick Start

### Configure permissions
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

<br>

### Generate and display video

The following ArkTS snippets create a camera stream, start real-time generation,
and bind the output to an ArkUI video component.

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

Create the input stream and start generation from an async method in that component:

```ts
import { RealtimeContext } from '@xmax/sdk';

const localStream = await realtime.createLocalCameraStream();
this.localVideoTrack = localStream.videoTrack;

const remoteStream = await realtime.startGeneration(
  localStream,
  new RealtimeContext(
    '视频中角色替换成参考图中角色',
    'https://platform.xmaxai.com/images/source/charx/chatx_image1.jpg'
  )
);
this.remoteVideoTrack = remoteStream.videoTrack;
```

The camera uses the selected model's default format. Store the tracks in component
state and add `XmaxRealtimeVideoView` to your view hierarchy:

```ts
import {
  RealtimeVideoTrack,
  VideoContentMode,
  XmaxRealtimeVideoView
} from '@xmax/sdk';

@State private localVideoTrack: RealtimeVideoTrack | undefined = undefined;
@State private remoteVideoTrack: RealtimeVideoTrack | undefined = undefined;

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

The component displays a local camera preview until the generated video is ready
to render, with touch interaction enabled by default.

<br>

### Listen for events

After creating `realtime`, register the listeners you need before creating the
input stream or starting generation.

| Listener | Purpose |
| --- | --- |
| `setStateListener` | Observe pipeline states during real-time generation. |
| `setErrorListener` | Handle fatal errors that prevent the realtime workflow from continuing. |
| `setCameraPreviewReadyListener` | Notify when the initial local camera frame is ready for preview rendering. |
| `setNetworkQualityListener` | Monitor uplink and downlink network quality. |
| `setPerformanceAlarmListener` | Detect device performance limitations or recovery, with a suggested video format when available. |

For example, monitor state changes and errors:

```ts
realtime.setStateListener((state) => {
  console.info(`State: ${state.connectionState}`);
});

realtime.setErrorListener((error) => {
  console.error(`Error: ${error.code} ${error.message}`);
});
```

<br>

### Resource Cleanup

- **`disconnect()` — Stop Remote Generation**

  Ends the remote session while keeping the local camera stream and preview
  active. Use this when ending the online session but staying on the current
  screen. You can start a new session later using the same local stream:

  ```ts
  await realtime.disconnect();
  this.remoteVideoTrack = undefined;
  ```

- **`close()` — Full Teardown & Release**

  Ends the remote session, stops local media capture, and releases all engine
  resources. Use this when leaving or dismissing the generation screen:

  ```ts
  await realtime.close();
  ```

> **Note:** These methods are alternatives, not sequential steps. When exiting a
> screen, call `close()` directly—there is no need to call `disconnect()` first.

<br>

> [!TIP]
> For complete usage examples, including image and video inputs, model capabilities,
> reference images, touch interaction, and logging, see the [usage guide](./docs/usage.md).

<br>

## Example Project
A runnable ArkUI reference application is available in
[`examples/XLab`](https://github.com/XingMai/XmaxSDK-HarmonyOS/tree/main/examples/XLab).
The application demonstrates realtime generation with camera, image, and local
video inputs, together with custom prompts, reference image selection, and
trajectory rendering.

<p align="center"><img src="./docs/images/xlab/home.jpg" alt="X-Lab home" width="20%" /><img src="./docs/images/xlab/features.jpg" alt="X-Lab SDK features" width="20%" /><img src="./docs/images/xlab/storage.jpg" alt="X-Lab storage service" width="20%" /><img src="./docs/images/xlab/realtime-generation.jpg" alt="X-Lab realtime generation" width="20%" /><img src="./docs/images/xlab/trajectory-generation.jpg" alt="X-Lab trajectory generation" width="20%" /></p>

For local builds and regression checks, see [Development validation](./docs/development.md).

<br>

## Dependencies

- <ins><strong>VolcEngine RTC SDK for HarmonyOS</strong></ins> enables low-latency, real-time audio and video communication.
- <ins><strong>Tencent Cloud COS SDK</strong></ins> handles media upload and download via object storage.

<br>

## Contact us

For bug reports and feature requests, please open a
[GitHub Issue](https://github.com/XingMai/XmaxSDK-HarmonyOS/issues). For integration
assistance and technical support, contact us at [sdk@xmax.ai](mailto:sdk@xmax.ai).

<br>

## License

XmaxSDK is available under the terms of the [MIT License](LICENSE).
