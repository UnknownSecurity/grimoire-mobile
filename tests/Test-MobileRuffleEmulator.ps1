[CmdletBinding()]
param(
    [string] $DeviceId = 'emulator-5556',

    [string] $PackageName = 'com.unknownsecurity.grimoireexodus.mobile.ruffle',

    [ValidateRange(5, 120)]
    [int] $TimeoutSeconds = 45,

    [ValidateRange(1024, 65535)]
    [int] $DevToolsPort = 9223
)

$ErrorActionPreference = 'Stop'
$panicText = 'Bitmap caching is unavailable'

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

function Get-CdpSignalText {
    param($Message)

    if ($Message.method -eq 'Runtime.consoleAPICalled') {
        return @($Message.params.args | ForEach-Object {
            if ($null -ne $_.value) { [string]$_.value } else { [string]$_.description }
        }) -join ' '
    }
    if ($Message.method -eq 'Runtime.exceptionThrown') {
        return @(
            [string]$Message.params.exceptionDetails.text
            [string]$Message.params.exceptionDetails.exception.description
        ) -join ' '
    }
    if ($Message.method -eq 'Log.entryAdded') {
        return [string]$Message.params.entry.text
    }
    return ''
}

function Test-BridgeReadyResponse {
    param($Message)

    if ($null -eq $Message.result.result.value) {
        return $false
    }
    try {
        $probe = [string]$Message.result.result.value | ConvertFrom-Json
        return $probe.ready -eq $true
    }
    catch {
        return $false
    }
}

function Get-RuffleTarget {
    param(
        [Parameter(Mandatory = $true)][int] $Port,
        [ValidateRange(1, 15)][int] $WaitSeconds = 10
    )

    $target = @()
    $targetDeadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
    while ($target.Count -eq 0 -and [DateTime]::UtcNow -lt $targetDeadline) {
        try {
            $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json" -TimeoutSec 2
            $target = @($targets | Where-Object {
                $_.type -eq 'page' -and $_.url -like 'http://127.0.0.1:*'
            } | Select-Object -First 1)
        }
        catch {
            $target = @()
        }
        if ($target.Count -eq 0) {
            Start-Sleep -Milliseconds 250
        }
    }
    return $target
}

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    throw 'adb is required for the Android Ruffle emulator regression.'
}
if (-not $DeviceId.StartsWith('emulator-', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'This regression is restricted to an Android emulator device ID.'
}

$deviceState = (Invoke-Adb @('get-state') | Select-Object -First 1).Trim()
if ($deviceState -ne 'device') {
    throw "The selected emulator is unavailable: $deviceState"
}
$appProcessId = (Invoke-Adb @('shell', 'pidof', $PackageName) | Select-Object -First 1).Trim()
if ($appProcessId -notmatch '^\d+$') {
    throw 'The Grimoire Android app must already be running on the selected emulator.'
}

[void](Invoke-Adb @(
    'forward', "tcp:$DevToolsPort", "localabstract:webview_devtools_remote_$appProcessId"
))
$target = @(Get-RuffleTarget -Port $DevToolsPort)
if ($target.Count -eq 0) {
    throw 'The running Grimoire WebView did not expose its local Ruffle page.'
}

$socket = [System.Net.WebSockets.ClientWebSocket]::new()
$lifetime = [Threading.CancellationTokenSource]::new(
    [TimeSpan]::FromSeconds($TimeoutSeconds + 10)
)
$commandId = 0
$probeIds = [Collections.Generic.HashSet[int]]::new()
$ready = $false
$panic = $false
$lastProbeAt = [DateTime]::MinValue
$reconnects = 0
$readyExpression = @'
JSON.stringify((() => {
  try {
    if (typeof window.grimoireInvoke !== "function") return {ready:false};
    const response = JSON.parse(window.grimoireInvoke(JSON.stringify({name:"InGame",args:[]})));
    const snapshot = typeof window.grimoireSessionSnapshot === "function"
      ? JSON.parse(window.grimoireSessionSnapshot())
      : {ok:false};
    return {ready:response.ok === true && snapshot.ok === true};
  } catch (_) {
    return {ready:false};
  }
})())
'@

try {
    [void]$socket.ConnectAsync([Uri]$target.webSocketDebuggerUrl, $lifetime.Token).GetAwaiter().GetResult()
    foreach ($method in @('Runtime.enable', 'Log.enable', 'Page.enable')) {
        $commandId++
        Send-CdpCommand -Socket $socket -Id $commandId -Method $method -Params @{} `
            -CancellationToken $lifetime.Token
    }
    $commandId++
    Send-CdpCommand -Socket $socket -Id $commandId -Method 'Page.reload' `
        -Params @{ ignoreCache = $true } -CancellationToken $lifetime.Token

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline -and -not $ready -and -not $panic) {
        try {
            if (([DateTime]::UtcNow - $lastProbeAt).TotalMilliseconds -ge 500) {
                $commandId++
                [void]$probeIds.Add($commandId)
                Send-CdpCommand -Socket $socket -Id $commandId -Method 'Runtime.evaluate' `
                    -Params @{ expression = $readyExpression; returnByValue = $true } `
                    -CancellationToken $lifetime.Token
                $lastProbeAt = [DateTime]::UtcNow
            }

            $message = Receive-CdpMessage -Socket $socket `
                -CancellationToken $lifetime.Token
            $signal = Get-CdpSignalText $message
            if ($signal.IndexOf($panicText, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $panic = $true
            }
            if ($null -ne $message.id -and $probeIds.Remove([int]$message.id)) {
                if (Test-BridgeReadyResponse $message) {
                    $ready = $true
                }
            }
        }
        catch [System.OperationCanceledException] {
        }
        catch {
            if ([DateTime]::UtcNow -ge $deadline -or $reconnects -ge 3) {
                throw
            }
            $reconnects++
            $socket.Dispose()
            Start-Sleep -Milliseconds 200
            $target = @(Get-RuffleTarget -Port $DevToolsPort -WaitSeconds 5)
            if ($target.Count -eq 0) {
                throw 'The Ruffle WebView target disappeared during reload.'
            }
            $socket = [System.Net.WebSockets.ClientWebSocket]::new()
            [void]$socket.ConnectAsync(
                [Uri]$target.webSocketDebuggerUrl,
                $lifetime.Token
            ).GetAwaiter().GetResult()
            foreach ($method in @('Runtime.enable', 'Log.enable')) {
                $commandId++
                Send-CdpCommand -Socket $socket -Id $commandId -Method $method -Params @{} `
                    -CancellationToken $lifetime.Token
            }
            $lastProbeAt = [DateTime]::MinValue
        }
    }

    if ($panic) {
        Write-Output 'RUFFLE_EMULATOR_READY FAIL'
        Write-Output 'REASON=BITMAP_CACHE_PANIC'
        exit 1
    }
    if (-not $ready) {
        Write-Output 'RUFFLE_EMULATOR_READY FAIL'
        Write-Output 'REASON=BRIDGE_READY_TIMEOUT'
        exit 1
    }

    Write-Output 'RUFFLE_EMULATOR_READY PASS'
    Write-Output 'BRIDGE_READY=true'
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
