# Contributing to Grimoire Exodus

Thanks for helping improve Grimoire Exodus. By participating, you agree to
follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before opening an issue

- Search existing issues to avoid duplicates.
- Use the bug or feature issue form and include enough detail to reproduce the problem.
- Never post passwords, account-vault contents, access tokens, private bot data, or other secrets.
- Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Development setup

You need Windows, JDK 17 or 21, and the licensed HARMAN AIR SDK 51.4. The SDK may
be provided through `AIR_HOME` or the ignored `.tools/AIRSDK_51.4.1.2` folder.

```powershell
git clone https://github.com/UnknownSecurity/grimoire-mobile.git
cd grimoire-mobile
.\mobile\build-android.ps1 -Configuration Debug
```

Create a focused branch from `main`. Keep unrelated formatting or generated
output out of the change. Do not commit APKs, AIR SDK files, signing material,
local account data, private bots, packet logs, or credentials.

## Testing changes

Run the checks relevant to your change:

```powershell
.\tests\Test-MobileAirShell.ps1
.\tests\Test-MobileRuffle.ps1
.\mobile\gradlew.bat -p .\mobile test :app:assembleDebug :app:lintDebug --no-daemon
.\mobile\build-android.ps1 -Configuration Debug
git diff --check
```

Confirm visible overlay changes in landscape at the native 960×550 logical
plane. Keep AQW touch coordinates aligned and test both an open overlay and the
closed, draggable Ciel state. Do not launch a private account unless the user
explicitly places it in scope.

## Commits and pull requests

- Use a conventional commit message such as `fix: prevent accidental shutdown`.
- Keep each commit understandable and limited to one purpose.
- Explain the user-visible behavior and technical approach in the pull request.
- List the checks you ran and include screenshots for visible UI changes.
- Link related issues with `Fixes #123` when appropriate.
- Update documentation when behavior, setup, or release packaging changes.

Maintainers may request changes before merging. A contribution is not accepted
until it has been reviewed and merged.
