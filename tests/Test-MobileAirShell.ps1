param()

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$rootPath = Join-Path $repositoryRoot 'game-client\AS3\grimoire\Root.as'
$shellPath = Join-Path $repositoryRoot 'game-client\AS3\grimoire\MobileShell.as'
$botLibraryPath = Join-Path $repositoryRoot 'game-client\AS3\grimoire\MobileBotLibrary.as'
$botEditorPath = Join-Path $repositoryRoot 'game-client\AS3\grimoire\MobileBotEditor.as'
$botRunnerPath = Join-Path $repositoryRoot 'game-client\AS3\grimoire\MobileBotRunner.as'
$preferencesPath = Join-Path $repositoryRoot 'game-client\AS3\grimoire\MobilePreferences.as'
$runnerBridgePath = Join-Path $repositoryRoot 'mobile\air-client\runner-service-ane\actionscript\grimoire\nativebridge\AndroidRunnerBridge.as'
$runnerContextPath = Join-Path $repositoryRoot 'mobile\air-client\runner-service-ane\native\src\com\unknownsecurity\grimoireexodus\runner\RunnerContext.java'
$runnerServicePath = Join-Path $repositoryRoot 'mobile\air-client\runner-service-ane\native\src\com\unknownsecurity\grimoireexodus\runner\RunnerForegroundService.java'
$runnerExtensionPath = Join-Path $repositoryRoot 'mobile\air-client\runner-service-ane\extension.xml'
$pickerBridgePath = Join-Path $repositoryRoot 'mobile\air-client\document-picker-ane\actionscript\grimoire\nativebridge\AndroidDocumentPicker.as'
$pickerActivityPath = Join-Path $repositoryRoot 'mobile\air-client\document-picker-ane\native\src\com\unknownsecurity\grimoireexodus\documentpicker\DocumentPickerActivity.java'
$pickerBuildPath = Join-Path $repositoryRoot 'mobile\air-client\document-picker-ane\build-document-picker-ane.ps1'
$pickerExtensionPath = Join-Path $repositoryRoot 'mobile\air-client\document-picker-ane\extension.xml'
$legacyFixturePath = Join-Path $repositoryRoot 'shared\fixtures\gbot\v1\legacy-delay.gbot'
$legacyLevelingFixturePath = Join-Path $repositoryRoot 'shared\fixtures\gbot\v1\legacy-leveling-loop.gbot'
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
$botEditorSource = Get-Content -Raw $botEditorPath
$botRunnerSource = Get-Content -Raw $botRunnerPath
$preferencesSource = Get-Content -Raw $preferencesPath
$runnerBridgeSource = if (Test-Path -LiteralPath $runnerBridgePath) { Get-Content -Raw $runnerBridgePath } else { '' }
$runnerContextSource = if (Test-Path -LiteralPath $runnerContextPath) { Get-Content -Raw $runnerContextPath } else { '' }
$runnerServiceSource = if (Test-Path -LiteralPath $runnerServicePath) { Get-Content -Raw $runnerServicePath } else { '' }
$runnerExtensionSource = if (Test-Path -LiteralPath $runnerExtensionPath) { Get-Content -Raw $runnerExtensionPath } else { '' }
$pickerBridgeSource = Get-Content -Raw $pickerBridgePath
$pickerActivitySource = Get-Content -Raw $pickerActivityPath
$pickerBuildSource = Get-Content -Raw $pickerBuildPath
$pickerExtensionSource = Get-Content -Raw $pickerExtensionPath
$legacyFixture = Get-Content -Raw $legacyFixturePath | ConvertFrom-Json -Depth 100
$legacyLevelingFixture = Get-Content -Raw $legacyLevelingFixturePath | ConvertFrom-Json -Depth 100
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
Assert-Contract (($botLibrarySource -match 'import\s+grimoire\.nativebridge\.AndroidDocumentPicker') -and
    ($botLibrarySource -match 'private\s+var\s+picker:AndroidDocumentPicker') -and
    ($botLibrarySource -match 'this\.picker\.browse\(\)') -and
    ($botLibrarySource -notmatch 'browseForOpen|FileReference|new FileFilter') -and
    ($botLibrarySource -match 'readFileText\(selectedFile\)') -and
    ($botLibrarySource -match 'parseDocument\(raw\)')) `
    'Android bot import must use the native Storage Access Framework bridge and validate the selected file before copying it.'
Assert-Contract (($descriptorSource -match '<extensionID>com\.unknownsecurity\.grimoireexodus\.mobile\.documentpicker</extensionID>') -and
    ($descriptorSource -match 'android:name="com\.unknownsecurity\.grimoireexodus\.documentpicker\.DocumentPickerActivity"') -and
    ($descriptorSource -match 'android:exported="false"')) `
    'The AIR application descriptor must register the private picker Activity and native extension.'
Assert-Contract (($buildScriptSource -match 'build-document-picker-ane\.ps1') -and
    ($buildScriptSource -match 'external-library-path\+=\$documentPickerAne') -and
    ($buildScriptSource -match '-extdir\s+\$extensionDirectory')) `
    'The AIR build must compile against and package the document picker ANE.'
Assert-Contract (($pickerBridgeSource -match 'ExtensionContext\.createExtensionContext') -and
    ($pickerBridgeSource -match 'context\.call\("browse"\)') -and
    ($pickerBridgeSource -match 'StatusEvent\.STATUS')) `
    'The ActionScript picker bridge must use a bounded native extension context.'
Assert-Contract (($pickerActivitySource -match 'Intent\.ACTION_OPEN_DOCUMENT') -and
    ($pickerActivitySource -match 'intent\.setType\("\*/\*"\)') -and
    ($pickerActivitySource -notmatch 'EXTRA_MIME_TYPES') -and
    ($pickerActivitySource -match 'MAX_BYTES\s*=\s*2L\s*\*\s*1024L\s*\*\s*1024L')) `
    'The native picker must show unknown .gbot documents and enforce the mobile size limit after selection.'
Assert-Contract (($pickerExtensionSource -match '<platform name="Android-ARM64">') -and
    ($pickerBuildSource -match '-platform\s+Android-ARM64')) `
    'The document picker ANE must provide the implementation required by the arm64 APK target.'

Assert-Contract ($rootSource -notmatch 'StageScaleMode\.NO_SCALE') `
    'AIR must not expose a second physical coordinate plane that AQW Stage children can bypass.'
Assert-Contract ($rootSource -notmatch 'StageScaleMode\.EXACT_FIT') `
    'AIR must not stretch AQW independently across the physical X and Y axes.'
Assert-Contract ([regex]::Matches($rootSource, 'StageScaleMode\.SHOW_ALL').Count -eq 2) `
    'Desktop and Android must both use the shared Stage transform so AQW map layers and input stay aligned.'
Assert-Contract ($rootSource -notmatch 'layoutMobileGame') `
    'AIR must not apply a child-only transform to AQW while its runtime can add sibling layers to Stage.'
Assert-Contract (($rootSource -notmatch 'Game\.scale[XY]\s*=') -and
    ($rootSource -notmatch 'Game\.[xy]\s*=')) `
    'Root must leave AQW at its native 960x550 coordinates and let SHOW_ALL transform the complete Stage.'
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
Assert-Contract ($shellSource -notmatch 'targetGame(?:X|Y|Scale)') `
    'Chrome layout must not maintain a second transformed AQW coordinate plane.'
Assert-Contract (($shellSource -match 'setViewportSize\(width:Number,\s*height:Number\)') -and
    ($shellSource -match 'this\.interfaceScale\s*=\s*1') -and
    ($shellSource -match 'this\.layoutWidth\s*=\s*DESIGN_WIDTH') -and
    ($shellSource -match 'this\.layoutHeight\s*=\s*DESIGN_HEIGHT') -and
    ($shellSource -match 'this\.rightRailX\s*=\s*RIGHT_RAIL_X')) `
    'MobileShell must share AQW''s logical Stage plane without introducing a second scale.'
Assert-Contract (($shellSource -match 'CIEL_X:Number\s*=\s*924') -and
    ($shellSource -match 'CIEL_Y:Number\s*=\s*36') -and
    ($shellSource -match 'this\.toggleButton\.visible\s*=\s*this\.gameConnected\s*&&\s*!this\.chromeVisible')) `
    'Ciel must occupy the top-right corner and appear only in-game while the overlay is closed.'
Assert-Contract (($shellSource -match '"bot_edit",\s*"EDIT",\s*0,\s*270,\s*90,\s*28') -and
    ($shellSource -match '"bot_command_delete",\s*"DELETE",\s*216,\s*281,\s*68,\s*27') -and
    ($shellSource -match '4,\s*316,\s*272,\s*17') -and
    ($shellSource -match 'maximumBotPageStart\(this\.botLibrary\.entries\.length\)')) `
    'Bot library and editor controls plus the status strip must remain inside the shortened sidebar below Ciel.'
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
Assert-Contract (($botEditorSource -match 'Grimoire\.Botting\.Configuration, Grimoire, Version=1\.0\.0\.0') -and
    ($botEditorSource -match 'System\.Collections\.Generic\.List`1\[\[Grimoire\.Botting\.IBotCommand, Grimoire') -and
    ($botEditorSource -match 'Commands\["\$values"\]') -and
    ($botEditorSource -match 'delete\s+copy\.mobileCommands')) `
    'The mobile editor must preserve the desktop configuration/list identity and remove runtime-only fields when saving.'
Assert-Contract (($botEditorSource -match 'function\s+addTemplate') -and
    ($botEditorSource -match 'function\s+moveSelected') -and
    ($botEditorSource -match 'function\s+duplicateSelected') -and
    ($botEditorSource -match 'function\s+deleteSelected') -and
    ($botEditorSource -match 'function\s+setSelectedProperty') -and
    ($botEditorSource -match 'MAX_COMMANDS')) `
    'The mobile editor must support bounded add, reorder, duplicate, delete, and property editing operations.'
foreach ($requiredTemplate in @('CmdKill', 'CmdKillFor', 'CmdJoin', 'CmdJoin2', 'CmdMoveToCell',
        'CmdUseSkill', 'CmdAcceptQuest2', 'CmdCompleteQuest2', 'CmdDelay', 'CmdGetDrop')) {
    Assert-Contract ($botEditorSource -match [regex]::Escape($requiredTemplate)) `
        "The mobile editor template catalog must include $requiredTemplate."
}
Assert-Contract (($botLibrarySource -match 'function\s+saveEditedBot') -and
    ($botLibrarySource -match 'File\.applicationStorageDirectory\.resolvePath\("Bots"\)') -and
    ($botLibrarySource -match 'this\.parseDocument\(serialized\)') -and
    ($botLibrarySource -match 'entry\.community') -and
    ($botLibrarySource -match 'JSON\.stringify')) `
    'Edited bots must be revalidated and saved only in app-owned storage, with Community bots copied before editing.'
Assert-Contract (($botLibrarySource -match 'function\s+serializeLegacyJson') -and
    ($botLibrarySource -match 'if\s*\(key\s*==\s*"\$type"\)\s*return\s+0') -and
    ($botLibrarySource -match 'keys\.sort\(this\.compareLegacyJsonKeys\)') -and
    ($botLibrarySource -match 'key\s*!=\s*"mobileCommands"')) `
    'Saved GBot JSON must emit Newtonsoft metadata first and omit the mobile runtime command alias.'
Assert-Contract (($shellSource -match 'new\s+MobileBotEditor\(\)') -and
    ($shellSource -match 'bot_new') -and
    ($shellSource -match 'bot_edit') -and
    ($shellSource -match 'bot_add_command') -and
    ($shellSource -match 'bot_save') -and
    ($shellSource -match 'bot_command_duplicate') -and
    ($shellSource -match 'bot_property_')) `
    'The AIR overlay must expose the complete mobile Bot Manager editing workflow.'
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
$mobileSafeLegacyCommands = @(
    'CmdSkillSet', 'CmdClearTemp', 'CmdSetVar', 'CmdUpdateVar', 'CmdGetClassWithVar', 'CmdInt',
    'CmdIntIs', 'CmdIntIsNot', 'CmdIntGreaterThan', 'CmdIntLessThan', 'CmdIntEqualInt', 'CmdIntNotEqualInt',
    'CmdBankList', 'CmdBankSwap', 'CmdBankTransfer', 'CmdBuyByID', 'CmdBuyFast', 'CmdBuyFastByID',
    'CmdLoad', 'CmdLoad2', 'CmdMapItem', 'CmdMapItem2', 'CmdSell', 'CmdUseBoost', 'CmdLoadMapSwf',
    'CmdWhitelist', 'CmdQuestlist', 'CmdEquipped', 'CmdNotEquipped', 'CmdInBank', 'CmdNotInBank',
    'CmdInHouse', 'CmdNotInHouse', 'CmdItemPickupable', 'CmdItemNotPickupable', 'CmdListInInv',
    'CmdAvailableMonstersGreaterThan', 'CmdAvailableMonstersLessThan',
    'CmdVisibleMonstersGreaterThan', 'CmdVisibleMonstersLessThan',
    'CmdMonsterHealthGreaterThan', 'CmdMonsterHealthLessThan',
    'CmdPlayersGreaterThan', 'CmdPlayersLessThan', 'CmdPlayersInCellGreaterThan',
    'CmdPlayersInCellLessThan', 'CmdPlayersInMyCellGreaterThan', 'CmdPlayersInMyCellLessThan',
    'CmdPlayerInRoom', 'CmdPlayerNotInRoom', 'CmdPlayerIsInCell', 'CmdPlayerIsNotInCell',
    'CmdPlayerIsInMyCell', 'CmdPlayerIsNotInMyCell', 'CmdPlayerInCombat', 'CmdPlayerNotInCombat',
    'CmdPlayerEquippedClass', 'CmdPlayerNotEquippedClass',
    'CmdPlayerAuraIsActive', 'CmdPlayerAuraIsNotActive', 'CmdPlayerAuraStringValIs',
    'CmdPlayerAuraStringValIsNot', 'CmdPlayerAuraValIs', 'CmdPlayerAuraValIsNot',
    'CmdPlayerAuraValIsGreaterThan', 'CmdPlayerAuraValIsLessThan',
    'CmdTargetAuraIsActive', 'CmdTargetAuraIsNotActive', 'CmdTargetAuraStringValIs',
    'CmdTargetAuraStringValIsNot', 'CmdTargetAuraValIs', 'CmdTargetAuraValIsNot',
    'CmdTargetAuraValIsGreaterThan', 'CmdTargetAuraValIsLessThan'
)
foreach ($commandType in $mobileSafeLegacyCommands) {
    Assert-Contract ($botRunnerSource -match ('case\s+"' + [regex]::Escape($commandType) + '"')) `
        "The safe mobile legacy command contract is missing $commandType."
}
foreach ($desktopOnlyCommand in @('CmdBuyBack', 'CmdEquipSet', 'CmdLoadBot', 'CmdReturn')) {
    Assert-Contract ($botRunnerSource -notmatch ('case\s+"' + [regex]::Escape($desktopOnlyCommand) + '"')) `
        "$desktopOnlyCommand must remain fail-closed until its desktop-only file/runtime dependency has a bounded mobile contract."
}
$fixtureCommandType = [string]$legacyFixture.Commands.'$values'[0].'$type'
$fixtureCommandName = (($fixtureCommandType -split ',')[0] -split '\.')[-1]
Assert-Contract (($legacyFixture.'$type' -like 'Grimoire.Botting.Configuration,*') -and
    ($botRunnerSource -match ('case\s+"' + [regex]::Escape($fixtureCommandName) + '"'))) `
    'The shared legacy compatibility fixture must be recognized by the mobile runner.'
$levelingCommandTypes = @(Get-MobileCommandTypeNames -Node $legacyLevelingFixture | Sort-Object -Unique)
Assert-Contract (($legacyLevelingFixture.'$type' -like 'Grimoire.Botting.Configuration,*') -and
    ($levelingCommandTypes.Count -gt 0)) `
    'The synthetic looping level-up fixture must retain legacy desktop command identities.'
foreach ($commandType in $levelingCommandTypes) {
    Assert-Contract ($botRunnerSource -match ('case\s+"' + [regex]::Escape($commandType) + '"')) `
        "The looping level-up compatibility fixture uses unsupported command $commandType."
}
Assert-Contract (($botRunnerSource -match 'private\s+function\s+restartCommandLoop\(\):void') -and
    ($botRunnerSource -match 'if\s*\(this\.index\s*>=\s*this\.commands\.length\)\s*\{\s*this\.restartCommandLoop\(\);\s*return;\s*\}') -and
    ($botRunnerSource -notmatch 'this\.stop\("BOT COMPLETED"\)')) `
    'A running legacy farming bot must restart at the first command instead of stopping at the end of the list.'

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
Assert-Contract (($shellSource -match '\["Home", "Bot", "Bank", "Options", "Packet", "Tools", "Runner"\]') -and
    ($shellSource -match 'HostBridge\.invoke\("ShowBank"\)') -and
    ($shellSource -match 'renderOptions\(\)') -and
    ($shellSource -match 'renderPackets\(\)')) `
    'The mobile top bar must expose Bank, Options, Packet, Tools, and Bot surfaces.'
Assert-Contract (($shellSource -match 'this\.sidebarContent\.y\s*=\s*148') -and
    ($shellSource -notmatch 'this\.sidebarContent\.y\s*=\s*208')) `
    'The selected page title must sit directly below the profile card without the former oversized gap.'
Assert-Contract (($shellSource -match '\["Home", "Bot", "Bank", "Options", "Packet", "Tools", "Runner"\]') -and
    ($shellSource -match 'renderRunner\(\)') -and
    ($shellSource -match 'label\s*==\s*"Runner"')) `
    'The AIR overlay must expose the mobile-only Runner surface in the top navigation.'
Assert-Contract (($shellSource -notmatch 'createHeaderAction\("settings"') -and
    ($shellSource -notmatch 'header_settings') -and
    ($shellSource -match 'createHeaderAction\("close",\s*916,\s*21')) `
    'The unused icon beside Close must be absent and the Close icon must be vertically centered.'
Assert-Contract (($preferencesSource -match 'runnerEnabled') -and
    ($preferencesSource -match 'runnerStopNotifications') -and
    ($preferencesSource -match 'runnerKeepCpuAwake') -and
    ($preferencesSource -match 'executeInBackground\s*=\s*this\.runnerEnabled')) `
    'Runner preferences must persist background execution, stop notices, and an opt-in CPU wake mode.'
Assert-Contract (($shellSource -match 'AndroidRunnerBridge') -and
    ($shellSource -match 'runner_enabled') -and
    ($shellSource -match 'runner_stop_notifications') -and
    ($shellSource -match 'runner_keep_cpu_awake') -and
    ($shellSource -match 'runner_battery_settings') -and
    ($shellSource -match 'syncRunnerStatus\(\)')) `
    'The Runner screen must control the native foreground service and expose battery-conscious settings.'
Assert-Contract (($runnerBridgeSource -match 'ExtensionContext\.createExtensionContext') -and
    ($runnerBridgeSource -match 'context\.call\("configure"') -and
    ($runnerBridgeSource -match 'context\.call\("updateStatus"') -and
    ($runnerBridgeSource -match 'context\.call\("openBatterySettings"')) `
    'The ActionScript Runner bridge must expose only the bounded foreground-service operations.'
Assert-Contract (($runnerContextSource -match 'functions\.put\("configure"') -and
    ($runnerContextSource -match 'functions\.put\("updateStatus"') -and
    ($runnerContextSource -match 'functions\.put\("openBatterySettings"') -and
    ($runnerContextSource -notmatch 'botName|account|username|packet|room')) `
    'The native Runner context must not receive private game or bot details.'
Assert-Contract (($runnerServiceSource -match 'startForeground') -and
    ($runnerServiceSource -match 'NotificationChannel') -and
    ($runnerServiceSource -match 'PARTIAL_WAKE_LOCK') -and
    ($runnerServiceSource -match 'keepCpuAwake\s*&&\s*STATE_RUNNING\.equals\(currentState\)') -and
    ($runnerServiceSource -match 'isActive\(previous\)') -and
    ($runnerServiceSource -match 'releaseWakeLock\(\)') -and
    ($runnerServiceSource -match 'notifyStops') -and
    ($runnerServiceSource -match 'STATE_RUNNING') -and
    ($runnerServiceSource -notmatch 'botName|account|username|packet|room')) `
    'The Android foreground service must publish generic status, optional stop notices, and acquire a wake lock only for active runs.'
Assert-Contract (($runnerExtensionSource -match '<platform name="Android-ARM64">') -and
    ($descriptorSource -match '<extensionID>com\.unknownsecurity\.grimoireexodus\.mobile\.runner</extensionID>') -and
    ($descriptorSource -match 'android\.permission\.FOREGROUND_SERVICE') -and
    ($descriptorSource -match 'android\.permission\.POST_NOTIFICATIONS') -and
    ($descriptorSource -match 'android\.permission\.WAKE_LOCK') -and
    ($descriptorSource -match 'android:name="com\.unknownsecurity\.grimoireexodus\.runner\.RunnerForegroundService"') -and
    ($descriptorSource -match 'android:foregroundServiceType="specialUse"')) `
    'The APK descriptor must package the arm64 Runner extension and declare its modern Android service contract.'
Assert-Contract (($buildScriptSource -match 'build-runner-service-ane\.ps1') -and
    ($buildScriptSource -match 'external-library-path\+=\$runnerServiceAne') -and
    ($buildScriptSource -match 'GrimoireRunnerService\.ane')) `
    'The canonical AIR build must compile against and package the Runner foreground-service ANE.'
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
