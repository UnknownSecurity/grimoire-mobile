[CmdletBinding()]
param(
    [string] $DeviceId = 'emulator-5556',

    [string] $PackageName = 'com.unknownsecurity.grimoireexodus.mobile.ruffle',

    [ValidateRange(1.0, 2.0)]
    [double] $MaximumRenderScale = 1.25,

    [ValidateRange(5, 60)]
    [double] $MinimumAnimationFps = 20.0,

    [ValidateRange(1, 10)]
    [int] $SampleSeconds = 3,

    [ValidateRange(1024, 65535)]
    [int] $DevToolsPort = 9224
)

$ErrorActionPreference = 'Stop'

function Invoke-Adb {
    param([Parameter(Mandatory = $true)][string[]] $Arguments)

    $output = & adb -s $DeviceId @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed for the selected emulator: $($output -join ' ')"
    }
    return @($output)
}

function Send-CdpCommand {
    param(
        [Parameter(Mandatory = $true)][System.Net.WebSockets.ClientWebSocket] $Socket,
        [Parameter(Mandatory = $true)][int] $Id,
        [Parameter(Mandatory = $true)][string] $Method,
        [Parameter(Mandatory = $true)][hashtable] $Params,
        [Parameter(Mandatory = $true)][Threading.CancellationToken] $CancellationToken
    )

    $request = [ordered]@{
        id = $Id
        method = $Method
        params = $Params
    } | ConvertTo-Json -Depth 20 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($request)
    [void]$Socket.SendAsync(
        [ArraySegment[byte]]::new($bytes),
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        $CancellationToken
    ).GetAwaiter().GetResult()
}

function Receive-CdpMessage {
    param(
        [Parameter(Mandatory = $true)][System.Net.WebSockets.ClientWebSocket] $Socket,
        [Parameter(Mandatory = $true)][Threading.CancellationToken] $CancellationToken
    )

    $buffer = New-Object byte[] 65536
    $stream = New-Object IO.MemoryStream
    try {
        do {
            $result = $Socket.ReceiveAsync(
                [ArraySegment[byte]]::new($buffer),
                $CancellationToken
            ).GetAwaiter().GetResult()
            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                throw 'The WebView DevTools connection closed unexpectedly.'
            }
            $stream.Write($buffer, 0, $result.Count)
        } while (-not $result.EndOfMessage)
        return [Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
    }
    finally {
        $stream.Dispose()
    }
}

function Get-RuffleTarget {
    param([Parameter(Mandatory = $true)][int] $Port)

    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        try {
            $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json" -TimeoutSec 2
            $target = @($targets | Where-Object {
                $_.type -eq 'page' -and $_.url -like 'http://127.0.0.1:*'
            } | Select-Object -First 1)
            if ($target.Count -gt 0) {
                return $target[0]
            }
        }
        catch {
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    return $null
}

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    throw 'adb is required for the Android Ruffle performance regression.'
}
if (-not $DeviceId.StartsWith('emulator-', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'This regression is restricted to an Android emulator device ID.'
}

$appProcessId = (Invoke-Adb @('shell', 'pidof', $PackageName) | Select-Object -First 1).Trim()
if ($appProcessId -notmatch '^\d+$') {
    throw 'The Grimoire Android app must already be running on the selected emulator.'
}

[void](Invoke-Adb @(
    'forward', "tcp:$DevToolsPort", "localabstract:webview_devtools_remote_$appProcessId"
))
$target = Get-RuffleTarget -Port $DevToolsPort
if ($null -eq $target) {
    throw 'The running Grimoire WebView did not expose its local Ruffle page.'
}

$sampleMilliseconds = $SampleSeconds * 1000
$expression = @"
new Promise(resolve => {
  const waitingStarted = performance.now();
  const begin = () => {
    const player = document.querySelector("ruffle-player");
    const canvas = player && player.shadowRoot
      ? player.shadowRoot.querySelector("canvas")
      : document.querySelector("canvas");
    if (!canvas || canvas.clientWidth <= 0 || canvas.clientHeight <= 0) {
      if (performance.now() - waitingStarted >= 10000) {
        resolve(JSON.stringify({ready:false}));
      } else {
        requestAnimationFrame(begin);
      }
      return;
    }
    const started = performance.now();
    let frames = 0;
    const sample = now => {
      frames++;
      const elapsed = now - started;
      if (elapsed >= $sampleMilliseconds) {
        resolve(JSON.stringify({
          ready: true,
          canvasWidth: canvas.width,
          canvasHeight: canvas.height,
          clientWidth: canvas.clientWidth,
          clientHeight: canvas.clientHeight,
          scaleX: canvas.width / canvas.clientWidth,
          scaleY: canvas.height / canvas.clientHeight,
          devicePixelRatio: window.devicePixelRatio,
          frames: frames,
          elapsedMilliseconds: elapsed,
          animationFps: frames * 1000 / elapsed
        }));
        return;
      }
      requestAnimationFrame(sample);
    };
    requestAnimationFrame(sample);
  };
  begin();
})
"@

$socket = [System.Net.WebSockets.ClientWebSocket]::new()
$lifetime = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($SampleSeconds + 20))
$commandId = 1
try {
    [void]$socket.ConnectAsync([Uri]$target.webSocketDebuggerUrl, $lifetime.Token).GetAwaiter().GetResult()
    Send-CdpCommand -Socket $socket -Id $commandId -Method 'Runtime.evaluate' -Params @{
        expression = $expression
        awaitPromise = $true
        returnByValue = $true
    } -CancellationToken $lifetime.Token

    $measurement = $null
    while ($null -eq $measurement) {
        $message = Receive-CdpMessage -Socket $socket -CancellationToken $lifetime.Token
        if ($message.id -ne $commandId) {
            continue
        }
        if ($null -ne $message.error) {
            throw "The Ruffle performance probe failed: $($message.error.message)"
        }
        $encoded = [string]$message.result.result.value
        if ([string]::IsNullOrWhiteSpace($encoded)) {
            throw 'The Ruffle performance probe returned no measurement.'
        }
        $measurement = $encoded | ConvertFrom-Json
    }

    if ($measurement.ready -ne $true) {
        Write-Output 'RUFFLE_PERFORMANCE FAIL'
        Write-Output 'REASON=CANVAS_NOT_READY'
        exit 1
    }

    $scaleX = [double]$measurement.scaleX
    $scaleY = [double]$measurement.scaleY
    $animationFps = [double]$measurement.animationFps
    Write-Output "CANVAS=$($measurement.canvasWidth)x$($measurement.canvasHeight)"
    Write-Output "CSS_VIEWPORT=$($measurement.clientWidth)x$($measurement.clientHeight)"
    Write-Output "DEVICE_PIXEL_RATIO=$([Math]::Round([double]$measurement.devicePixelRatio, 3))"
    Write-Output "RENDER_SCALE=$([Math]::Round([Math]::Max($scaleX, $scaleY), 3))"
    Write-Output "ANIMATION_FPS=$([Math]::Round($animationFps, 1))"

    if ($scaleX -gt ($MaximumRenderScale + 0.02) -or
        $scaleY -gt ($MaximumRenderScale + 0.02)) {
        Write-Output 'RUFFLE_PERFORMANCE FAIL'
        Write-Output 'REASON=EXCESSIVE_RENDER_SCALE'
        exit 1
    }
    if ($animationFps -lt $MinimumAnimationFps) {
        Write-Output 'RUFFLE_PERFORMANCE FAIL'
        Write-Output 'REASON=ANIMATION_LOOP_STARVATION'
        exit 1
    }

    Write-Output 'RUFFLE_PERFORMANCE PASS'
}
finally {
    if ($socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        [void]$socket.CloseAsync(
            [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
            'done',
            [Threading.CancellationToken]::None
        ).GetAwaiter().GetResult()
    }
    $socket.Dispose()
    $lifetime.Dispose()
}
