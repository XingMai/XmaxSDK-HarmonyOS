# Installation guide

## Manual integration

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

See [Configure permissions](../README.md#configure-permissions) before creating
a local media stream.
