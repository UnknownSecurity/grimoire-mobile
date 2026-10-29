# Grimoire Exodus Mobile

This directory contains the additive Android port. The existing Windows client,
updater, installer, ActionScript bridge, and release paths remain in their
current locations and do not depend on this Gradle build.

## Current milestone (0.5.0)

Mobile versions are independent from Grimoire Exodus Desktop. The root
`VERSION` file is the source of truth for the AIR package and release artifact;
Compose/Ruffle keeps its own Android version code and matching mobile version
name. Mobile APKs are never included in the desktop release payload.

The Android work now has two additive surfaces:

- a HARMAN AIR captive-runtime client under `air-client/` that is the default
  playable Android app and loads AQW directly from AQW's live version endpoint;
- a Kotlin and Jetpack Compose/Ruffle client retained as an explicitly selected
  experimental build, not the default playable app;
- an AIR-native Grimoire command-center wrapper with the requested top menu,
  compact overlay drawer, authenticated character status, and dark violet game
  frame;
- a login-aware **Ciel** control in the top-right, separate from AQW's native
  action bar, that appears only after the game session is ready and opens the
  wrapper without becoming a combat skill or translating or scaling AQW;
- a clipped 960×550 AQW stage with uniform, aspect-preserving display scaling,
  so rendered targets and Android X/Y input share the same logical coordinates;
- an immersive, landscape-only dark-purple command center that hides Android's
  status and navigation bars during play;
- Grimoire-owned launcher, emblem, and banner artwork;
- a typed `GameTransport` boundary used by the experimental Ruffle prototype
  and an inert offline implementation retained for unit tests;
- an experimental loopback-only Ruffle origin, official AQW HTTPS asset proxy,
  validated server-map rewrite, and bounded WebSocket-to-TCP SmartFox tunnel;
- live Bank, desktop-compatible Options, bounded Packet, and expanded Tools
  surfaces routed through the checked-in ActionScript callback allowlist;
- an AIR-native Bot Manager that keeps the dark violet Compose-style layout and
  passes only validated legacy JSON into the bounded ActionScript runner;
- a versioned, fail-closed game-bridge handshake validator;
- Android document-picker import backed by a defensive, bounded, data-only
  legacy `.gbot` reader, plus repository-controlled Community bots;
- a compact, paged mobile Bot Manager with select/import/refresh/delete,
  start/pause/stop, and a cooperative fail-closed runner for foundational map,
  combat, quest, item, timing, and flow-control commands;
- persistent General, hardware Key Bindings, and Advanced settings adapted from
  the desktop global settings surface;
- shared, anonymized compatibility fixtures and versioned bridge contracts.

The AIR client is the standalone default runtime; it does not launch, wrap, patch,
or control another installed AQW Android application. It downloads the current
AQW SWF at runtime instead of bundling an AQW binary. On either mobile runtime,
an unsupported GBot command stops the run at that command rather than being
guessed, dynamically resolved, or skipped into an invalid state.

## Runtime decision

HARMAN AIR is the default Android runtime. It owns AQW's native AVM2 display,
preserves the live client rendering path, and draws the dark violet Grimoire
overlay and operational Bot Manager above the game without transforming AQW.
The Compose/Ruffle application remains available only through an explicit
experimental build for continued compatibility research. Both runtimes use the
checked-in ActionScript bridge; neither launches, repackages, or controls
another AQW Android application.

## Modules

| Module | Responsibility |
| --- | --- |
| `air-client` | Default standalone HARMAN AIR client, overlay, Bot Manager, and APK build |
| `app` | Experimental Android Ruffle client, loopback host, and Compose shell |
| `core:designsystem` | Grimoire-owned colors, type, shapes, and reusable surfaces |
| `core:model` | Platform-neutral mobile state and bridge model |
| `core:domain` | Transport boundary and safe offline implementation |
| `core:legacy-gbot` | Bounded, non-reflective legacy `.gbot` inspection |

Language-neutral contracts and fixtures live in `../shared` so Windows tests,
Android tests, documentation, and future tooling can consume the same source of
truth without either app importing the other's platform code.

## Build

From this directory:

```powershell
.\build-android.ps1
.\build-android.ps1 -Engine Ruffle
.\build-ruffle-runtime.ps1
```

`build-android.ps1` defaults to HARMAN AIR and writes the arm64 APK to `dist/`.
Pass `-Configuration Release` only with the protected Android signing variables
documented in `air-client/README.md`. Pass `-Engine Ruffle` to build the
separately identified experimental Compose/Ruffle APK.

`build-ruffle-runtime.ps1` is an occasional maintainer build, not part of every
APK build. It extracts the exact Ruffle 0.7.1 commit into the ignored build
area, applies the tracked Android-only Canvas offscreen and bitmap-cache patch, installs
the matching wasm-bindgen CLI, verifies the Binaryen v129 archive by SHA-256,
optimizes the WASM payload, and writes the resulting hashes to
`ruffle/runtime-manifest.json`. The checked-in Android runtime therefore does
not inherit unreviewed changes from a developer's Ruffle checkout.

The default build compiles the AIR-only wrapper and bounded GBot runner and
emits a filename containing `Android-AIR`. Seeing the HARMAN splash therefore
identifies the intended default engine. The opt-in Ruffle filename includes
`Ruffle-Experimental` and uses a separate Android application ID. Neither build
replaces the desktop SWF. The Android build uses its own wrapper and caches. It
never invokes `../exodus.ps1`, edits the desktop output, or launches either
application.

The Ruffle bridge is compiled with AVM2 float bytecode disabled and SWF version
43 so the pinned Android Ruffle runtime can verify it consistently. The host
uses the custom Canvas build because the upstream v0.7.1 WebGL backend does not
complete the offscreen `BitmapData.draw` path used by AQW avatars. The player is
explicitly sized to the live WebView viewport while AQW stays on its original
960×550 logical coordinate plane. This patch is mobile-only; the desktop Ruffle
payload remains independent.

To keep that compatibility path usable on high-density phones, the mobile
runtime caps its backing canvas at 1.25× while leaving the CSS viewport and
input mapping unchanged. Session status is also collected through one atomic
JavaScript snapshot per poll instead of four Android/WebView round trips. The
release build enables shrinking, optimization, and hardware acceleration;
WebView debugging is available only in debug builds.

The application ID is provisional until signing and distribution ownership are
approved. Do not publish development builds as an official release.

## Emulator validation

The 0.5.0 experimental Ruffle debug line has been exercised on an Android 16 Google APIs
x86_64 emulator. The official AQW client reaches authenticated server selection,
and bridge diagnostics report a connected socket, the `Game` timeline, and a
loaded local avatar. The upstream WebGL offscreen path corrupted AQW avatar
composition, so the current runtime uses the tracked Canvas patch. The packaged
client now passes a credential-free emulator reload that exercises AQW's
bitmap-cache path, rejects the prior renderer panic, reaches the ActionScript
bridge, and renders the real login surface. A fresh authenticated pass must
still verify avatar/player rendering, Ciel visibility, and live bot execution
before an Android release is considered ready.

The Bot Manager compatibility checks use only repository-controlled synthetic
fixtures; private account files and external bot folders are not part of the
Android build or validation corpus.
