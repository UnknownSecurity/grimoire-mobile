# Grimoire Exodus AIR client

This module is the default standalone Android game runtime. It compiles the checked-in
Grimoire ActionScript source with HARMAN AIR, downloads the current AQW client
from AQW's own version endpoint at runtime, and packages a captive-runtime APK.
It does not bundle or depend on another Android application.
The loading surface, launcher icon, and in-game command-center wrapper reuse
the Grimoire-owned dark/violet visual language from the Compose prototype.

The AIR bridge preserves the existing desktop `ExternalInterface` callbacks.
When no desktop host exists, the same callbacks are retained in a local
registry for the Android controller. Server-list responses fall back to the
original AQW response so login remains functional without a native filter.

## Prerequisites

- HARMAN AIR SDK 51.4, either in `AIR_HOME` or the ignored
  `.tools/AIRSDK_51.4.1.2` directory;
- Android SDK platform files, exposed through `ANDROID_SDK_ROOT`, `ANDROID_HOME`,
  or an `adb` installation on `PATH`;
- JDK 17 or 21;
- the AIR SDK license appropriate for the developer or organization.

The AIR SDK and signing material are development tools. They must not be
committed or placed in an APK or release archive.

## Build

From the repository root:

```powershell
.\mobile\air-client\build-air.ps1 -Configuration Debug
```

The development APK is written to `dist/` as
`Grimoire-Exodus-Android-AIR-0.5.0-arm64.apk`. It is signed with an ignored local
development certificate and must not be published as a release build.

For a release build, provide a protected keystore through
`GRIMOIRE_ANDROID_KEYSTORE` and `GRIMOIRE_ANDROID_KEYSTORE_PASSWORD`, then use
`-Configuration Release`. Never commit the keystore or its password.

## Runtime boundary

The packaged bootstrap performs these steps:

1. requests AQW's current version metadata over HTTPS;
2. downloads the selected AQW SWF into memory;
3. shows real byte progress in the AIR stage;
4. imports the SWF with `LoaderContext.allowCodeImport`;
5. initializes the Grimoire callback registry after AQW is ready.

After initialization, AQW remains a direct child of the AIR stage while the
top menu and sidebar are drawn in a separate overlay. AIR fits AQW's native
960×550 Stage plane with one uniform scale and centers any remaining letterbox
space instead of stretching the game. The wrapper never moves or rescales AQW
itself, so legacy Stage-based pointer reads stay aligned with the displayed
touch target. A local 960×550 scroll rectangle still contains world rendering
and hit targets. The compact drawer overlays the left edge only while it is
open. Ciel is a stable Grimoire HUD control in the top-right; it is hidden on
the login and server screens and appears only after AQW confirms the in-game
session. It is not injected into AQW's native action bar. Its supplied character
image and the description “Summon Ciel to automate and take over your body.”
identify the control. Tapping it opens the command overlay, whose dedicated
close button returns to the unobstructed client without changing the game
viewport.

The title block has been removed from the compact top bar. Bot, Bank, Options,
Packet, Tools, and the mobile-only Runner are available directly. Bank opens
AQW's live bank; Options cover the applicable desktop client behaviors; Packet
keeps a bounded capture history and can send controlled client/server packets;
and Tools exposes common player and client actions. Legacy packet and
packet-list GBot commands are also handled by the cooperative mobile runner.

The AIR Bot Manager lists packaged Community bots and bots imported through the
Android Storage Access Framework. A private native extension copies the chosen
document into a bounded app-cache file, after which the existing JSON and
command limits are applied before it reaches application-owned storage. The
picker intentionally accepts unknown MIME types so `.gbot` files remain visible
across Android file providers. A successful import is selected immediately.
The paged manager can create, edit, reorder, duplicate, delete, and save legacy
commands while preserving unknown fields and exact desktop `$type` identities.
Start, pause/resume, stop, refresh, and imported-bot removal are live. A
cooperative mobile runner supports a foundational subset of legacy timing,
join/movement, combat, skill, quest, inventory, label/index, stop/restart, and
common statement conditions. An unknown command stops the run with its type in
the visible status; this is not yet command-for-command parity with desktop.

The settings drawer persists General, Key Bindings, and Advanced preferences.
Mobile adaptations include start-in-focus, status visibility, back-button exit
confirmation, reduced motion, keep-awake, 30/60 FPS, render quality, hardware
F-key shortcuts, login-field clearing, app-owned settings reset, and an official
GitHub mobile-release check. Android has no desktop tray behavior, so it is not
presented as a mobile option.

Runner is off by default. When enabled, AIR background execution is paired with
an Android foreground service whose persistent notification shows only generic
idle/running/paused/stopped state. Optional stop notices also contain no player,
bot, map, room, or packet details. Balanced mode holds no CPU wake lock; the
explicit reliable mode holds a partial wake lock only while a bot is running.
The Runner page links to Android's per-app battery settings for users who need
to review device-specific restrictions.

The profile card remains anonymous until AQW confirms `loadInventoryBig`, then
reads the authenticated character name and any available level/class data from
the live game state. Typed credentials are never treated as an authenticated
profile. Mobile AIR targets 30 FPS at standard display density to reduce the
rendering and pixel-fill cost of the legacy vector scene; desktop frame and
display behavior are unchanged.

Because AIR imports the main AQW client from downloaded bytes, the bootstrap
restores AQW's official HTTPS game and asset origins before login. This keeps
the post-login `Assets_*.swf` request away from AIR's synthetic
`app:/[[DYNAMIC]]` URL and prevents the AQW “Client Initialization Failed” path.

AQW itself remains visually dominant. The mobile runner is intentionally
smaller than the mature desktop engine; subsequent milestones will add commands
only behind compatibility fixtures and live-client validation.

## Validation status

The debug APK has been exercised on an Android emulator: it retrieved live AQW
metadata, downloaded and initialized the current client, rendered the real login
surface, opened Android Files, displayed and imported a synthetic `.gbot`, and
opened that document in the command editor. The APK manifest and arm64 payload
have also been inspected. An authenticated device pass is still required to
verify live map/entity alignment, Ciel visibility, sockets, bot execution, and
long-session stability before release.
