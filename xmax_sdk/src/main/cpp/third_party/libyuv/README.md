# libyuv

Source: https://chromium.googlesource.com/libyuv/libyuv/

Commit: `28ce69c2744a6aafdb58564e7b884aec3f66be5f`

The source files required by the frame conversion pipeline are built into the
SDK as a static library. SVE and SME are disabled; ARM64 builds use libyuv's
runtime-dispatched NEON implementation.
