# Mobile Ruffle runtime

The Android application ships a custom, mobile-only self-hosted Ruffle runtime.
It is based on upstream Ruffle 0.7.1 at commit
`89a7049965f3090e706265670df309a5128233ac` and remains licensed under Ruffle's
MIT or Apache-2.0 terms. The corresponding license files are packaged with the
runtime.

AQW composes character art through `BitmapData.draw` and uses display-object
bitmap caches during normal frame rendering. Ruffle 0.7.1's Canvas backend did
not implement either the required offscreen render/synchronization path or
bitmap-cache submission, while the experimental upstream WebGL implementation
still produced incomplete geometry on the Android WebView. The patch in
`patches/` implements both Canvas paths with isolated render state. Unsupported
post-filters degrade to the unfiltered cached image instead of crashing the
client. Android explicitly requests Canvas; the desktop runtime is not modified
by this patch.

The same mobile-only patch caps the Ruffle backing canvas at a 1.25 device-pixel
ratio while preserving its CSS size, AQW's 960x550 logical coordinate plane,
and the matching pointer scale. High-density phones otherwise multiply Canvas
pixel work by more than six times without exposing additional game detail. The
cap does not affect the desktop runtime or the ActionScript bridge contract.

`../build-ruffle-runtime.ps1` performs the maintainer build. It:

1. extracts the exact upstream commit from a local cache or the official Ruffle
   repository;
2. applies and verifies the tracked Canvas patch;
3. installs the matching wasm-bindgen CLI in the ignored build directory;
4. downloads the official Binaryen v129 Windows archive and verifies its
   SHA-256 before extraction;
5. builds and optimizes the self-hosted runtime; and
6. replaces stale Android runtime modules and rewrites
   `runtime-manifest.json` with file sizes and hashes.

`../../tests/Test-MobileRufflePerformance.ps1` is an emulator-only regression
that measures the packaged canvas scale and animation-loop responsiveness. It
must run together with the bitmap-cache/bridge emulator regression after a
runtime rebuild.

Do not hand-copy experimental modules into `app/src/main/assets/ruffle`. After a
runtime rebuild, run `tests/Test-MobileRuffle.ps1`,
`tests/Test-MobileRuffleEmulator.ps1`, and the Android Gradle test, assembly,
and lint tasks. The emulator regression reloads the real packaged client, fails
on the Canvas bitmap-cache panic, and requires a responsive ActionScript bridge.
Authenticated AQW rendering and Bot Manager behavior remain separate
device/emulator validation gates.
