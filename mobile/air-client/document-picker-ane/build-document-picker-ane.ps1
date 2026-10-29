[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $AirSdkHome,

    [string] $AndroidSdkHome = $env:ANDROID_SDK_ROOT
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$extensionRoot = $PSScriptRoot
$airClientRoot = Split-Path -Parent $extensionRoot
$buildRoot = Join-Path $airClientRoot 'build\document-picker-ane'
$actionScriptRoot = Join-Path $extensionRoot 'actionscript'
$nativeSourceRoot = Join-Path $extensionRoot 'native\src'
$extensionDescriptor = Join-Path $extensionRoot 'extension.xml'
$extensionDirectory = Join-Path $airClientRoot 'build\extensions'
$extensionOutput = Join-Path $extensionDirectory 'GrimoireDocumentPicker.ane'
$swcPath = Join-Path $buildRoot 'GrimoireDocumentPicker.swc'
$nativeClasses = Join-Path $buildRoot 'native-classes'
$platformRoot = Join-Path $buildRoot 'platform'
$nativeJar = Join-Path $platformRoot 'GrimoireDocumentPicker.jar'
$librarySwf = Join-Path $platformRoot 'library.swf'

if ([string]::IsNullOrWhiteSpace($AndroidSdkHome)) {
    $AndroidSdkHome = $env:ANDROID_HOME
}
if ([string]::IsNullOrWhiteSpace($AndroidSdkHome)) {
    $adb = Get-Command adb -ErrorAction SilentlyContinue
    if ($null -ne $adb) {
        $AndroidSdkHome = Split-Path -Parent (Split-Path -Parent $adb.Source)
    }
}
if ([string]::IsNullOrWhiteSpace($AndroidSdkHome)) {
    throw 'The Android SDK is required to build the document picker extension.'
}

$AirSdkHome = [IO.Path]::GetFullPath($AirSdkHome)
$AndroidSdkHome = [IO.Path]::GetFullPath($AndroidSdkHome)
$compc = Join-Path $AirSdkHome 'bin\compc.bat'
$adt = Join-Path $AirSdkHome 'bin\adt.bat'
$freJar = Join-Path $AirSdkHome 'lib\android\FlashRuntimeExtensions.jar'
$javac = (Get-Command javac -ErrorAction Stop).Source
$jar = (Get-Command jar -ErrorAction Stop).Source
$androidPlatform = Get-ChildItem -LiteralPath (Join-Path $AndroidSdkHome 'platforms') -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'android.jar') -PathType Leaf } |
    Sort-Object Name -Descending |
    Select-Object -First 1 -ExpandProperty FullName
$androidJar = if ([string]::IsNullOrWhiteSpace($androidPlatform)) {
    $null
} else {
    Join-Path $androidPlatform 'android.jar'
}

foreach ($required in @($compc, $adt, $freJar, $androidJar, $extensionDescriptor)) {
    if ([string]::IsNullOrWhiteSpace($required) -or
        -not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required document picker build input is missing: $required"
    }
}

New-Item -ItemType Directory -Force -Path $buildRoot, $nativeClasses, $platformRoot, $extensionDirectory | Out-Null

& $compc `
    "-source-path+=$actionScriptRoot" `
    '-include-classes=grimoire.nativebridge.AndroidDocumentPicker' `
    "-output=$swcPath"
if ($LASTEXITCODE -ne 0) {
    throw 'The document picker ActionScript library failed to compile.'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$swcArchive = [IO.Compression.ZipFile]::OpenRead($swcPath)
try {
    $entry = $swcArchive.GetEntry('library.swf')
    if ($null -eq $entry) {
        throw 'The document picker SWC does not contain library.swf.'
    }
    $input = $entry.Open()
    $output = [IO.File]::Open($librarySwf, [IO.FileMode]::Create, [IO.FileAccess]::Write)
    try {
        $input.CopyTo($output)
    }
    finally {
        $output.Dispose()
        $input.Dispose()
    }
}
finally {
    $swcArchive.Dispose()
}

$javaSources = @(Get-ChildItem -LiteralPath $nativeSourceRoot -Recurse -Filter '*.java' -File |
    Select-Object -ExpandProperty FullName)
if ($javaSources.Count -eq 0) {
    throw 'The document picker native source is missing.'
}
$classPath = "$freJar;$androidJar"
& $javac -source 8 -target 8 -encoding UTF-8 -classpath $classPath -d $nativeClasses @javaSources
if ($LASTEXITCODE -ne 0) {
    throw 'The document picker Android library failed to compile.'
}
& $jar cf $nativeJar -C $nativeClasses .
if ($LASTEXITCODE -ne 0) {
    throw 'The document picker Android library could not be archived.'
}

& $adt -package -target ane $extensionOutput $extensionDescriptor `
    -swc $swcPath `
    -platform Android-ARM -C $platformRoot . `
    -platform Android-ARM64 -C $platformRoot .
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $extensionOutput -PathType Leaf)) {
    throw 'The document picker AIR native extension failed to package.'
}

Write-Output $extensionOutput
