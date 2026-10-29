# Grimoire Exodus Mobile agent guide

## Scope

These instructions apply to the entire standalone mobile repository. The
default playable application is the HARMAN AIR captive-runtime client under
`mobile/air-client/`. `mobile/app/` is a separate Kotlin/Compose Ruffle research
build and must never silently replace the default engine.

Keep changes mobile-only. This repository must not depend on a sibling desktop
checkout, desktop build output, WinForms, ActiveX, the desktop updater, or a
developer-specific path.

## Privacy

- Never commit or report credentials, private bot files, account names, logs,
  packet bodies, room names, device identifiers, signing material, or local paths.
- Compatibility tests use only `app/Bot` and `shared/fixtures`.
- Build outputs, downloaded tools, APKs, keystores, and local settings stay ignored.

## Graph-first navigation

This project maintains a Graphify graph in `graphify-out/`.

- Before broad source exploration, run `graphify reflect --if-stale`, read
  `graphify-out/reflections/LESSONS.md` when present, and query the graph.
- After source or documentation changes, run `graphify update .`.
- Never hand-edit generated graph JSON or machine-specific Graphify state.

## Architecture

- `mobile/build-android.ps1` is the canonical entry point and defaults to AIR.
- `mobile/air-client/build-air.ps1` compiles `game-client/AS3/grimoire/Root.as`
  into an isolated mobile SWF and packages the captive-runtime arm64 APK.
- `game-client/AS3/grimoire/MobileShell.as` owns the overlay only. AQW remains a
  direct Stage child on its native 960×550 coordinate plane.
- `MobileBotLibrary.as` and `MobileBotRunner.as` provide bounded, data-only GBot
  loading and fail-closed cooperative execution.
- `mobile/app/` and `mobile/ruffle/` are experimental and use a separate Android
  application ID.
- `shared/` contains versioned contracts and synthetic fixtures only.
- `VERSION` is the independent mobile release version source.

## Compatibility and UI rules

- Preserve legacy GBot command names, property meanings, order, and safe defaults.
- Unknown commands must stop visibly; never dynamically resolve Newtonsoft
  `$type` names.
- Keep AQW at origin `(0,0)`, scale `1`, and on the direct AIR Stage. Do not
  reintroduce transformed pointer coordinates.
- The overlay may cover the logical Stage with translucent chrome but must leave
  the game readable and Ciel accessible after closing it.
- Keep Ciel hidden before authentication, draggable while the overlay is closed,
  and bounded to the playable Stage.
- Keep packet history and UI text bounded.
- ActionScript changes ship only after rebuilding the AIR APK.

## Validation

From the repository root:

```powershell
.\tests\Test-MobileAirShell.ps1
.\tests\Test-MobileRuffle.ps1
.\mobile\gradlew.bat -p .\mobile test :app:assembleDebug :app:lintDebug --no-daemon
.\mobile\build-android.ps1 -Configuration Debug
git diff --check
```

Do not launch an emulator or application unless the user asks. Release builds
require protected signing variables and must never create or expose a keystore.

## Releases

Mobile releases are independent from desktop releases. Keep `VERSION`, the AIR
descriptor, Gradle version name/code, release notes, and tag synchronized. Do
not create a tag or release unless the user explicitly asks.
