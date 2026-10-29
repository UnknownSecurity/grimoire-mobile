param()

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$activityPath = Join-Path $repositoryRoot 'mobile\app\src\main\kotlin\com\unknownsecurity\grimoireexodus\mobile\MainActivity.kt'
$transportPath = Join-Path $repositoryRoot 'mobile\app\src\main\kotlin\com\unknownsecurity\grimoireexodus\mobile\ruffle\RuffleGameTransport.kt'
$serverPath = Join-Path $repositoryRoot 'mobile\app\src\main\kotlin\com\unknownsecurity\grimoireexodus\mobile\ruffle\RuffleLoopbackServer.kt'
$mapPath = Join-Path $repositoryRoot 'mobile\app\src\main\kotlin\com\unknownsecurity\grimoireexodus\mobile\ruffle\RuffleServerMap.kt'
$surfacePath = Join-Path $repositoryRoot 'mobile\app\src\main\kotlin\com\unknownsecurity\grimoireexodus\mobile\ruffle\RuffleGameSurface.kt'
$uiPath = Join-Path $repositoryRoot 'mobile\app\src\main\kotlin\com\unknownsecurity\grimoireexodus\mobile\ui\GrimoireExodusApp.kt'
$hostPagePath = Join-Path $repositoryRoot 'mobile\app\src\main\assets\ruffle-host\index.html'
$manifestPath = Join-Path $repositoryRoot 'mobile\app\src\main\AndroidManifest.xml'
$cielAssetPath = Join-Path $repositoryRoot 'mobile\app\src\main\res\drawable-nodpi\ciel_skill.png'
$clientBuildPath = Join-Path $repositoryRoot 'mobile\build-ruffle-client.ps1'
$runtimeBuildPath = Join-Path $repositoryRoot 'mobile\build-ruffle-runtime.ps1'
$runtimeManifestPath = Join-Path $repositoryRoot 'mobile\ruffle\runtime-manifest.json'
$runtimePatchPath = Join-Path $repositoryRoot 'mobile\ruffle\patches\0001-canvas-bitmapdata-draw.patch'
$runtimeAssetsPath = Join-Path $repositoryRoot 'mobile\app\src\main\assets\ruffle'
$clientSwfPath = Join-Path $repositoryRoot 'mobile\app\src\main\assets\client.swf'
$appBuildPath = Join-Path $repositoryRoot 'mobile\app\build.gradle.kts'
$apkBuildPath = Join-Path $repositoryRoot 'mobile\build-android.ps1'
$rootPath = Join-Path $repositoryRoot 'game-client\AS3\grimoire\Root.as'
$clientPath = Join-Path $repositoryRoot 'game-client\AS3\grimoire\game\Client.as'
$externalizerPath = Join-Path $repositoryRoot 'game-client\AS3\grimoire\Externalizer.as'
$sessionSignalPath = Join-Path $repositoryRoot 'mobile\core\model\src\main\kotlin\com\unknownsecurity\grimoireexodus\model\MobileSessionSignal.kt'

function Assert-Contract {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) {
        throw "Mobile Ruffle contract failed: $Message"
    }
}

$activity = Get-Content -Raw $activityPath
$transport = Get-Content -Raw $transportPath
$server = Get-Content -Raw $serverPath
$map = Get-Content -Raw $mapPath
$surface = Get-Content -Raw $surfacePath
$ui = Get-Content -Raw $uiPath
$hostPage = Get-Content -Raw $hostPagePath
$manifest = Get-Content -Raw $manifestPath
$clientBuild = Get-Content -Raw $clientBuildPath
$runtimeBuild = Get-Content -Raw $runtimeBuildPath
$runtimePatch = Get-Content -Raw $runtimePatchPath
$runtimeManifest = Get-Content -Raw $runtimeManifestPath | ConvertFrom-Json
$apkBuild = Get-Content -Raw $apkBuildPath
$root = Get-Content -Raw $rootPath
$client = Get-Content -Raw $clientPath
$externalizer = Get-Content -Raw $externalizerPath
$sessionSignal = Get-Content -Raw $sessionSignalPath
$appBuild = Get-Content -Raw $appBuildPath

Assert-Contract ($activity -match 'RuffleGameTransport\(applicationContext\)') `
    'The experimental Compose application must retain its Ruffle transport.'
Assert-Contract (($manifest -match 'android\.permission\.INTERNET') -and
    ($manifest -match 'network_security_config')) `
    'Android must permit the official HTTPS client and loopback-only Ruffle host.'
Assert-Contract (($surface -match '960f\s*/\s*550f') -and
    ($surface -match 'aspectRatio\(AQW_ASPECT_RATIO')) `
    'The Ruffle surface must preserve AQW''s native 960x550 aspect ratio.'
Assert-Contract (($hostPage -match 'socketProxy') -and
    ($hostPage -match '41000 \+ slot') -and
    ($hostPage -match 'grimoireInvoke') -and
    ($hostPage -match 'urlRewriteRules') -and
    ($hostPage -match 'preferredRenderer:\s*"canvas"') -and
    ($hostPage -match 'logLevel:\s*"error"') -and
    ($hostPage -match 'fitPlayerToViewport') -and
    ($hostPage -match 'height:100vh')) `
    'The host page must configure sockets, callbacks, asset rewriting, the patched Canvas renderer, and a non-zero viewport.'
Assert-Contract (($server -match 'ServerSocket\(0, 32, InetAddress\.getByName\("127\.0\.0\.1"\)\)') -and
    ($server -match 'MAXIMUM_WEBSOCKET_BYTES') -and
    ($server -match 'MAXIMUM_UPSTREAM_BYTES') -and
    ($server -match 'OFFICIAL_GAME_BASE') -and
    ($server -notmatch 'ruffle-client-probe|DEBUG-ruffle')) `
    'The Android host must be loopback-only, bounded, and limited to the official game origin.'
Assert-Contract (($map -match 'ALLOWED_SUFFIXES') -and
    ($map -match 'isPublicIpv4') -and
    ($map -match 'FIRST_SYNTHETIC_PORT')) `
    'AQW socket endpoints must be validated before they are mapped into Ruffle.'
Assert-Contract (($transport -match 'MAXIMUM_PACKET_ENTRIES\s*=\s*40') -and
    ($transport -match 'MAXIMUM_PACKET_CAPTURE_CHARACTERS\s*=\s*320') -and
    ($transport -match 'ALLOWED_CALLBACKS')) `
    'Packet capture and native-to-ActionScript calls must remain bounded and allowlisted.'
Assert-Contract ((Test-Path -LiteralPath $cielAssetPath -PathType Leaf) -and
    ($ui -match 'Alignment\.TopEnd') -and
    ($ui -match 'else if \(inGame\)') -and
    ($ui -match 'Close Grimoire overlay') -and
    ($ui -match 'Summon Ciel to automate and take over your body')) `
    'Ciel must stay in the top-right, remain hidden during login, and reopen a closable overlay.'
Assert-Contract (($transport -match 'MobileSessionSignal\.isInventoryLoaded') -and
    ($transport -match 'scheduleWithFixedDelay\(\s*::pollSession') -and
    ($transport -match 'AtomicBoolean\(false\)') -and
    ($transport -match 'evaluateBridgeSession\(target\)') -and
    ($transport -match 'decodeBridgeSession') -and
    ($transport -match 'evaluateBridgeProfile\(target\)') -and
    ($transport -match 'setOf\("InGame", "Username", "Level", "Class"\)') -and
    ($transport -match 'MobileSessionSignal\.reduceBridgeSession') -and
    ($transport -match 'refreshProfile\(PROFILE_RETRY_DELAY_MILLIS\)') -and
    ($transport -match 'RufflePlayerProfile') -and
    ($transport -match "typeof window\.grimoireInvoke === 'function'") -and
    ($hostPage -match 'grimoireSessionSnapshot') -and
    ($sessionSignal -match 'fun reduceBridgeSession') -and
    ($sessionSignal -match 'replace\("&quot;"') -and
    ($externalizer -notmatch '"MobileProfile"')) `
    'Login state must poll the live bridge while retaining packet detection as a fast path.'
Assert-Contract (($client -match 'if \(game == null\)') -and
    ($client -match 'game\.ui == null \|\| game\.ui\.mcInterface == null') -and
    ($client -match 'game\.sfc != null && game\.sfc\.isConnected') -and
    ($client -match 'game\.world\.myAvatar != null') -and
    ($client -match 'catch \(error:Error\)')) `
    'Session polling must use the connected Game timeline while retaining fail-closed legacy UI checks.'
Assert-Contract (($ui -match 'Destination\.Bank') -and
    ($ui -match 'Destination\.Options') -and
    ($ui -match 'Destination\.Packet') -and
    ($ui -match 'Destination\.Tools') -and
    ($ui -match 'MobileNavigationState\.select') -and
    ($ui -match '"RUFFLE"') -and
    ($ui -notmatch 'MOBILE COMMAND CENTER|Text\("Grimoire(?: Exodus)?"')) `
    'The title-free Ruffle top bar must expose Bank, Options, Packet, and Tools.'
Assert-Contract (($transport -match 'MobileBotStart') -and
    ($transport -match 'MAXIMUM_BOT_DOCUMENT_CHARACTERS') -and
    ($ui -match 'MobileBotControls') -and
    ($hostPage -match 'mobileBotState')) `
    'The Ruffle Bot Manager must use the bounded cooperative ActionScript runner.'
Assert-Contract (($clientBuild -match 'includes=grimoire\.MobileBotRunner') -and
    ($clientBuild -match 'app\\src\\main\\assets\\client\.swf') -and
    ($clientBuild -notmatch 'game-client\\grimoire-exodus\.swf')) `
    'The mobile bridge build must include the runner without overwriting the desktop SWF.'
$clientSwfBytes = [IO.File]::ReadAllBytes($clientSwfPath)
Assert-Contract (($clientBuild -match 'target-player=32\.0') -and
    ($clientBuild -match 'compiler\.float=false') -and
    ($clientBuild -match 'swf-version=43') -and
    ($clientSwfBytes.Length -ge 10000) -and
    ($clientSwfBytes[3] -le 43)) `
    'The real mobile bridge SWF must disable float bytecode and cap SWF version 43 so the pinned Ruffle runtime can verify its AVM2 bytecode.'
Assert-Contract (($apkBuild -match '\[string\]\s*\$Engine\s*=\s*''Air''') -and
    ($apkBuild -match 'if \(\$Engine -eq ''Air''\)') -and
    ($apkBuild -match 'Grimoire-Exodus-Android-Ruffle-Experimental-') -and
    ($apkBuild -match ':app:assembleDebug') -and
    ($appBuild -match 'applicationId\s*=\s*"com\.unknownsecurity\.grimoireexodus\.mobile\.ruffle"')) `
    'Ruffle must remain available only as an explicitly selected, separately identified experimental APK.'
Assert-Contract (($appBuild -match 'versionCode\s*=\s*500') -and
    ($appBuild -match 'versionName\s*=\s*"0\.5\.0"')) `
    'The experimental Android target must use the standalone mobile 0.5.0 version.'
Assert-Contract (($root -match 'documentJson\.length\s*>\s*2\s*\*\s*1024\s*\*\s*1024') -and
    ($root -match 'commands\.length\s*>\s*5000') -and
    ($root -match 'getDefinitionByName\("grimoire\.MobileBotRunner"\)') -and
    ($externalizer -match '"MobileBotStart"') -and
    ($externalizer -match '"MobileBotStop"') -and
    ($externalizer -match '"MobileBotPause"')) `
    'The Ruffle bot bridge must validate size and command count before resolving the included mobile runner.'

Assert-Contract (($runtimeManifest.version -eq '0.7.1') -and
    ($runtimeManifest.upstreamCommit -eq '89a7049965f3090e706265670df309a5128233ac') -and
    ($runtimeManifest.renderer -eq 'canvas') -and
    ([double]$runtimeManifest.maximumRenderDevicePixelRatio -eq 1.25) -and
    ($runtimeManifest.wasmBindgen -eq '0.2.127') -and
    ($runtimeManifest.binaryen -eq 'version_129') -and
    ($runtimeManifest.binaryenArchiveSha256 -eq '1405d2f51377859ccf5fcd2c59c0a8c5756373e691ca0eeb5219f646b743e3aa')) `
    'The custom mobile runtime provenance must pin Ruffle and its optimizer toolchain.'
Assert-Contract (($runtimeBuild -match [regex]::Escape($runtimeManifest.upstreamCommit)) -and
    ($runtimeBuild -match [regex]::Escape($runtimeManifest.binaryenArchiveSha256)) -and
    ($runtimeBuild -match 'Assert-FileHash') -and
    ($runtimeBuild -match 'wasm-opt') -and
    ($runtimePatch -match 'fn render_to_bitmap') -and
    ($runtimePatch -match 'for entry in cache_entries') -and
    ($runtimePatch -notmatch '(?m)^\+\s+panic!\("Bitmap caching is unavailable on the canvas backend"') -and
    ($runtimePatch -match 'fn is_offscreen_supported\(&self\) -> bool') -and
    ($runtimePatch -match 'get_image_data') -and
    ($runtimePatch -match 'MAXIMUM_RENDER_DEVICE_PIXEL_RATIO:\s*f64\s*=\s*1\.25') -and
    ($runtimePatch -match 'render_device_pixel_ratio') -and
    ($runtimePatch -notmatch 'render/webgl')) `
    'The runtime build must verify dependencies and apply only the tracked Canvas BitmapData and render-density patch.'

$manifestNames = @()
foreach ($file in @($runtimeManifest.files)) {
    $assetPath = Join-Path $repositoryRoot ($file.path -replace '/', '\')
    Assert-Contract (Test-Path -LiteralPath $assetPath -PathType Leaf) `
        'A runtime file recorded by the mobile manifest is missing.'
    Assert-Contract ((Get-Item -LiteralPath $assetPath).Length -eq [long]$file.bytes) `
        'A mobile runtime file size does not match its manifest.'
    Assert-Contract ((Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq
        [string]$file.sha256) `
        'A mobile runtime file hash does not match its manifest.'
    $manifestNames += [IO.Path]::GetFileName($assetPath)
}

$actualRuntimeNames = @(Get-ChildItem -LiteralPath $runtimeAssetsPath -File | ForEach-Object Name | Sort-Object)
$expectedRuntimeNames = @($manifestNames | Sort-Object)
Assert-Contract (($actualRuntimeNames -join '|') -eq ($expectedRuntimeNames -join '|')) `
    'The Android runtime directory must not contain stale experimental assets.'

$ruffleScript = Get-Content -Raw (Join-Path $runtimeAssetsPath 'ruffle.js')
$runtimeModuleNames = @($actualRuntimeNames | Where-Object {
    $_ -like 'core.ruffle.*.js' -or $_ -like '*.wasm'
})
Assert-Contract (($runtimeModuleNames.Count -eq 2) -and
    ($runtimeModuleNames | Where-Object { -not $ruffleScript.Contains($_) }).Count -eq 0) `
    'ruffle.js must reference exactly one optimized core module and one optimized WASM module.'

Write-Host 'Mobile Ruffle contract passed.'
