# Development validation

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
