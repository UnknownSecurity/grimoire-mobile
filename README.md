# Grimoire Exodus Mobile

Grimoire Exodus Mobile is the standalone Android port of Grimoire Exodus. It
owns its AQW client, uses the original HARMAN AIR AVM2 runtime by default, and
draws the Grimoire command overlay above the live game. It does not launch,
patch, automate, or repackage another installed Android application.

The current independent mobile version is **0.5.0**. Mobile and desktop now
have separate version histories, build pipelines, signing keys, and releases.
Use `.\Set-MobileVersion.ps1 -Version <major.minor.patch>` to update the mobile
AIR descriptor and experimental Android version together.

## Current features

- Landscape-only, immersive AQW client loaded from the official live endpoint
- HARMAN AIR default engine with the native 960×550 AQW coordinate plane
- Dark violet, full-stage glass overlay with left controls and a live right rail
- Operational Bot Manager with bounded `.gbot` import and fail-closed execution
- Draggable Ciel control for opening the overlay without blocking game controls
- Bank, Options, Packet, Tools, profile status, and mobile settings surfaces
- Separately identified Compose/Ruffle experimental research build

## Build

Requirements for the default APK:

- Windows
- JDK 17 or 21
- HARMAN AIR SDK 51.4 in `AIR_HOME` or `.tools/AIRSDK_51.4.1.2`
- A valid HARMAN AIR SDK license

From the repository root:

```powershell
.\mobile\build-android.ps1 -Configuration Debug
```

The arm64 APK is written to `dist/`. Release builds additionally require the
protected `GRIMOIRE_ANDROID_KEYSTORE` and
`GRIMOIRE_ANDROID_KEYSTORE_PASSWORD` environment variables.

The experimental Ruffle build is explicit:

```powershell
.\mobile\build-android.ps1 -Engine Ruffle
```

See [mobile/README.md](mobile/README.md) for architecture and validation details
and [docs/android-port-plan.md](docs/android-port-plan.md) for the delivery plan.

## Safety and privacy

The mobile Bot Manager parses legacy documents as bounded JSON data and never
resolves arbitrary serialized types. Unsupported commands stop the run rather
than being guessed or skipped. Never commit credentials, private bot files,
signing material, device logs, APKs, or machine-specific paths.

Only download builds from this repository's official
[GitHub Releases](https://github.com/UnknownSecurity/grimoire-mobile/releases).
Unofficial mirrors or repacks may contain credential stealers, malware, or
cryptocurrency miners.

## Community

- [Contributing](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security policy](SECURITY.md)

## License

Repository-authored source is provided under [CC0 1.0 Universal](LICENSE).
HARMAN AIR, AQW content, Ruffle, and other third-party components retain their
respective licenses and trademarks.
