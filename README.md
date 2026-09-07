<p align="center">
  <img src="./docs/images/brand/xmax-sdk.png" alt="XmaxSDK — Realtime Interactive Video Generation" width="880">
</p>

<p align="center">
  <a href="https://developer.huawei.com/consumer/en/"><img src="https://img.shields.io/badge/HarmonyOS-5.1.0%2B-F05138" alt="HarmonyOS 5.1.0+"></a>
  <a href="https://developer.huawei.com/consumer/en/arkts/"><img src="https://img.shields.io/badge/ArkTS-native-007AFF" alt="ArkTS native"></a>
  <a href="https://platform.xmaxai.com/"><img src="https://img.shields.io/badge/Realtime-AI-FF9500" alt="Realtime AI"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-4C9A2A" alt="MIT License"></a>
</p>

Native HarmonyOS SDK, providing access to Xmax's real-time, interactive video generation models. The models are optimized for low latency and cost efficiency, enabling instantaneous video transformations across diverse characters, outfits, and aesthetic styles. Also, they can dynamically respond to user gestures, allowing interactive virtual subjects to blend into real-world footage for immersive experiences. XmaxSDK implements an end-to-end pipeline to leverage these novel capabilities through concise ArkTS APIs, making it easy for developers to build next-generation interactive video experiences within the HarmonyOS ecosystem.

<p align="center"><img src="./docs/images/xlab/generation-demo.gif" alt="X-Lab realtime generation demo" width="33%" /><img src="./docs/images/xlab/index-demo.gif" alt="X-Lab index demo" width="33%" /><img src="./docs/images/xlab/storage-demo.gif" alt="X-Lab storage demo" width="33%" /></p>

<br>

## What XmaxSDK does

XmaxSDK offers a complete workflow that covers media acquisition, low-latency video communication, frame-by-frame generation, and in-app rendering. Whether processing live camera feeds, pre-recorded video, or still images, it streams media to our cloud inference service, applies on-device enhancement to the returned video, and renders the result to screen. With the entire workflow abstracted into simple API calls, integrating real-time video generation is seamless and intuitive.

<br>

## What you can build with XmaxSDK

<table>
  <tr>
    <th width="24%" align="left">Realtime Use Case</th>
    <th width="60%" align="left">Description</th>
    <th width="16%" align="center">Demo</th>
  </tr>
  <tr>
    <td rowspan="2" width="24%" valign="middle">
      <strong>Character Swapping</strong>
    </td>
    <td width="60%" valign="middle">
      Replace anyone in your live feed with a designated avatar in real-time.
    </td>
    <td rowspan="2" width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/XingMai/XmaxSDK-iOS@88182780abe60b3df1c44f549487fcf8ab4b660c/docs/videos/use-cases/character-swapping.mp4">
        <img src="./docs/images/use-cases/character-swapping-poster.png" alt="Play the Character Swapping demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td width="60%" valign="middle">
      <strong>Prompt:</strong> <code>视频中角色替换成参考图中角色</code>
      <br><br>
      <strong>Reference image:</strong> Select a clear image of the desired character with a clean background.
    </td>
  </tr>
  <tr>
    <td rowspan="2" width="24%" valign="middle">
      <strong>Virtual Try-On</strong>
    </td>
    <td width="60%" valign="middle">
      Seamlessly change outfits, preserving exact body shape, natural motion, and an
      authentic fit.
    </td>
    <td rowspan="2" width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/XingMai/XmaxSDK-iOS@88182780abe60b3df1c44f549487fcf8ab4b660c/docs/videos/use-cases/virtual-try-on.mp4">
        <img src="./docs/images/use-cases/virtual-try-on-poster.png" alt="Play the Virtual Try-On demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td width="60%" valign="middle">
      <strong>Prompt:</strong> <code>视频中人物衣服替换成参考图中衣服</code>
      <br><br>
      <strong>Reference image:</strong> Select a clear image of the target outfit with a clean background.
    </td>
  </tr>
  <tr>
    <td rowspan="2" width="24%" valign="middle">
      <strong>Video Restyling</strong>
    </td>
    <td width="60%" valign="middle">
      Reimagine your world in any style with an immersive visual experience.
    </td>
    <td rowspan="2" width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/XingMai/XmaxSDK-iOS@88182780abe60b3df1c44f549487fcf8ab4b660c/docs/videos/use-cases/video-restyling.mp4">
        <img src="./docs/images/use-cases/video-restyling-poster.png" alt="Play the Video Restyling demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td width="60%" valign="middle">
      <strong>Prompt:</strong> <code>视频风格变为参考图指定的风格</code>
      <br><br>
      <strong>Reference image:</strong> Select an image that captures the artistic style you want to apply.
    </td>
  </tr>
  <tr>
    <td rowspan="2" width="24%" valign="middle">
      <strong>AI Companions</strong>
    </td>
    <td width="60%" valign="middle">
      Summon virtual characters into your live camera feed and interact with them
      through gestures.
    </td>
    <td rowspan="2" width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/XingMai/XmaxSDK-iOS@88182780abe60b3df1c44f549487fcf8ab4b660c/docs/videos/use-cases/ai-companions.mp4">
        <img src="./docs/images/use-cases/ai-companions-poster.png" alt="Play the AI Companions demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td width="60%" valign="middle">
      <strong>Prompt:</strong> <code>指定角色在场景中互动</code>
      <br><br>
      <strong>Reference image:</strong> Select a clear image of the virtual character you want to summon with a clean background.
    </td>
  </tr>
  <tr>
    <td rowspan="2" width="24%" valign="middle">
      <strong>Live Photo</strong>
    </td>
    <td width="60%" valign="middle">
      Animate and control characters in your images simply by drawing motion
      trajectories.
    </td>
    <td rowspan="2" width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/XingMai/XmaxSDK-iOS@4351aa869d4e24fd40690c670d8949bff270dee0/docs/videos/use-cases/live-photo.mp4">
        <img src="./docs/images/use-cases/live-photo-poster.png" alt="Play the Live Photo demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td width="60%" valign="middle">
      <strong>Prompt:</strong> <code>让画面自然动起来</code>
      <br><br>
      <strong>Reference image:</strong> Use the input image as the reference
    </td>
  </tr>
</table>

<br>

## Why XmaxSDK?

<table>
  <thead>
    <tr>
      <th height="104" align="center" valign="middle">
        <img src="./docs/images/why/low-latency.svg" alt="Low latency" width="36" height="36"><br>Low latency
      </th>
      <th height="104" align="center" valign="middle">
        <img src="./docs/images/why/low-cost.svg" alt="Cost efficiency" width="36" height="36"><br>Cost efficiency
      </th>
      <th height="104" align="center" valign="middle">
        <img src="./docs/images/why/high-fidelity.svg" alt="High fidelity" width="36" height="36"><br>High fidelity
      </th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>End-to-end latency is measured in <img src="./docs/images/why/latency-highlight.svg" alt="hundreds of milliseconds" width="192" height="20" align="absmiddle">, ensuring that updates to generation conditions and interaction controls are reflected instantly.</td>
      <td>Run on a <img src="./docs/images/why/gpu-highlight.svg" alt="single RTX 5090" width="126" height="20" align="absmiddle">, reducing inference costs by orders of magnitude versus datacenter GPUs like H100.</td>
      <td>Our models support real-time generation at up to <img src="./docs/images/why/resolution-highlight.svg" alt="1080p" width="48" height="20" align="absmiddle">, delivering production-ready, high-quality video output.</td>
    </tr>
  </tbody>
</table>

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

The current release is distributed as a Harmony Archive (HAR). XmaxSDK depends on
the VolcEngine RTC SDK for HarmonyOS, which is not currently available through the
official OHPM Registry; both archives must therefore be integrated manually.

Download the following files:

- [`xmaxsdk-1.0.4.har`](https://github.com/XingMai/XmaxSDK-HarmonyOS/releases/download/1.0.4/xmaxsdk-1.0.4.har)
  from the XmaxSDK GitHub Release
- The VolcEngine RTC HAR from the
  [HarmonyOS integration guide](https://bytedance.larkoffice.com/docx/VCVzduvzioORCixDKzEcMt9Fnof?from=from_copylink)

Add both files to the application module's `libs` directory:

```text
entry/libs/xmaxsdk-1.0.4.har
entry/libs/VolcEngineRTCToB-Release.har
```

Declare XmaxSDK in the module-level `oh-package.json5`:

```json5
{
  "dependencies": {
    "@xmax/sdk": "file:./libs/xmaxsdk-1.0.4.har"
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

See [Configure permissions](#configure-permissions) before creating
a local media stream.

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

A complete example application featuring an ArkUI implementation
is available in [`examples/XLab`](https://github.com/XingMai/XmaxSDK-HarmonyOS/tree/main/examples/XLab).
It demonstrates real-time generation using live camera feeds, static images, and
local video files.

<p align="center"><img src="./docs/images/xlab/home.jpg" alt="X-Lab home" width="20%" /><img src="./docs/images/xlab/features.jpg" alt="X-Lab SDK features" width="20%" /><img src="./docs/images/xlab/storage.jpg" alt="X-Lab storage service" width="20%" /><img src="./docs/images/xlab/realtime-generation.jpg" alt="X-Lab realtime generation" width="20%" /><img src="./docs/images/xlab/trajectory-generation.jpg" alt="X-Lab trajectory generation" width="20%" /></p>

<br>

## Dependencies

- <ins><strong>VolcEngine RTC SDK</strong></ins> enables low-latency, real-time audio and video communication.
- <ins><strong>Tencent Cloud COS SDK</strong></ins> handles media upload and download via object storage.

<br>

## Contact us

For bug reports and feature requests, please open a
[GitHub Issue](https://github.com/XingMai/XmaxSDK-HarmonyOS/issues). For integration
assistance and technical support, contact us at [sdk@xmax.ai](mailto:sdk@xmax.ai).

<br>

## License

XmaxSDK is available under the terms of the [MIT License](LICENSE).
