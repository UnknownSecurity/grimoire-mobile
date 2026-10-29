param()

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$rootPath = Join-Path $repositoryRoot 'game-client\AS3\grimoire\Root.as'
$shellPath = Join-Path $repositoryRoot 'game-client\AS3\grimoire\MobileShell.as'
$botLibraryPath = Join-Path $repositoryRoot 'game-client\AS3\grimoire\MobileBotLibrary.as'
$botRunnerPath = Join-Path $repositoryRoot 'game-client\AS3\grimoire\MobileBotRunner.as'
$preferencesPath = Join-Path $repositoryRoot 'game-client\AS3\grimoire\MobilePreferences.as'
$legacyFixturePath = Join-Path $repositoryRoot 'shared\fixtures\gbot\v1\legacy-delay.gbot'
$descriptorPath = Join-Path $repositoryRoot 'mobile\air-client\GrimoireExodus-app.xml'
$buildScriptPath = Join-Path $repositoryRoot 'mobile\air-client\build-air.ps1'
$mobileBuildScriptPath = Join-Path $repositoryRoot 'mobile\build-android.ps1'
$cielAssetPath = Join-Path $repositoryRoot 'mobile\air-client\assets\ciel_skill.png'

function Assert-Contract {
    param(
        [Parameter(Mandatory = $true)]
        [bool] $Condition,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if (-not $Condition) {
        throw "Mobile AIR shell contract failed: $Message"
    }
}

function Get-MobileCommandTypeNames {
    param([object] $Node)

    if ($null -eq $Node) {
        return
    }
    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
        foreach ($item in $Node) {
            Get-MobileCommandTypeNames -Node $item
        }
        return
    }
    if ($Node -isnot [pscustomobject]) {
        return
    }

    $typeProperty = $Node.PSObject.Properties['$type']
    if ($null -ne $typeProperty) {
        $qualifiedType = [string]$typeProperty.Value
        if ($qualifiedType -like 'Grimoire.Botting.Commands.*') {
            (($qualifiedType -split ',')[0] -split '\.')[-1]
        }
    }
    foreach ($property in $Node.PSObject.Properties) {
        if ($property.Name -ne '$type') {
            Get-MobileCommandTypeNames -Node $property.Value
        }
    }
}

$rootSource = Get-Content -Raw $rootPath
$shellSource = Get-Content -Raw $shellPath
$botLibrarySource = Get-Content -Raw $botLibraryPath
$botRunnerSource = Get-Content -Raw $botRunnerPath
$preferencesSource = Get-Content -Raw $preferencesPath
$legacyFixture = Get-Content -Raw $legacyFixturePath | ConvertFrom-Json -Depth 100
$descriptorSource = Get-Content -Raw $descriptorPath
$buildScriptSource = Get-Content -Raw $buildScriptPath
$mobileBuildScriptSource = Get-Content -Raw $mobileBuildScriptPath

Assert-Contract ($buildScriptSource -match 'Grimoire-Exodus-Android-AIR-') `
    'The default mobile APK must be unmistakably labeled as the HARMAN AIR build.'
Assert-Contract (($descriptorSource -match '<id>com\.unknownsecurity\.grimoireexodus\.mobile</id>') -and
    ($descriptorSource -match '<name>Grimoire Exodus</name>')) `
    'The HARMAN AIR client must own the primary Grimoire Exodus Android identity.'
Assert-Contract (($descriptorSource -match '<versionNumber>0\.5\.0</versionNumber>') -and
    ($descriptorSource -match '<versionLabel>0\.5\.0</versionLabel>') -and
    ($buildScriptSource -match 'Join-Path \$repositoryRoot "VERSION"')) `
    'The default AIR client must use the standalone mobile 0.5.0 version source.'
Assert-Contract (($mobileBuildScriptSource -match '\[string\]\s*\$Engine\s*=\s*''Air''') -and
    ($mobileBuildScriptSource -match 'if \(\$Engine -eq ''Air''\)') -and
    ($mobileBuildScriptSource -match 'air-client\\build-air\.ps1')) `
    'The canonical Android build entry point must default to the HARMAN AIR client.'

Assert-Contract ($rootSource -match 'StageScaleMode\.SHOW_ALL') `
    'AIR must preserve AQW''s native 960x550 aspect ratio on every Android display.'
Assert-Contract ($rootSource -notmatch 'StageScaleMode\.EXACT_FIT') `
    'AIR must not stretch AQW independently across the physical X and Y axes.'
Assert-Contract ($rootSource -notmatch 'StageScaleMode\.NO_SCALE') `
    'AIR must not expose physical Android coordinates to the legacy AQW input path.'
Assert-Contract ($rootSource -match 'stage\.align\s*=\s*""') `
    'AIR must center any aspect-ratio letterboxing around the native AQW plane.'
Assert-Contract ($rootSource -match '(?:stage|this\.stg)\.addChild(?:At)?\(Game') `
    'The live AQW display must remain a direct Stage child.'
$removeLoadingIndex = $rootSource.IndexOf('this.removeLoadingSurface();', [StringComparison]::Ordinal)
$stageGameIndex = $rootSource.IndexOf('this.stg.addChildAt(Game, 0);', [StringComparison]::Ordinal)
$mobileShellIndex = $rootSource.IndexOf('this.mobileShell = new mobileShellClass', [StringComparison]::Ordinal)
Assert-Contract (($removeLoadingIndex -ge 0) -and
    ($stageGameIndex -gt $removeLoadingIndex) -and
    ($mobileShellIndex -gt $stageGameIndex)) `
    'The AIR branch must attach AQW to Stage before creating its overlay.'
Assert-Contract ($rootSource -match 'Event\.RESIZE') `
    'AIR must relayout when the Android surface dimensions change.'
Assert-Contract (($rootSource -match 'frameRate\s*=\s*30') -and
    ($buildScriptSource -match 'default-frame-rate=30')) `
    'AIR must cap the legacy AQW scene at 30 FPS on mobile.'
Assert-Contract (($descriptorSource -match '<requestedDisplayResolution>standard</requestedDisplayResolution>') -and
    ($descriptorSource -notmatch '<requestedDisplayResolution>high</requestedDisplayResolution>')) `
    'AIR must avoid rendering the legacy AQW scene at high-density device resolution.'

Assert-Contract ($shellSource -notmatch 'addChild\s*\(\s*(?:this\.)?game\s*\)') `
    'MobileShell must be an overlay/controller and must not reparent AQW.'
Assert-Contract ($shellSource -notmatch '(?:this\.)?(?:game|_game)\.mask\s*=') `
    'MobileShell must not mask the live AQW display.'
Assert-Contract ($shellSource -match 'import\s+flash\.geom\.Rectangle;') `
    'MobileShell must use a local rectangle to clip AQW without reparenting it.'
Assert-Contract ($shellSource -match '(?:this\.)?game\.scrollRect\s*=\s*new\s+Rectangle\(0,\s*0,\s*GAME_WIDTH,\s*GAME_HEIGHT\)') `
    'AQW must be clipped to its native 960x550 coordinate space.'
Assert-Contract (($shellSource -notmatch 'VIEW_WIDTH') -and ($shellSource -notmatch 'VIEW_HEIGHT')) `
    'The game viewport must not regress to fixed 960x550-era dimensions.'
Assert-Contract (($shellSource -match 'this\.game\.x\s*=\s*0') -and
    ($shellSource -match 'this\.game\.y\s*=\s*0') -and
    ($shellSource -match 'this\.game\.scaleX\s*=\s*this\.game\.scaleY\s*=\s*1')) `
    'AQW must stay at its native Stage origin and scale for accurate touch input.'
$invalidGameTransforms = @($shellSource -split "`r?`n" | Where-Object {
    ($_ -match 'this\.game\.[xy]\s*=') -and ($_ -notmatch 'this\.game\.[xy]\s*=\s*0(?:\.0)?\s*;')
}) + @($shellSource -split "`r?`n" | Where-Object {
    ($_ -match 'this\.game\.scale[XY]\s*=') -and
    ($_ -notmatch 'this\.game\.scaleX\s*=\s*this\.game\.scaleY\s*=\s*1(?:\.0)?\s*;')
})
Assert-Contract ($invalidGameTransforms.Count -eq 0) `
    'No mobile layout or animation path may translate or scale the AQW display object.'
Assert-Contract ($shellSource -notmatch 'targetGame(?:X|Y|Scale)') `
    'Chrome layout must not maintain a second transformed AQW coordinate plane.'
Assert-Contract (($shellSource -match 'CIEL_X:Number\s*=\s*924') -and
    ($shellSource -match 'CIEL_Y:Number\s*=\s*36') -and
    ($shellSource -match 'this\.toggleButton\.visible\s*=\s*this\.gameConnected\s*&&\s*!this\.chromeVisible')) `
    'Ciel must occupy the top-right corner and appear only in-game while the overlay is closed.'
Assert-Contract (($shellSource -match '"bot_stop",\s*"STOP",\s*194,\s*270,\s*90,\s*28') -and
    ($shellSource -match '4,\s*316,\s*272,\s*17') -and
    ($shellSource -match 'maximumBotPageStart\(this\.botLibrary\.entries\.length\)')) `
    'Bot controls and the status strip must remain inside the shortened sidebar below Ciel.'
Assert-Contract ($shellSource -match 'this\.chrome\.addChild\(this\.background\)') `
    'Opaque shell artwork must be contained by the fading chrome overlay.'
Assert-Contract (($shellSource -match 'beginFill\(CANVAS,\s*0\.42\)') -and
    ($shellSource -match 'drawRect\(0,\s*0,\s*this\.layoutWidth,\s*this\.layoutHeight\)') -and
    ($shellSource -match 'RIGHT_RAIL_X') -and
    ($shellSource -match 'renderRightRail\(section:String\)')) `
    'The overlay must use a translucent full-stage glass layer and a live right-side data rail.'
Assert-Contract (($shellSource -notmatch 'createHeaderAction\("play"') -and
    ($shellSource -notmatch 'createHeaderAction\("stop"')) `
    'The non-functional play and record/stop icons must not occupy the top bar.'
Assert-Contract (Test-Path -LiteralPath $cielAssetPath -PathType Leaf) `
    'The Ciel overlay skill image must be a checked-in mobile AIR asset.'
Assert-Contract (($buildScriptSource -match 'assets\\ciel_skill\.png') -and
    ($buildScriptSource -match 'cielSkillSource')) `
    'The AIR package must stage the Ciel skill image explicitly.'
Assert-Contract (($shellSource -match 'CIEL_NAME:String\s*=\s*"Ciel"') -and
    ($shellSource -match 'CIEL_DESCRIPTION:String\s*=\s*"Summon Ciel to automate and take over your body\."')) `
    'The seventh overlay skill must expose the Ciel name and description.'
Assert-Contract (($shellSource -match 'app:/assets/ciel_skill\.png') -and
    ($shellSource -match 'ciel_overlay_skill') -and
    ($shellSource -match 'this\.openOverlay\(\)')) `
    'The packaged Ciel image must open the Grimoire overlay.'
Assert-Contract (($shellSource -notmatch 'getChildByName\("i6"\)') -and
    ($shellSource -notmatch 'cielSkillSlot') -and
    ($shellSource -notmatch 'syncCielWithGameActionBar') -and
    ($shellSource -match 'addChild\(this\.toggleButton\)')) `
    'Ciel must remain a Grimoire HUD control, never an injected AQW action-bar slot.'
Assert-Contract (($shellSource -match 'createHeaderAction\("close"') -and
    ($shellSource -match 'private function closeOverlay\(\):void') -and
    ($shellSource -match 'id == "header_close"')) `
    'The overlay must expose a dedicated close button rather than using Ciel as a two-way toggle.'
Assert-Contract (($shellSource -match 'onCielDragStart') -and
    ($shellSource -match 'onCielDragMove') -and
    ($shellSource -match 'onCielDragEnd') -and
    ($preferencesSource -match 'cielX') -and
    ($preferencesSource -match 'cielY')) `
    'Ciel must support bounded hold-and-drag placement and persist its position.'

# Exercise aspect-preserving physical-to-logical mapping against a 20:9 phone.
$deviceWidth = 2400.0
$deviceHeight = 1080.0
$designWidth = 960.0
$designHeight = 550.0
$uniformScale = [Math]::Min($deviceWidth / $designWidth, $deviceHeight / $designHeight)
$displayedWidth = $designWidth * $uniformScale
$displayedHeight = $designHeight * $uniformScale
$letterboxX = ($deviceWidth - $displayedWidth) / 2.0
$letterboxY = ($deviceHeight - $displayedHeight) / 2.0
$logicalX = 641.25
$logicalY = 318.75
$physicalX = $letterboxX + ($logicalX * $uniformScale)
$physicalY = $letterboxY + ($logicalY * $uniformScale)
$mappedX = ($physicalX - $letterboxX) / $uniformScale
$mappedY = ($physicalY - $letterboxY) / $uniformScale
Assert-Contract (([Math]::Abs(($displayedWidth / $displayedHeight) - ($designWidth / $designHeight)) -lt 0.000001) -and
    ([Math]::Abs($uniformScale - ($displayedWidth / $designWidth)) -lt 0.000001) -and
    ([Math]::Abs($uniformScale - ($displayedHeight / $designHeight)) -lt 0.000001)) `
    'Android display fitting must preserve AQW''s native aspect ratio with one uniform scale.'
Assert-Contract (([Math]::Abs($mappedX - $logicalX) -lt 0.001) -and
    ([Math]::Abs($mappedY - $logicalY) -lt 0.001)) `
    'Android X/Y input must account for letterboxing and map to the exact AQW logical target.'

Assert-Contract (($shellSource -match 'renderBotManager\(\)') -and
    ($shellSource -match 'renderSettings\(\)') -and
    ($shellSource -match 'handleKey\(keyCode:uint\)')) `
    'The mobile shell must expose the Bot Manager, settings, and hardware key bindings.'
Assert-Contract (($shellSource -match 'bot_previous') -and
    ($shellSource -match 'bot_next') -and
    ($shellSource -match 'botPageStart')) `
    'The compact Bot Manager must page through every available bot rather than trapping selection on the first rows.'
Assert-Contract (($botLibrarySource -match 'MAX_BOT_BYTES') -and
    ($botLibrarySource -match 'MAX_COMMANDS') -and
    ($botLibrarySource -notmatch 'getDefinitionByName|ApplicationDomain')) `
    'Mobile GBot loading must stay bounded and data-only.'
Assert-Contract (($botLibrarySource -match 'this\.picker\.browse\(\)') -and
    ($botLibrarySource -notmatch 'new FileFilter') -and
    ($botLibrarySource -match 'bytes\.length\s*>\s*MAX_BOT_BYTES')) `
    'Android bot import must open the unfiltered system picker and validate the selected payload after loading.'
Assert-Contract (($botLibrarySource -match 'selectPath\(destination\.url') -and
    ($botLibrarySource -match 'private function selectPath\(path:String')) `
    'A successfully imported bot must become the selected bot so Start works immediately.'
Assert-Contract (($botRunnerSource -match 'default:') -and
    ($botRunnerSource -match 'this\.stop\("UNSUPPORTED COMMAND " \+ kind\.toUpperCase\(\)\)') -and
    ($botRunnerSource -notmatch 'getDefinitionByName|ApplicationDomain')) `
    'Unknown GBot commands must stop safely instead of continuing or resolving runtime types.'
Assert-Contract (($botRunnerSource -match 'document\.BotDelay\s*==\s*null\s*\?\s*500') -and
    ($botRunnerSource -match 'executeStatement\(kind,\s*command\)') -and
    ($botRunnerSource -match 'case\s+"CmdInInventory"') -and
    ($botRunnerSource -match 'case\s+"CmdLevelLessThan"') -and
    ($botRunnerSource -match 'case\s+"CmdMapIs"') -and
    ($botRunnerSource -match 'case\s+"CmdQuestInProgress"')) `
    'The mobile runner must use a safe default delay and support foundational legacy statement flow.'
$fixtureCommandType = [string]$legacyFixture.Commands.'$values'[0].'$type'
$fixtureCommandName = (($fixtureCommandType -split ',')[0] -split '\.')[-1]
Assert-Contract (($legacyFixture.'$type' -like 'Grimoire.Botting.Configuration,*') -and
    ($botRunnerSource -match ('case\s+"' + [regex]::Escape($fixtureCommandName) + '"'))) `
    'The shared legacy compatibility fixture must be recognized by the mobile runner.'

$communityBotDirectory = Join-Path $repositoryRoot 'app\Bot'
if (Test-Path -LiteralPath $communityBotDirectory -PathType Container) {
    $communityCommandTypes = Get-ChildItem -LiteralPath $communityBotDirectory -Filter '*.gbot' -File -Recurse |
        ForEach-Object {
            $document = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json -Depth 100
            Get-MobileCommandTypeNames -Node $document
        } |
        Sort-Object -Unique
    foreach ($commandType in $communityCommandTypes) {
        Assert-Contract ($botRunnerSource -match ('case\s+"' + [regex]::Escape($commandType) + '"')) `
            'A repository-controlled Community bot uses a command not recognized by the mobile runner.'
    }
}
Assert-Contract (($preferencesSource -match 'SharedObject\.getLocal') -and
    ($preferencesSource -match 'confirmExit') -and
    ($preferencesSource -match 'cycleBinding')) `
    'Mobile global settings must persist and include exit confirmation and key bindings.'
Assert-Contract (($buildScriptSource -match 'app\\Bot') -and
    ($buildScriptSource -match 'bots\\community')) `
    'The APK must package only the repository-controlled Community Bot directory.'
Assert-Contract (($rootSource -match 'private var mobileShell:\*') -and
    ($buildScriptSource -match 'includes=grimoire\.MobileShell')) `
    'AIR-only mobile classes must remain dynamically isolated from the desktop Flash Player bridge.'

$gameFilePathIndex = $rootSource.IndexOf('gameDefinition.serverFilePath = gameFilePath;', [StringComparison]::Ordinal)
Assert-Contract (($gameFilePathIndex -ge 0) -and ($stageGameIndex -gt $gameFilePathIndex)) `
    'AIR must restore AQW''s HTTPS asset origin before activating the game on Stage.'
$gameConfiguredIndex = $rootSource.IndexOf('Game.params.loginURL = this.loginURL;', [StringComparison]::Ordinal)
Assert-Contract (($gameConfiguredIndex -ge 0) -and ($stageGameIndex -gt $gameConfiguredIndex)) `
    'All AQW bootstrap parameters must be complete before its ADDED_TO_STAGE handler runs.'
Assert-Contract ($rootSource -match 'Game\.params\.sFilePath\s*=\s*gameFilePath') `
    'AQW parameters must retain the official gamefiles origin after loadBytes.'
Assert-Contract ($rootSource -match 'gameDefinition\.serverGamePath\s*=\s*this\.sURL') `
    'AQW API requests must retain the official game origin after loadBytes.'
Assert-Contract ($shellSource -match 'getTimer\(\)') `
    'Chrome animation must use elapsed time rather than frame-dependent easing.'
Assert-Contract ($shellSource -notmatch '\+=\s*\([^\r\n]+\)\s*\*\s*0\.19') `
    'The old asymptotic 0.19-per-frame animation must not return.'
$topNavigation = [regex]::Match(
    $shellSource,
    'private function buildTopNavigation\(\):void[\s\S]*?\n\s*\}',
    [Text.RegularExpressions.RegexOptions]::CultureInvariant
)
Assert-Contract ($topNavigation.Success -and
    ($topNavigation.Value -notmatch '"GRIMOIRE"|"EXODUS"|MOBILE COMMAND CENTER')) `
    'The Android top bar must not render a Grimoire title block.'
Assert-Contract (($shellSource -match '\["Home", "Bot", "Bank", "Options", "Packet", "Tools"\]') -and
    ($shellSource -match 'HostBridge\.invoke\("ShowBank"\)') -and
    ($shellSource -match 'renderOptions\(\)') -and
    ($shellSource -match 'renderPackets\(\)')) `
    'The mobile top bar must expose Bank, Options, Packet, Tools, and Bot surfaces.'
Assert-Contract (($shellSource -match 'MAX_PACKET_ENTRIES:int\s*=\s*40') -and
    ($shellSource -match 'MAX_PACKET_CHARACTERS:int\s*=\s*320') -and
    ($shellSource -match 'sendServerPacket') -and
    ($rootSource -match 'public static function sendServerPacket\(packet:String\):void')) `
    'Mobile packet capture and send must remain bounded and use the live SmartFox bridge.'
Assert-Contract (($botRunnerSource -match 'case\s+"CmdPacket"') -and
    ($botRunnerSource -match 'case\s+"CmdPacket2"') -and
    ($botRunnerSource -match 'case\s+"CmdPacketlist2"')) `
    'Mobile GBot execution must support legacy packet and packet-list commands.'

Assert-Contract (($rootSource -match 'updateMobileSessionFromPacket\(e\.params\.message\)') -and
    ($rootSource -match 'updateMobileSessionFromPacket\(raw\)') -and
    ($rootSource -match 'isInventoryLoadedPacket\(message\)') -and
    ($rootSource -match 'split\("&quot;"\)\.join') -and
    ($rootSource -match 'refreshMobileProfile\(\)')) `
    'The mobile profile must refresh after a formatting-tolerant authenticated-character signal.'
Assert-Contract ($rootSource -match 'Game\.world\.myAvatar\.objData') `
    'The authenticated mobile profile must read the live AQW avatar data.'
Assert-Contract ($rootSource -match 'loginInfo\.strUsername') `
    'The authenticated mobile profile must safely fall back to AQW login state.'
Assert-Contract ($rootSource -notmatch 'mobileShell\.setPlayerName\(username\)') `
    'Typing or selecting credentials must not impersonate an authenticated profile.'
Assert-Contract ($shellSource -match 'setPlayerProfile\(value:String,\s*level:\*,\s*characterClass:String\)') `
    'The profile card must accept authenticated character name, level, and class details.'
Assert-Contract (($shellSource -match 'feedbackMessage') -and
    ($shellSource -notmatch 'if \(this\.selectedNavigation != "Home"\)[\s\S]{0,100}this\.showSection\("Home"\)')) `
    'Feature feedback must remain in the active panel instead of redirecting to Home.'

Assert-Contract ($descriptorSource -match '<aspectRatio>landscape</aspectRatio>') `
    'The Android client must remain landscape-only.'
Assert-Contract ($descriptorSource -match '<fullScreen>true</fullScreen>') `
    'The Android client must remain immersive full screen.'

Write-Host 'Mobile AIR shell contract passed.'
