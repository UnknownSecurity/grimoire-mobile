[CmdletBinding()]
param(
    [string] $SourceDirectory,
    [string] $SourceRepositoryDirectory,
    [switch] $SkipDependencyRestore
)

$ErrorActionPreference = 'Stop'

$mobileRoot = $PSScriptRoot
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $mobileRoot '..'))
$buildRoot = Join-Path $mobileRoot 'build'
$toolsRoot = Join-Path $buildRoot 'ruffle-runtime-tools'
$downloadRoot = Join-Path $toolsRoot 'downloads'
$ruffleRepository = 'https://github.com/ruffle-rs/ruffle.git'
$ruffleVersion = '0.7.1'
$ruffleCommit = '89a7049965f3090e706265670df309a5128233ac'
$wasmBindgenVersion = '0.2.127'
$binaryenVersion = 'version_129'
$binaryenArchiveName = 'binaryen-version_129-x86_64-windows.tar.gz'
$binaryenArchiveUri = "https://github.com/WebAssembly/binaryen/releases/download/$binaryenVersion/$binaryenArchiveName"
$binaryenArchiveSha256 = '1405d2f51377859ccf5fcd2c59c0a8c5756373e691ca0eeb5219f646b743e3aa'
$patchRelativePath = 'mobile/ruffle/patches/0001-canvas-bitmapdata-draw.patch'
$patchPath = Join-Path $repositoryRoot ($patchRelativePath -replace '/', '\')
$patchedCanvasSha256 = 'de14dee3738c0ba119f73a6830a7d30a05d0d79b7b3b71eda52c5a6b8b79cf10'
$patchedWebSha256 = '9e1e404c01780ede70da65fa8146f6cbd59c40e22e9f0235503eb95f46d37d86'
$maximumRenderDevicePixelRatio = 1.25
$assetsPath = Join-Path $mobileRoot 'app\src\main\assets\ruffle'
$manifestPath = Join-Path $mobileRoot 'ruffle\runtime-manifest.json'

if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $SourceDirectory = Join-Path $buildRoot 'ruffle-runtime-v0.7.1-canvas'
}
$SourceDirectory = [IO.Path]::GetFullPath($SourceDirectory)

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $true)][string[]] $Arguments,
        [string] $WorkingDirectory
    )

    $previousLocation = Get-Location
    try {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            Set-Location -LiteralPath $WorkingDirectory
        }
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "$FilePath failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Set-Location -LiteralPath $previousLocation
    }
}

function Assert-FileHash {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $ExpectedSha256
    )

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $ExpectedSha256.ToLowerInvariant()) {
        throw "Hash verification failed for $([IO.Path]::GetFileName($Path))."
    }
}

function Get-CommandOutput {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $true)][string[]] $Arguments,
        [string] $WorkingDirectory
    )

    $previousLocation = Get-Location
    try {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            Set-Location -LiteralPath $WorkingDirectory
        }
        $output = (& $FilePath @Arguments 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) {
            throw "$FilePath failed with exit code $LASTEXITCODE."
        }
        return $output
    }
    finally {
        Set-Location -LiteralPath $previousLocation
    }
}

foreach ($requiredCommand in @('git', 'cargo', 'npm', 'tar')) {
    if (-not (Get-Command $requiredCommand -ErrorAction SilentlyContinue)) {
        throw "Required Ruffle build command is unavailable: $requiredCommand"
    }
}
if (-not (Test-Path -LiteralPath $patchPath -PathType Leaf)) {
    throw "The pinned mobile Ruffle patch is missing: $patchRelativePath"
}

New-Item -ItemType Directory -Force -Path $buildRoot, $toolsRoot, $downloadRoot | Out-Null
if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
    if ([string]::IsNullOrWhiteSpace($SourceRepositoryDirectory)) {
        $SourceRepositoryDirectory = Join-Path $buildRoot 'ruffle-upstream'
        if (-not (Test-Path -LiteralPath (Join-Path $SourceRepositoryDirectory '.git'))) {
            if (Test-Path -LiteralPath $SourceRepositoryDirectory) {
                throw 'The Ruffle repository cache exists but is not a Git checkout.'
            }
            Invoke-CheckedCommand 'git' @(
                'clone', '--filter=blob:none', '--no-checkout', $ruffleRepository,
                $SourceRepositoryDirectory
            )
        }
    }
    $SourceRepositoryDirectory = [IO.Path]::GetFullPath($SourceRepositoryDirectory)
    if (-not (Test-Path -LiteralPath (Join-Path $SourceRepositoryDirectory '.git'))) {
        throw 'The supplied Ruffle repository path is not a Git checkout.'
    }
    & git -c core.excludesfile= -C $SourceRepositoryDirectory cat-file -e "$ruffleCommit`^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Invoke-CheckedCommand 'git' @('fetch', '--depth=1', 'origin', $ruffleCommit) `
            $SourceRepositoryDirectory
    }

    $sourceArchivePath = Join-Path $downloadRoot "ruffle-$ruffleCommit.tar"
    if (-not (Test-Path -LiteralPath $sourceArchivePath -PathType Leaf)) {
        Invoke-CheckedCommand 'git' @(
            '-c', 'core.excludesfile=', 'archive', '--format=tar',
            "--output=$sourceArchivePath", $ruffleCommit
        ) $SourceRepositoryDirectory
    }
    New-Item -ItemType Directory -Force -Path $SourceDirectory | Out-Null
    Invoke-CheckedCommand 'tar' @('-xf', $sourceArchivePath, '-C', $SourceDirectory)
    [IO.File]::WriteAllText(
        (Join-Path $SourceDirectory '.grimoire-ruffle-source'),
        "$ruffleCommit`n",
        (New-Object Text.UTF8Encoding($false))
    )
}

$sourceMarkerPath = Join-Path $SourceDirectory '.grimoire-ruffle-source'
if (-not (Test-Path -LiteralPath $sourceMarkerPath -PathType Leaf) -or
    (Get-Content -Raw -LiteralPath $sourceMarkerPath).Trim() -ne $ruffleCommit) {
    throw 'The Ruffle source snapshot is not the pinned upstream commit.'
}
if (-not (Test-Path -LiteralPath (Join-Path $SourceDirectory '.git'))) {
    Invoke-CheckedCommand 'git' @('init', '--quiet') $SourceDirectory
}

& git -c core.excludesfile= -C $SourceDirectory apply --check $patchPath 2>$null
if ($LASTEXITCODE -eq 0) {
    & git -c core.excludesfile= -C $SourceDirectory apply --whitespace=nowarn $patchPath
    if ($LASTEXITCODE -ne 0) {
        throw "The pinned Canvas patch failed with exit code $LASTEXITCODE."
    }
}
else {
    & git -c core.excludesfile= -C $SourceDirectory apply --reverse --check $patchPath 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'The Ruffle source has changes that do not match the pinned Canvas patch.'
    }
}
Assert-FileHash (Join-Path $SourceDirectory 'render\canvas\src\lib.rs') $patchedCanvasSha256
Assert-FileHash (Join-Path $SourceDirectory 'web\src\lib.rs') $patchedWebSha256

$versionSeal = [ordered]@{
    version_number = $ruffleVersion
    version_name = "Grimoire Mobile $ruffleVersion"
    version_channel = 'grimoire-mobile'
    build_date = '2026-10-07T00:00:00.000Z'
    commitHash = $ruffleCommit
    version4 = ''
    firefox_extension_id = 'ruffle@ruffle.rs'
}
[IO.File]::WriteAllText(
    (Join-Path $SourceDirectory 'web\version_seal.json'),
    ($versionSeal | ConvertTo-Json -Compress),
    (New-Object Text.UTF8Encoding($false))
)

$wasmBindgenPath = Join-Path $toolsRoot 'bin\wasm-bindgen.exe'
$installWasmBindgen = -not (Test-Path -LiteralPath $wasmBindgenPath -PathType Leaf)
if (-not $installWasmBindgen) {
    $installedVersion = Get-CommandOutput $wasmBindgenPath @('--version')
    $installWasmBindgen = $installedVersion -ne "wasm-bindgen $wasmBindgenVersion"
}
if ($installWasmBindgen) {
    Invoke-CheckedCommand 'cargo' @(
        'install', '--locked', '--root', $toolsRoot,
        'wasm-bindgen-cli', '--version', $wasmBindgenVersion
    )
}

$binaryenArchivePath = Join-Path $downloadRoot $binaryenArchiveName
if (-not (Test-Path -LiteralPath $binaryenArchivePath -PathType Leaf)) {
    Invoke-WebRequest -Uri $binaryenArchiveUri -OutFile $binaryenArchivePath
}
Assert-FileHash $binaryenArchivePath $binaryenArchiveSha256

$binaryenRoot = Join-Path $toolsRoot 'binaryen-version_129'
$wasmOptPath = Join-Path $binaryenRoot 'bin\wasm-opt.exe'
if (-not (Test-Path -LiteralPath $wasmOptPath -PathType Leaf)) {
    Invoke-CheckedCommand 'tar' @('-xf', $binaryenArchivePath, '-C', $toolsRoot)
}
if (-not (Test-Path -LiteralPath $wasmOptPath -PathType Leaf)) {
    throw 'The verified Binaryen archive did not contain wasm-opt.exe.'
}
$wasmOptVersion = Get-CommandOutput $wasmOptPath @('--version')
if ($wasmOptVersion -notmatch 'version 129') {
    throw 'The extracted wasm-opt version does not match the pinned Binaryen release.'
}

$webRoot = Join-Path $SourceDirectory 'web'
if (-not $SkipDependencyRestore) {
    Invoke-CheckedCommand 'npm' @('ci', '--no-audit', '--no-fund') $webRoot
}

$previousPath = $env:PATH
try {
    $env:PATH = "$(Join-Path $toolsRoot 'bin');$(Join-Path $binaryenRoot 'bin');$previousPath"
    $env:ENABLE_VERSION_SEAL = 'true'
    $env:CFG_RELEASE_CHANNEL = 'grimoire-mobile'
    Invoke-CheckedCommand 'npm' @('run', 'build', '--workspace=ruffle-core') $webRoot
    Invoke-CheckedCommand 'npm' @('run', 'build', '--workspace=ruffle-selfhosted') $webRoot
}
finally {
    $env:PATH = $previousPath
    Remove-Item Env:ENABLE_VERSION_SEAL -ErrorAction SilentlyContinue
    Remove-Item Env:CFG_RELEASE_CHANNEL -ErrorAction SilentlyContinue
}

$distPath = Join-Path $webRoot 'packages\selfhosted\dist'
$runtimeFiles = @()
$ruffleScript = Join-Path $distPath 'ruffle.js'
if (-not (Test-Path -LiteralPath $ruffleScript -PathType Leaf)) {
    throw 'The self-hosted Ruffle build did not produce ruffle.js.'
}
$runtimeFiles += Get-Item -LiteralPath $ruffleScript
$runtimeFiles += @(Get-ChildItem -LiteralPath $distPath -File -Filter 'core.ruffle.*.js')
$runtimeFiles += @(Get-ChildItem -LiteralPath $distPath -File -Filter '*.wasm')
if (($runtimeFiles | Where-Object Name -Like 'core.ruffle.*.js').Count -ne 1 -or
    ($runtimeFiles | Where-Object Extension -eq '.wasm').Count -ne 1) {
    throw 'The Ruffle build produced an unexpected self-hosted runtime shape.'
}

$assetsFullPath = [IO.Path]::GetFullPath($assetsPath)
$expectedAssetsRoot = [IO.Path]::GetFullPath((Join-Path $mobileRoot 'app\src\main\assets'))
if (-not $assetsFullPath.StartsWith($expectedAssetsRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to replace Ruffle assets outside the Android assets directory.'
}
New-Item -ItemType Directory -Force -Path $assetsFullPath | Out-Null

Get-ChildItem -LiteralPath $assetsFullPath -File | Where-Object {
    $_.Name -eq 'ruffle.js' -or
    $_.Name -like 'core.ruffle.*.js' -or
    $_.Extension -eq '.wasm' -or
    $_.Extension -eq '.map'
} | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Force
}

foreach ($runtimeFile in $runtimeFiles) {
    Copy-Item -LiteralPath $runtimeFile.FullName -Destination $assetsFullPath -Force
}
Copy-Item -LiteralPath (Join-Path $SourceDirectory 'web\packages\selfhosted\LICENSE_APACHE') `
    -Destination (Join-Path $assetsFullPath 'LICENSE_APACHE') -Force
Copy-Item -LiteralPath (Join-Path $SourceDirectory 'web\packages\selfhosted\LICENSE_MIT') `
    -Destination (Join-Path $assetsFullPath 'LICENSE_MIT') -Force

$manifestFiles = @(Get-ChildItem -LiteralPath $assetsFullPath -File | Sort-Object Name | ForEach-Object {
    [ordered]@{
        path = "mobile/app/src/main/assets/ruffle/$($_.Name)"
        bytes = $_.Length
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
})
$manifest = [ordered]@{
    runtime = 'Ruffle'
    version = $ruffleVersion
    upstreamRepository = $ruffleRepository
    upstreamCommit = $ruffleCommit
    renderer = 'canvas'
    maximumRenderDevicePixelRatio = $maximumRenderDevicePixelRatio
    patch = $patchRelativePath
    wasmBindgen = $wasmBindgenVersion
    binaryen = $binaryenVersion
    binaryenArchiveSha256 = $binaryenArchiveSha256
    files = $manifestFiles
}
New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($manifestPath)) | Out-Null
[IO.File]::WriteAllText(
    $manifestPath,
    (($manifest | ConvertTo-Json -Depth 5) + "`n"),
    (New-Object Text.UTF8Encoding($false))
)

Write-Host "Built optimized mobile Ruffle $ruffleVersion runtime with the Canvas patch."
Write-Host "Runtime assets: $($manifestFiles.Count)"
