param(
    [ValidateSet('Air', 'Ruffle')]
    [string] $Engine = 'Air',

    [ValidateSet('Debug', 'Release')]
    [string] $Configuration = 'Debug',

    [switch] $SkipActionScript
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$mobileRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryRoot = Split-Path -Parent $mobileRoot
$gradle = Join-Path $mobileRoot 'gradlew.bat'
$appBuild = Join-Path $mobileRoot 'app\build.gradle.kts'
$sourceApk = Join-Path $mobileRoot 'app\build\outputs\apk\debug\app-debug.apk'
$distRoot = Join-Path $repositoryRoot 'dist'

if ($Engine -eq 'Air') {
    & (Join-Path $mobileRoot 'air-client\build-air.ps1') -Configuration $Configuration
    if (-not $?) {
        throw 'The default HARMAN AIR Android APK build failed.'
    }
    return
}

if ($Configuration -ne 'Debug') {
    throw 'The experimental Ruffle path currently supports Debug APK builds only.'
}

if (-not $SkipActionScript) {
    & (Join-Path $mobileRoot 'build-ruffle-client.ps1')
    if (-not $?) {
        throw 'The mobile Ruffle ActionScript bridge build failed.'
    }
}

if ([string]::IsNullOrWhiteSpace($env:ANDROID_HOME) -and
    [string]::IsNullOrWhiteSpace($env:ANDROID_SDK_ROOT)) {
    $adb = Get-Command adb -ErrorAction SilentlyContinue
    if ($null -ne $adb) {
        $sdkRoot = Split-Path -Parent (Split-Path -Parent $adb.Source)
        $env:ANDROID_HOME = $sdkRoot
        $env:ANDROID_SDK_ROOT = $sdkRoot
    }
}

Push-Location $mobileRoot
try {
    & $gradle test :app:assembleDebug :app:lintDebug --no-daemon
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $sourceApk -PathType Leaf)) {
        throw 'The Android Ruffle APK build failed.'
    }
}
finally {
    Pop-Location
}

$buildSource = Get-Content -LiteralPath $appBuild -Raw
$versionMatch = [regex]::Match($buildSource, 'versionName\s*=\s*"([^"]+)"')
if (-not $versionMatch.Success) {
    throw 'The Android versionName could not be read from the app build.'
}

New-Item -ItemType Directory -Force -Path $distRoot | Out-Null
$outputName = "Grimoire-Exodus-Android-Ruffle-Experimental-$($versionMatch.Groups[1].Value)-debug.apk"
$outputPath = Join-Path $distRoot $outputName
Copy-Item -LiteralPath $sourceApk -Destination $outputPath -Force

$hash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "Built $outputName"
Write-Host "SHA-256: $hash"
