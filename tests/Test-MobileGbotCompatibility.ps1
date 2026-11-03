[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runnerPath = Join-Path $repositoryRoot 'game-client\AS3\grimoire\MobileBotRunner.as'
$libraryPath = Join-Path $repositoryRoot 'game-client\AS3\grimoire\MobileBotLibrary.as'

function Assert-Contract([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Get-CommandTypeNames([object] $Document) {
    $commands = $Document.Commands.'$values'
    foreach ($command in @($commands)) {
        if ($null -eq $command -or [string]::IsNullOrWhiteSpace([string]$command.'$type')) {
            throw 'A repository-controlled GBot contains a command without a legacy type identity.'
        }
        $qualified = ([string]$command.'$type' -split ',')[0]
        ($qualified -split '\.')[-1]
    }
}

$runnerSource = Get-Content -LiteralPath $runnerPath -Raw
$librarySource = Get-Content -LiteralPath $libraryPath -Raw
$runnerCommands = [regex]::Matches($runnerSource, 'case\s+"(Cmd[^"]+)"') |
    ForEach-Object { $_.Groups[1].Value } |
    Sort-Object -Unique

$maximumBytesMatch = [regex]::Match($librarySource,
    'MAX_BOT_BYTES:uint\s*=\s*(\d+)\s*\*\s*(\d+)\s*\*\s*(\d+)')
$maximumCommandsMatch = [regex]::Match($librarySource, 'MAX_COMMANDS:int\s*=\s*(\d+)')
Assert-Contract ($maximumBytesMatch.Success -and $maximumCommandsMatch.Success) `
    'The bounded mobile GBot limits could not be verified.'
$maximumBytes = [int64]$maximumBytesMatch.Groups[1].Value *
    [int64]$maximumBytesMatch.Groups[2].Value *
    [int64]$maximumBytesMatch.Groups[3].Value
$maximumCommands = [int]$maximumCommandsMatch.Groups[1].Value

$fixtureDirectory = Join-Path $repositoryRoot 'shared\fixtures\gbot\v1'
$communityDirectory = Join-Path $repositoryRoot 'app\Bot'
$documents = @()
if (Test-Path -LiteralPath $fixtureDirectory -PathType Container) {
    $documents += Get-ChildItem -LiteralPath $fixtureDirectory -Filter '*.gbot' -File -Recurse
}
if (Test-Path -LiteralPath $communityDirectory -PathType Container) {
    $documents += Get-ChildItem -LiteralPath $communityDirectory -Filter '*.gbot' -File -Recurse
}
Assert-Contract ($documents.Count -gt 0) `
    'No repository-controlled GBot compatibility documents were found.'

$scalarFields = @(
    'Author', 'Description', 'BotDelay', 'SkillDelay', 'DropDelay',
    'ExitCombatBeforeRest', 'ExitCombatBeforeQuest', 'ExitCombatBeforeStop',
    'EnablePickup', 'EnableRejection', 'EnablePickupAll', 'EnablePickupAcTagged',
    'EnableRejectAll', 'AutoRelogin', 'RelogDelay', 'RelogRetryUponFailure',
    'WaitForAllSkills', 'WaitForSkill', 'SkipDelayIndexIf',
    'InfiniteAttackRange', 'ProvokeMonsters', 'ProvokeAllMonster', 'Untarget',
    'EnemyMagnet', 'LagKiller', 'HidePlayers', 'SkipCutscenes',
    'DisableAnimations', 'AutoSaveState', 'WalkSpeed', 'RestIfMp', 'RestIfHp',
    'RestMp', 'RestHp', 'RestartUponDeath', 'UnbankOnStart', 'BankOnStop',
    'NotifyItemOnPickup', 'RelogUponQuestFailure', 'RelogUponItemBuyFailure', 'AFK'
)

foreach ($file in $documents) {
    Assert-Contract ($file.Length -le $maximumBytes) `
        'A repository-controlled GBot exceeds the bounded mobile file limit.'
    $document = Get-Content -LiteralPath $file.FullName -Raw |
        ConvertFrom-Json -Depth 100
    Assert-Contract ([string]$document.'$type' -like 'Grimoire.Botting.Configuration,*') `
        'A repository-controlled GBot has an invalid root configuration identity.'
    Assert-Contract ($null -ne $document.Commands -and
        $document.Commands.'$values' -is [Array]) `
        'A repository-controlled GBot has an invalid legacy command-list shape.'
    Assert-Contract ($document.Commands.'$values'.Count -le $maximumCommands) `
        'A repository-controlled GBot exceeds the bounded mobile command limit.'

    $beforeTypes = @(Get-CommandTypeNames -Document $document)
    foreach ($commandType in $beforeTypes) {
        Assert-Contract ($runnerCommands -contains $commandType) `
            'A repository-controlled GBot uses a command not supported by the mobile runner.'
    }

    $roundTrip = $document | ConvertTo-Json -Depth 100 -Compress |
        ConvertFrom-Json -Depth 100
    $afterTypes = @(Get-CommandTypeNames -Document $roundTrip)
    Assert-Contract (($beforeTypes -join "`n") -ceq ($afterTypes -join "`n")) `
        'A GBot JSON round trip changed command identity or ordering.'

    foreach ($field in $scalarFields) {
        $beforeProperty = $document.PSObject.Properties[$field]
        if ($null -eq $beforeProperty) {
            continue
        }
        $afterProperty = $roundTrip.PSObject.Properties[$field]
        Assert-Contract ($null -ne $afterProperty -and
            ([string]$beforeProperty.Value -ceq [string]$afterProperty.Value)) `
            'A GBot JSON round trip changed a desktop configuration field.'
    }
}

Assert-Contract (($runnerSource -match 'default:') -and
    ($runnerSource -match 'this\.stop\("UNSUPPORTED COMMAND " \+ kind\.toUpperCase\(\)\)') -and
    ($runnerSource -notmatch 'getDefinitionByName|ApplicationDomain')) `
    'Unknown mobile commands must remain fail-closed and data-only.'
Assert-Contract (($runnerSource -match 'restartCommandLoop\(\)') -and
    ($runnerSource -match 'activeCommandIndex') -and
    ($runnerSource -match 'notifyStateChanged\(\)')) `
    'Looping and active-action progression contracts are missing from the mobile runner.'

Write-Host 'Mobile GBot compatibility suite passed.'
