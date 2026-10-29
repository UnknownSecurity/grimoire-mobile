[CmdletBinding()]
param(
    [string] $AirSdkHome = $env:AIR_HOME
)

$ErrorActionPreference = 'Stop'

$mobileRoot = $PSScriptRoot
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $mobileRoot '..'))
$actionScriptRoot = Join-Path $repositoryRoot 'game-client\AS3'
$rootSource = Join-Path $actionScriptRoot 'grimoire\Root.as'
$outputPath = Join-Path $mobileRoot 'app\src\main\assets\client.swf'
$buildDirectory = Join-Path $mobileRoot 'app\build\generated-ruffle-client'
$temporaryOutput = Join-Path $buildDirectory 'client.swf'

if ([string]::IsNullOrWhiteSpace($AirSdkHome)) {
    $repositorySdk = Join-Path $repositoryRoot '.tools\AIRSDK_51.4.1.2'
    if (Test-Path -LiteralPath $repositorySdk -PathType Container) {
        $AirSdkHome = $repositorySdk
    }
}
if ([string]::IsNullOrWhiteSpace($AirSdkHome)) {
    throw 'HARMAN AIR SDK 51.4 is required. Set AIR_HOME or install it under the ignored .tools directory.'
}

$compiler = Join-Path ([IO.Path]::GetFullPath($AirSdkHome)) 'bin\mxmlc.bat'
foreach ($requiredPath in @($compiler, $rootSource)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required mobile Ruffle build input is missing: $requiredPath"
    }
}

New-Item -ItemType Directory -Force -Path $buildDirectory | Out-Null
if (Test-Path -LiteralPath $temporaryOutput -PathType Leaf) {
    Remove-Item -LiteralPath $temporaryOutput -Force
}

& $compiler `
    "-source-path+=$actionScriptRoot" `
    '-includes=grimoire.MobileBotRunner' `
    '-debug=false' `
    '-compiler.float=false' `
    '-target-player=32.0' `
    '-swf-version=43' `
    '-default-size=960,550' `
    '-default-frame-rate=30' `
    '-default-background-color=#05060B' `
    "-output=$temporaryOutput" `
    $rootSource
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $temporaryOutput -PathType Leaf)) {
    throw "The mobile Ruffle ActionScript compilation failed with exit code $LASTEXITCODE."
}

Copy-Item -LiteralPath $temporaryOutput -Destination $outputPath -Force
$hash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host 'Built mobile/app/src/main/assets/client.swf'
Write-Host "SHA-256: $hash"
