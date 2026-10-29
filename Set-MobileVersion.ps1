[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string] $Version
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = $PSScriptRoot
$parts = @($Version.Split('.') | ForEach-Object { [int]$_ })
$versionCode = ($parts[0] * 10000) + ($parts[1] * 100) + $parts[2]
if ($versionCode -le 0 -or $versionCode -gt [int]::MaxValue) {
    throw 'The semantic version cannot be represented as an Android version code.'
}

function Update-RequiredMatch {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [string] $Pattern,
        [Parameter(Mandatory = $true)] [string] $Replacement
    )

    $source = Get-Content -LiteralPath $Path -Raw
    if (-not [regex]::IsMatch($source, $Pattern)) {
        throw "Version marker was not found in $Path"
    }
    $updated = [regex]::Replace($source, $Pattern, $Replacement)
    Set-Content -LiteralPath $Path -Value $updated -NoNewline -Encoding utf8
}

Set-Content -LiteralPath (Join-Path $repositoryRoot 'VERSION') -Value $Version -Encoding ascii

$descriptor = Join-Path $repositoryRoot 'mobile\air-client\GrimoireExodus-app.xml'
Update-RequiredMatch $descriptor '<versionNumber>[^<]+</versionNumber>' "<versionNumber>$Version</versionNumber>"
Update-RequiredMatch $descriptor '<versionLabel>[^<]+</versionLabel>' "<versionLabel>$Version</versionLabel>"

$gradle = Join-Path $repositoryRoot 'mobile\app\build.gradle.kts'
Update-RequiredMatch $gradle 'versionCode\s*=\s*\d+' "versionCode = $versionCode"
Update-RequiredMatch $gradle 'versionName\s*=\s*"[^"]+"' "versionName = `"$Version`""

Write-Host "Mobile version updated to $Version (Android version code $versionCode)."
