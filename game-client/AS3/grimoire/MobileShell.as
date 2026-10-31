package grimoire
{
    import flash.desktop.NativeApplication;
    import flash.display.DisplayObject;
    import flash.display.Loader;
    import flash.display.Shape;
    import flash.display.Sprite;
    import flash.display.Stage;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.MouseEvent;
    import flash.events.SecurityErrorEvent;
    import flash.events.TimerEvent;
    import flash.geom.Point;
    import flash.geom.Rectangle;
    import flash.net.navigateToURL;
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.text.TextField;
    import flash.text.TextFieldType;
    import flash.text.TextFormat;
    import flash.text.TextFormatAlign;
    import flash.utils.clearTimeout;
    import flash.utils.getTimer;
    import flash.utils.setTimeout;
    import flash.utils.Timer;
    import grimoire.nativebridge.AndroidRunnerBridge;

    /**
     * AIR-only command-center overlay for the live AQW display. AQW remains a
     * direct Stage child; this class only lays it out and draws controls above
     * it so the desktop ExternalInterface host remains unchanged.
     */
    public final class MobileShell extends Sprite
    {
        public static const DESIGN_WIDTH:Number = 960;
        public static const DESIGN_HEIGHT:Number = 550;

        private static const GAME_WIDTH:Number = 960;
        private static const GAME_HEIGHT:Number = 550;
        private static const MARGIN:Number = 8;
        private static const TOP_HEIGHT:Number = 52;
        private static const SIDEBAR_WIDTH:Number = 332;
        private static const RIGHT_RAIL_X:Number = 348;
        private static const RIGHT_RAIL_WIDTH:Number = 304;
        private static const VIEW_X:Number = 340;
        private static const VIEW_Y:Number = 68;
        private static const TRANSITION_MS:Number = 180;
        private static const SECTION_TRANSITION_MS:Number = 150;
        private static const CIEL_NAME:String = "Ciel";
        private static const CIEL_DESCRIPTION:String = "Summon Ciel to automate and take over your body.";
        private static const CIEL_X:Number = 924;
        private static const CIEL_Y:Number = 36;
        private static const CIEL_ICON_SIZE:Number = 40;
        private static const BOT_PAGE_SIZE:int = 3;
        private static const BOT_COMMAND_PAGE_SIZE:int = 6;
        private static const BOT_TEMPLATE_PAGE_SIZE:int = 6;
        private static const BOT_PROPERTY_PAGE_SIZE:int = 5;
        private static const MAX_PACKET_ENTRIES:int = 40;
        private static const MAX_PACKET_CHARACTERS:int = 320;

        private static const CANVAS:uint = 0x05060B;
        private static const SURFACE:uint = 0x0B0D15;
        private static const ELEVATED:uint = 0x121522;
        private static const CONTROL:uint = 0x191C2C;
        private static const VIOLET:uint = 0x8B5CF6;
        private static const BRIGHT_VIOLET:uint = 0xA855F7;
        private static const PALE_VIOLET:uint = 0xC4B5FD;
        private static const PRIMARY_TEXT:uint = 0xF7F5FF;
        private static const SECONDARY_TEXT:uint = 0x9B96B3;
        private static const DIVIDER:uint = 0x29263B;
        private static const SUCCESS:uint = 0x22C55E;
        private static const DANGER:uint = 0xEF4444;

        private var game:DisplayObject;
        private var background:Shape;
        private var chrome:Sprite;
        private var chromeCanvas:Shape;
        private var sidebarContent:Sprite;
        private var rightRailContent:Sprite;
        private var toggleButton:Sprite;
        private var cielImageFrame:Sprite;
        private var cielSkillLoader:Loader;
        private var cielTooltip:Sprite;
        private var cielTooltipTimer:uint;
        private var cielDragging:Boolean;
        private var cielDragMoved:Boolean;
        private var cielDragOffsetX:Number;
        private var cielDragOffsetY:Number;
        private var cielDragStage:Stage;
        private var closeButton:Sprite;
        private var navigationButtons:Array = [];
        private var selectedNavigation:String = "Home";
        private var playerNameField:TextField;
        private var playerDetailField:TextField;
        private var connectionField:TextField;
        private var emblemLoader:Loader;
        private var chromeVisible:Boolean = true;
        private var preferences:MobilePreferences;
        private var botLibrary:MobileBotLibrary;
        private var botRunner:MobileBotRunner;
        private var runnerBridge:AndroidRunnerBridge;
        private var botEditor:MobileBotEditor;
        private var botMode:String = "library";
        private var botPageStart:int;
        private var botCommandPageStart:int;
        private var botTemplatePageStart:int;
        private var botPropertyPageStart:int;
        private var botFileName:String = "Untitled Bot";
        private var botEditorCreatesCopy:Boolean;
        private var botDiscardArmedAt:int;
        private var settingsPage:int;
        private var resetArmedAt:int;
        private var exitArmedAt:int;
        private var updateLoader:URLLoader;
        private var availableUpdateUrl:String;
        private var gameConnected:Boolean;
        private var lagKillerEnabled:Boolean;
        private var playersHidden:Boolean;
        private var infiniteRangeEnabled:Boolean;
        private var provokeCellEnabled:Boolean;
        private var provokeMapEnabled:Boolean;
        private var enemyMagnetEnabled:Boolean;
        private var skipCutscenesEnabled:Boolean;
        private var disableAnimationsEnabled:Boolean;
        private var untargetSelfEnabled:Boolean;
        private var autoSaveStateEnabled:Boolean;
        private var fastWalkEnabled:Boolean;
        private var optionsPage:int;
        private var optionTimer:Timer;
        private var lastAutoSaveAt:int;
        private var packetCaptureEnabled:Boolean = false;
        private var packetEntries:Array = [];
        private var packetDraft:String = "";
        private var packetInput:TextField;
        private var feedbackMessage:String = "";

        private var targetToggleX:Number;
        private var targetToggleY:Number;
        private var targetChromeAlpha:Number = 1;

        private var layoutWidth:Number = DESIGN_WIDTH;
        private var layoutHeight:Number = DESIGN_HEIGHT;
        private var interfaceScale:Number = 1;
        private var rightRailX:Number = RIGHT_RAIL_X;
        private var viewportX:Number;
        private var viewportY:Number;
        private var viewportWidth:Number = DESIGN_WIDTH;
        private var viewportHeight:Number = DESIGN_HEIGHT;

        private var animationStartedAt:int;
        private var startToggleX:Number;
        private var startToggleY:Number;
        private var startChromeAlpha:Number;
        private var sectionAnimationStartedAt:int;

        public function MobileShell(game:DisplayObject)
        {
            this.game = game;
            // AQW and the overlay share the Stage's SHOW_ALL transform. Do not
            // move or scale the game clip: AQW can add sibling layers to Stage.
            this.game.scrollRect = new Rectangle(0, 0, GAME_WIDTH, GAME_HEIGHT);
            this.preferences = new MobilePreferences();
            this.botLibrary = new MobileBotLibrary();
            this.botRunner = new MobileBotRunner(this.botLibrary.loadKnownDocument);
            this.botEditor = new MobileBotEditor();
            try
            {
                this.runnerBridge = new AndroidRunnerBridge();
            }
            catch (runnerBridgeError:Error)
            {
                this.runnerBridge = null;
            }
            this.botLibrary.addEventListener(MobileBotLibrary.CHANGED, this.onBotLibraryChanged);
            this.botRunner.addEventListener(MobileBotRunner.STATE_CHANGED, this.onBotStateChanged);
            HostBridge.addEventListener(HostBridgeEvent.MESSAGE, this.onHostBridgeMessage);
            NativeApplication.nativeApplication.addEventListener(Event.ACTIVATE,
                this.onApplicationActivate);
            this.optionTimer = new Timer(500);
            this.optionTimer.addEventListener(TimerEvent.TIMER, this.onOptionTimer);
            this.optionTimer.start();
            this.chromeVisible = !this.preferences.startFocused;
            mouseEnabled = false;

            this.chrome = new Sprite();
            this.chrome.mouseEnabled = false;
            addChild(this.chrome);

            this.background = new Shape();
            this.chrome.addChild(this.background);

            this.chromeCanvas = new Shape();
            this.chrome.addChild(this.chromeCanvas);
            this.drawChrome();
            this.buildTopNavigation();
            this.buildProfileCard();

            this.sidebarContent = new Sprite();
            this.sidebarContent.x = 16;
            this.sidebarContent.y = 148;
            this.chrome.addChild(this.sidebarContent);

            this.rightRailContent = new Sprite();
            this.rightRailContent.x = this.rightRailX + 8;
            this.rightRailContent.y = VIEW_Y + 14;
            this.chrome.addChild(this.rightRailContent);
            this.renderSidebar(this.selectedNavigation);
            this.configureRunner();

            this.toggleButton = this.createToggleButton();
            addChild(this.toggleButton);

            this.cielTooltip = this.createCielTooltip();
            addChild(this.cielTooltip);

            addEventListener(Event.REMOVED_FROM_STAGE, this.onRemovedFromStage);

            this.calculateTargets();
            this.applyTargetsImmediately();
        }

        public function setViewportSize(width:Number, height:Number):void
        {
            if (width <= 0 || height <= 0)
            {
                return;
            }

            removeEventListener(Event.ENTER_FRAME, this.animateLayout);
            removeEventListener(Event.ENTER_FRAME, this.animateSection);
            // SHOW_ALL owns the only device transform. Keep the overlay on the
            // same logical 960x550 plane as AQW to preserve visual and pointer
            // alignment across map changes.
            this.interfaceScale = 1;
            this.layoutWidth = DESIGN_WIDTH;
            this.layoutHeight = DESIGN_HEIGHT;
            this.rightRailX = RIGHT_RAIL_X;
            this.scaleX = this.scaleY = 1;
            this.x = 0;
            this.y = 0;

            this.drawChrome();
            if (this.rightRailContent != null)
            {
                this.rightRailContent.x = this.rightRailX + 8;
            }
            if (this.closeButton != null)
            {
                this.closeButton.x = this.layoutWidth - 44;
            }
            this.calculateTargets();
            this.applyTargetsImmediately();
            this.preferences.apply(stage);
        }

        public function handleKey(keyCode:uint):void
        {
            if (keyCode == this.preferences.bindingFor("startBot"))
            {
                this.startSelectedBot();
            }
            else if (keyCode == this.preferences.bindingFor("stopBot"))
            {
                this.botRunner.stop();
            }
            else if (keyCode == this.preferences.bindingFor("toggleChrome"))
            {
                this.toggleChrome();
            }
            else if (keyCode == this.preferences.bindingFor("openSettings"))
            {
                this.showSection("Settings");
            }
            else if (keyCode == this.preferences.bindingFor("lagKiller"))
            {
                this.toggleLagKiller();
            }
            else if (keyCode == this.preferences.bindingFor("hidePlayers"))
            {
                this.toggleHidePlayers();
            }
        }

        public function handleBack():Boolean
        {
            if (!this.chromeVisible)
            {
                this.toggleChrome();
                return true;
            }
            if (!this.preferences.confirmExit)
            {
                return false;
            }
            if (getTimer() - this.exitArmedAt <= 2200)
            {
                return false;
            }
            this.exitArmedAt = getTimer();
            this.botLibraryStatus("PRESS BACK AGAIN TO EXIT");
            return true;
        }

        public function setPlayerProfile(value:String, level:*, characterClass:String):void
        {
            var normalized:String = value == null ? "" : value.replace(/^\s+|\s+$/g, "");
            var normalizedClass:String = characterClass == null ? "" : characterClass.replace(/^\s+|\s+$/g, "");
            var details:Array = [];
            this.playerNameField.text = normalized.length == 0 ? "AQW PLAYER" : normalized.toUpperCase();

            if (level !== null && level !== undefined && String(level).length > 0)
            {
                details.push("LVL " + String(level));
            }
            if (normalizedClass.length > 0)
            {
                details.push(normalizedClass.toUpperCase());
            }
            this.playerDetailField.text = details.length > 0 ? details.join(" / ") : "AUTHENTICATED PLAYER";
        }

        public function resetPlayerProfile():void
        {
            this.playerNameField.text = "AQW PLAYER";
            this.playerDetailField.text = "SIGN IN TO CONNECT";
        }

        public function setConnected(connected:Boolean):void
        {
            this.gameConnected = connected;
            this.connectionField.text = connected ? "CLIENT ONLINE" : "CLIENT DISCONNECTED";
            this.connectionField.textColor = connected ? SUCCESS : DANGER;
            if (!connected && this.botRunner != null && this.botRunner.isRunning)
            {
                this.botRunner.stop("BOT STOPPED: CLIENT DISCONNECTED");
            }
            if (connected)
            {
                this.applyImmediateOptions();
            }
            this.refreshNavigationAvailability();
            this.updateOverlayControls();
        }

        private function drawChrome():void
        {
            this.background.graphics.clear();
            // A low-opacity full-stage glass layer visually owns the whole
            // playable surface while leaving AQW readable underneath. The
            // denser left and right rails carry controls and live bot data.
            this.background.graphics.beginFill(CANVAS, 0.42);
            this.background.graphics.drawRect(0, 0, this.layoutWidth, this.layoutHeight);
            this.background.graphics.endFill();
            this.background.graphics.beginFill(CANVAS, 0.96);
            this.background.graphics.drawRect(0, 0, this.layoutWidth, VIEW_Y);
            this.background.graphics.drawRect(0, VIEW_Y, VIEW_X, this.layoutHeight - VIEW_Y);
            this.background.graphics.drawRect(this.rightRailX, VIEW_Y,
                this.layoutWidth - this.rightRailX, this.layoutHeight - VIEW_Y);
            this.background.graphics.endFill();

            this.chromeCanvas.graphics.clear();
            this.drawPanel(this.chromeCanvas, MARGIN, MARGIN, this.layoutWidth - (MARGIN * 2), TOP_HEIGHT, 14, SURFACE, DIVIDER, 1);
            this.drawPanel(this.chromeCanvas, MARGIN, VIEW_Y, SIDEBAR_WIDTH, this.layoutHeight - VIEW_Y - MARGIN, 14, SURFACE, DIVIDER, 1);
            this.drawPanel(this.chromeCanvas, this.rightRailX, VIEW_Y, RIGHT_RAIL_WIDTH,
                this.layoutHeight - VIEW_Y - MARGIN, 14, SURFACE, DIVIDER, 1);

        }

        private function buildTopNavigation():void
        {
            var labels:Array = ["Home", "Bot", "Bank", "Options", "Packet", "Tools", "Runner"];
            var i:int;
            var button:Sprite;

            for (i = 0; i < labels.length; i++)
            {
                button = this.createNavigationButton(labels[i], 16 + (i * 82), 14, 76, 40);
                this.navigationButtons.push(button);
                this.chrome.addChild(button);
            }

            this.closeButton = this.createHeaderAction("close", 916, 21, false);
            this.chrome.addChild(this.closeButton);
        }

        private function drawBrandMark():void
        {
            var mark:Shape = new Shape();
            mark.x = 20;
            mark.y = 17;
            mark.graphics.lineStyle(2, BRIGHT_VIOLET, 1);
            mark.graphics.moveTo(3, 5);
            mark.graphics.lineTo(18, 0);
            mark.graphics.lineTo(18, 30);
            mark.graphics.lineTo(3, 25);
            mark.graphics.lineTo(3, 5);
            mark.graphics.moveTo(18, 0);
            mark.graphics.lineTo(33, 5);
            mark.graphics.lineTo(33, 25);
            mark.graphics.lineTo(18, 30);
            mark.graphics.moveTo(8, 9);
            mark.graphics.lineTo(14, 7);
            mark.graphics.moveTo(22, 7);
            mark.graphics.lineTo(28, 9);
            this.chrome.addChild(mark);

            this.emblemLoader = new Loader();
            this.emblemLoader.contentLoaderInfo.addEventListener(Event.COMPLETE, this.onEmblemLoaded);
            this.emblemLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, this.onEmblemError);
            this.emblemLoader.load(new URLRequest("app:/assets/grimoire_emblem.png"));
        }

        private function onEmblemLoaded(e:Event):void
        {
            this.emblemLoader.contentLoaderInfo.removeEventListener(Event.COMPLETE, this.onEmblemLoaded);
            this.emblemLoader.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR, this.onEmblemError);
            this.emblemLoader.x = 17;
            this.emblemLoader.y = 12;
            this.emblemLoader.width = 42;
            this.emblemLoader.height = 42;
            this.chrome.addChild(this.emblemLoader);
        }

        private function onEmblemError(e:IOErrorEvent):void
        {
            this.emblemLoader.contentLoaderInfo.removeEventListener(Event.COMPLETE, this.onEmblemLoaded);
            this.emblemLoader.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR, this.onEmblemError);
        }

        private function buildProfileCard():void
        {
            var card:Shape = new Shape();
            this.drawPanel(card, 16, 78, 284, 58, 12, ELEVATED, DIVIDER, 1);
            this.chrome.addChild(card);

            var avatar:Shape = new Shape();
            avatar.x = 25;
            avatar.y = 85;
            avatar.graphics.beginFill(0x241844);
            avatar.graphics.lineStyle(2, VIOLET, 1);
            avatar.graphics.drawCircle(20, 20, 20);
            avatar.graphics.endFill();
            avatar.graphics.lineStyle(2, PALE_VIOLET, 0.9);
            avatar.graphics.drawCircle(20, 15, 6);
            avatar.graphics.moveTo(9, 34);
            avatar.graphics.curveTo(20, 24, 31, 34);
            this.chrome.addChild(avatar);

            this.playerNameField = this.addText(this.chrome, "AQW PLAYER", 72, 84, 218, 20, 12, PRIMARY_TEXT, true);
            this.connectionField = this.addText(this.chrome, "CLIENT DISCONNECTED", 72, 103, 218, 16, 9, DANGER, true);
            this.playerDetailField = this.addText(this.chrome, "SIGN IN TO CONNECT", 72, 119, 218, 14, 8, SECONDARY_TEXT, false);
        }

        private function createNavigationButton(label:String, x:Number, y:Number, width:Number, height:Number):Sprite
        {
            var button:Sprite = new Sprite();
            button.name = "nav_" + label;
            button.x = x;
            button.y = y;
            button.buttonMode = true;
            button.useHandCursor = true;
            button.addEventListener(MouseEvent.CLICK, this.onNavigationClick);

            var backgroundShape:Shape = new Shape();
            backgroundShape.name = "background";
            button.addChild(backgroundShape);
            var labelField:TextField = this.addText(button, label, 0, 22, width, 18, 10, SECONDARY_TEXT, true, "_sans", TextFormatAlign.CENTER);
            labelField.name = "label";

            var icon:Shape = new Shape();
            icon.name = "icon";
            icon.x = width / 2;
            icon.y = 11;
            this.drawNavigationIcon(icon, label, false);
            button.addChild(icon);
            this.redrawNavigationButton(button, label == this.selectedNavigation, width, height);
            return button;
        }

        private function redrawNavigationButton(button:Sprite, selected:Boolean, width:Number, height:Number):void
        {
            var unavailable:Boolean = button.name == "nav_Bank" && !this.gameConnected;
            var backgroundShape:Shape = button.getChildByName("background") as Shape;
            var labelField:TextField = button.getChildByName("label") as TextField;
            var icon:Shape = button.getChildByName("icon") as Shape;
            button.alpha = unavailable ? 0.35 : 1;
            button.mouseEnabled = !unavailable;
            button.buttonMode = !unavailable;
            selected = selected && !unavailable;
            backgroundShape.graphics.clear();
            if (selected)
            {
                backgroundShape.graphics.beginFill(0x241844, 0.92);
                backgroundShape.graphics.lineStyle(1, VIOLET, 0.9);
                backgroundShape.graphics.drawRoundRect(0, 0, width, height, 12, 12);
                backgroundShape.graphics.endFill();
            }
            labelField.textColor = selected ? PALE_VIOLET : SECONDARY_TEXT;
            this.drawNavigationIcon(icon, button.name.substr(4), selected);
        }

        private function refreshNavigationAvailability():void
        {
            for each (var button:Sprite in this.navigationButtons)
            {
                this.redrawNavigationButton(button,
                    button.name == "nav_" + this.selectedNavigation, 76, 40);
            }
        }

        private function drawNavigationIcon(icon:Shape, label:String, selected:Boolean):void
        {
            var color:uint = selected ? BRIGHT_VIOLET : VIOLET;
            icon.graphics.clear();
            icon.graphics.lineStyle(1.8, color, 1);
            if (label == "Home")
            {
                icon.graphics.moveTo(-8, 2);
                icon.graphics.lineTo(0, -5);
                icon.graphics.lineTo(8, 2);
                icon.graphics.moveTo(-6, 1);
                icon.graphics.lineTo(-6, 8);
                icon.graphics.lineTo(6, 8);
                icon.graphics.lineTo(6, 1);
            }
            else if (label == "Bot")
            {
                icon.graphics.drawRoundRect(-7, -5, 14, 13, 4, 4);
                icon.graphics.moveTo(-3, 0);
                icon.graphics.lineTo(-3, 2);
                icon.graphics.moveTo(3, 0);
                icon.graphics.lineTo(3, 2);
                icon.graphics.moveTo(0, -5);
                icon.graphics.lineTo(0, -9);
            }
            else if (label == "Tools")
            {
                icon.graphics.moveTo(-7, -6);
                icon.graphics.lineTo(7, 8);
                icon.graphics.moveTo(5, -7);
                icon.graphics.lineTo(-7, 5);
                icon.graphics.drawCircle(6, -8, 2);
            }
            else if (label == "Packet")
            {
                icon.graphics.moveTo(-8, -4);
                icon.graphics.lineTo(0, -8);
                icon.graphics.lineTo(8, -4);
                icon.graphics.lineTo(0, 0);
                icon.graphics.lineTo(-8, -4);
                icon.graphics.moveTo(-8, 2);
                icon.graphics.lineTo(0, 6);
                icon.graphics.lineTo(8, 2);
            }
            else if (label == "Bank")
            {
                icon.graphics.drawRect(-8, -4, 16, 12);
                icon.graphics.moveTo(-5, -4);
                icon.graphics.lineTo(-3, -8);
                icon.graphics.lineTo(3, -8);
                icon.graphics.lineTo(5, -4);
                icon.graphics.moveTo(-3, 1);
                icon.graphics.lineTo(3, 1);
            }
            else if (label == "Options" || label == "Settings")
            {
                icon.graphics.drawCircle(0, 0, 7);
                icon.graphics.drawCircle(0, 0, 2.5);
                icon.graphics.moveTo(0, -10);
                icon.graphics.lineTo(0, -7);
                icon.graphics.moveTo(0, 7);
                icon.graphics.lineTo(0, 10);
                icon.graphics.moveTo(-10, 0);
                icon.graphics.lineTo(-7, 0);
                icon.graphics.moveTo(7, 0);
                icon.graphics.lineTo(10, 0);
            }
            else if (label == "Runner")
            {
                icon.graphics.drawCircle(0, 0, 8);
                icon.graphics.moveTo(0, -5);
                icon.graphics.lineTo(0, 1);
                icon.graphics.moveTo(-3, 4);
                icon.graphics.lineTo(3, 4);
            }
            else
            {
                icon.graphics.drawCircle(-4, -3, 3);
                icon.graphics.drawCircle(4, -3, 3);
                icon.graphics.drawCircle(0, 5, 3);
                icon.graphics.moveTo(-2, 0);
                icon.graphics.lineTo(-1, 3);
                icon.graphics.moveTo(2, 0);
                icon.graphics.lineTo(1, 3);
            }
        }

        private function createHeaderAction(id:String, x:Number, y:Number, danger:Boolean):Sprite
        {
            var button:Sprite = new Sprite();
            button.name = "header_" + id;
            button.x = x;
            button.y = y;
            button.buttonMode = true;
            button.graphics.beginFill(CONTROL, 1);
            button.graphics.lineStyle(1, DIVIDER, 1);
            button.graphics.drawCircle(13, 13, 13);
            button.graphics.endFill();
            if (id == "play")
            {
                button.graphics.beginFill(PALE_VIOLET);
                button.graphics.moveTo(10, 7);
                button.graphics.lineTo(19, 13);
                button.graphics.lineTo(10, 19);
                button.graphics.lineTo(10, 7);
                button.graphics.endFill();
            }
            else if (id == "stop")
            {
                button.graphics.beginFill(danger ? DANGER : PALE_VIOLET);
                button.graphics.drawCircle(13, 13, 5);
                button.graphics.endFill();
            }
            else if (id == "close")
            {
                button.graphics.lineStyle(2, PALE_VIOLET, 1);
                button.graphics.moveTo(8, 8);
                button.graphics.lineTo(18, 18);
                button.graphics.moveTo(18, 8);
                button.graphics.lineTo(8, 18);
            }
            else
            {
                button.graphics.lineStyle(2, PALE_VIOLET, 1);
                button.graphics.drawCircle(13, 13, 6);
                button.graphics.drawCircle(13, 13, 2);
                button.graphics.moveTo(13, 3);
                button.graphics.lineTo(13, 7);
                button.graphics.moveTo(13, 19);
                button.graphics.lineTo(13, 23);
                button.graphics.moveTo(3, 13);
                button.graphics.lineTo(7, 13);
                button.graphics.moveTo(19, 13);
                button.graphics.lineTo(23, 13);
            }
            button.addEventListener(MouseEvent.CLICK, this.onCommandClick);
            return button;
        }

        private function onNavigationClick(e:MouseEvent):void
        {
            var requested:String = Sprite(e.currentTarget).name.substr(4);
            if (requested == "Bank")
            {
                if (!this.gameConnected)
                {
                    this.botLibraryStatus("SIGN IN BEFORE OPENING THE BANK");
                    return;
                }
                HostBridge.invoke("ShowBank");
                this.closeOverlay();
                return;
            }
            var changed:Boolean = requested != this.selectedNavigation;
            this.selectedNavigation = requested;
            var i:int;
            var button:Sprite;
            for (i = 0; i < this.navigationButtons.length; i++)
            {
                button = this.navigationButtons[i] as Sprite;
                this.redrawNavigationButton(button, button.name == "nav_" + this.selectedNavigation, 76, 40);
            }
            this.renderSidebar(this.selectedNavigation);
            if (changed)
            {
                this.animateSectionTransition();
            }
            HostBridge.call("mobileNavigation", this.selectedNavigation);
        }

        private function showSection(section:String):void
        {
            var changed:Boolean = section != this.selectedNavigation;
            this.selectedNavigation = section;
            if (!this.chromeVisible)
            {
                this.toggleChrome();
            }
            var i:int;
            for (i = 0; i < this.navigationButtons.length; i++)
            {
                var button:Sprite = this.navigationButtons[i] as Sprite;
                this.redrawNavigationButton(button, button.name == "nav_" + section, 76, 40);
            }
            this.renderSidebar(section);
            if (changed)
            {
                this.animateSectionTransition();
            }
        }

        private function animateSectionTransition():void
        {
            removeEventListener(Event.ENTER_FRAME, this.animateSection);
            this.sidebarContent.x = 16;
            this.rightRailContent.x = this.rightRailX + 8;
            this.sidebarContent.alpha = 1;
            this.rightRailContent.alpha = 1;
            if (this.preferences.reducedMotion)
            {
                return;
            }
            this.sectionAnimationStartedAt = getTimer();
            this.sidebarContent.x = 8;
            this.rightRailContent.x = this.rightRailX + 16;
            this.sidebarContent.alpha = 0;
            this.rightRailContent.alpha = 0;
            addEventListener(Event.ENTER_FRAME, this.animateSection);
        }

        private function animateSection(event:Event):void
        {
            var progress:Number = Math.min(1,
                (getTimer() - this.sectionAnimationStartedAt) / SECTION_TRANSITION_MS);
            var eased:Number = 1 - Math.pow(1 - progress, 3);
            this.sidebarContent.x = 8 + (8 * eased);
            this.rightRailContent.x = this.rightRailX + 16 - (8 * eased);
            this.sidebarContent.alpha = eased;
            this.rightRailContent.alpha = eased;
            if (progress >= 1)
            {
                this.sidebarContent.x = 16;
                this.rightRailContent.x = this.rightRailX + 8;
                this.sidebarContent.alpha = 1;
                this.rightRailContent.alpha = 1;
                removeEventListener(Event.ENTER_FRAME, this.animateSection);
            }
        }

        private function renderSidebar(section:String):void
        {
            while (this.sidebarContent.numChildren > 0)
            {
                this.sidebarContent.removeChildAt(0);
            }

            this.addText(this.sidebarContent, section.toUpperCase(), 3, 0, 274, 21, 11, PRIMARY_TEXT, true);
            this.addText(this.sidebarContent, this.sectionSubtitle(section), 3, 19, 274, 23, 9, SECONDARY_TEXT, false);

            if (section == "Home")
            {
                this.drawSectionCard("SESSION", "Authenticated AQW client", 43, ["Bot", "Settings", "Focus"]);
                this.drawSectionCard("QUICK CONTROLS", "Common live actions", 142, ["Start", "Stop", "Pause", "Rest", "Lag killer", "Hide players"]);
            }
            else if (section == "Bot")
            {
                this.renderBotManager();
            }
            else if (section == "Options")
            {
                this.renderOptions();
            }
            else if (section == "Packet")
            {
                this.renderPackets();
            }
            else if (section == "Tools")
            {
                this.drawSectionCard("PLAYER", "Live character controls", 43,
                    ["Rest", "Spawn", "Cancel target", "Cancel attack", "Jump", "Anti AFK"]);
                this.drawSectionCard("CLIENT", "Useful mobile actions", 181,
                    ["Bank", "Lag killer", "Hide players", "FPS 30", "FPS 60", "Settings"]);
            }
            else if (section == "Runner")
            {
                this.renderRunner();
            }
            else
            {
                this.renderSettings();
            }

            if (!this.preferences.hideStatus)
            {
                var statusText:String = this.feedbackMessage.length > 0
                    ? this.feedbackMessage
                    : "AIR  •  AQW LIVE  •  " + this.botRunner.status;
                this.addText(this.sidebarContent, statusText,
                    4, 316, 272, 17, 8, this.botRunner.isRunning ? SUCCESS : SECONDARY_TEXT,
                    true, "_sans", TextFormatAlign.CENTER);
            }
			this.renderRightRail(section);
			this.feedbackMessage = "";
        }

        private function renderRightRail(section:String):void
        {
            while (this.rightRailContent.numChildren > 0)
            {
                this.rightRailContent.removeChildAt(0);
            }

            this.addText(this.rightRailContent, "LIVE CONTEXT", 3, 0, 268, 21,
                11, PRIMARY_TEXT, true);
            this.addText(this.rightRailContent, "HARMAN AIR  •  ORIGINAL AQW RUNTIME",
                3, 19, 268, 18, 8, PALE_VIOLET, true);

            // The Bot editor uses the full rail for metadata and command
            // fields; the library view keeps the live client summary card.
            if (section == "Bot" && this.botMode != "library")
            {
                this.renderBotRightRail();
                return;
            }

            var sessionTitle:String = this.gameConnected ? "CLIENT ONLINE" : "CLIENT DISCONNECTED";
            var player:String = this.playerNameField == null ? "AQW PLAYER" : this.playerNameField.text;
            this.drawRailCard(43, sessionTitle, player,
                this.gameConnected ? SUCCESS : DANGER);

            if (section == "Bot")
            {
                this.renderBotRightRail();
            }
            else if (section == "Packet")
            {
                this.drawRailCard(126, this.packetCaptureEnabled ? "CAPTURE ACTIVE" : "CAPTURE PAUSED",
                    "BOUNDED HISTORY  •  " + this.packetEntries.length + " RECENT EVENTS",
                    this.packetCaptureEnabled ? SUCCESS : SECONDARY_TEXT);
                this.drawRailCard(209, "PACKET SAFETY",
                    "Payload previews and history stay bounded. Sending remains disabled until the AQW session is online.",
                    PALE_VIOLET);
            }
            else if (section == "Options" || section == "Settings")
            {
                this.drawRailCard(126, "DISPLAY PROFILE",
                    this.preferences.frameRate + " FPS  •  " + this.preferences.quality.toUpperCase()
                    + " QUALITY  •  " + (this.preferences.reducedMotion ? "REDUCED MOTION" : "ANIMATED UI"),
                    PALE_VIOLET);
                this.drawRailCard(209, "LIVE OPTIONS",
                    (this.lagKillerEnabled ? "LAG KILLER ON" : "LAG KILLER OFF") + "  •  "
                    + (this.playersHidden ? "PLAYERS HIDDEN" : "PLAYERS VISIBLE"),
                    this.lagKillerEnabled ? SUCCESS : SECONDARY_TEXT);
            }
            else if (section == "Runner")
            {
                this.drawRailCard(126, this.preferences.runnerEnabled
                    ? "BACKGROUND RUNNER ON" : "BACKGROUND RUNNER OFF",
                    this.preferences.runnerEnabled
                        ? "A foreground service keeps the AIR session eligible while another app is open."
                        : "Enable Runner when you want an active bot to continue outside Grimoire.",
                    this.preferences.runnerEnabled ? SUCCESS : SECONDARY_TEXT);
                this.drawRailCard(209, "BOT STATUS", this.runnerStatusLabel(),
                    this.botRunner.isRunning ? SUCCESS : SECONDARY_TEXT);
                this.drawRailCard(292, "BATTERY PROFILE",
                    this.preferences.runnerKeepCpuAwake
                        ? "RELIABLE — CPU wake lock is held only while a bot is running."
                        : "BALANCED — no CPU wake lock; Android may pause work while the device sleeps.",
                    this.preferences.runnerKeepCpuAwake ? PALE_VIOLET : SUCCESS);
            }
            else
            {
                var activeBot:String = this.botLibrary.selectedEntry == null
                    ? "NO BOT SELECTED" : String(this.botLibrary.selectedEntry.name).toUpperCase();
                this.drawRailCard(126, "ACTIVE BOT", this.ellipsize(activeBot, 42), PALE_VIOLET);
                this.drawRailCard(209, "RUNNER STATUS", this.botRunner.status,
                    this.botRunner.isRunning ? SUCCESS : SECONDARY_TEXT);
                this.drawRailCard(292, "CIEL CONTROL",
                    "Close the overlay, then hold and drag Ciel anywhere inside the playable surface.",
                    PALE_VIOLET);
            }
        }

        private function renderBotRightRail():void
        {
            if (this.botMode == "editor")
            {
                this.renderBotPropertyEditor();
                return;
            }
            if (this.botMode == "templates")
            {
                this.drawRailCard(43, "COMMAND TEMPLATES",
                    "Choose a template on the left. It is inserted after the selected command and can be fully edited next.",
                    PALE_VIOLET);
                this.drawRailCard(126, "LEGACY SAFE",
                    "Templates use the desktop Grimoire assembly identity. Unknown commands already in a bot remain untouched.",
                    SUCCESS);
                return;
            }

            var entry:Object = this.botLibrary.selectedEntry;
            var document:Object = this.botLibrary.selectedDocument;
            var botName:String = entry == null ? "NO BOT SELECTED"
                : this.ellipsize(String(entry.name).toUpperCase(), 34);
            var source:String = entry == null ? "IMPORT OR SELECT A GBOT"
                : (entry.community ? "COMMUNITY BOT" : "IMPORTED BOT");
            var commands:Array = document == null ? null : document.mobileCommands as Array;
            var commandCount:int = commands == null ? 0 : commands.length;
            var delay:String = document == null || document.BotDelay == null
                ? "500" : String(Math.max(10, Number(document.BotDelay)));
            this.drawRailCard(126, botName,
                source + "  •  " + commandCount + " COMMANDS  •  " + delay + " MS",
                PALE_VIOLET);

            var runnerState:String = this.botRunner.isPaused ? "PAUSED"
                : (this.botRunner.isRunning ? "RUNNING" : "IDLE");
            var progress:String = this.botRunner.commandCount > 0
                ? this.botRunner.commandPosition + " / " + this.botRunner.commandCount
                : "—";
            this.drawRailCard(209, "BOT " + runnerState,
                this.botRunner.status + "  •  COMMAND " + progress,
                this.botRunner.isRunning ? SUCCESS : SECONDARY_TEXT);

            this.rightRailContent.addChild(this.createAction("bot_start", "START",
                0, 295, 84, 31));
            this.rightRailContent.addChild(this.createAction("bot_pause",
                this.botRunner.isPaused ? "RESUME" : "PAUSE", 92, 295, 84, 31));
            this.rightRailContent.addChild(this.createAction("bot_stop", "STOP",
                184, 295, 84, 31));
        }

        private function renderBotPropertyEditor():void
        {
            var command:Object = this.botEditor.selectedCommand;
            if (command == null)
            {
                this.addText(this.rightRailContent, "BOT DETAILS", 3, 43, 268, 18,
                    10, PALE_VIOLET, true);
                this.addBotInput(this.rightRailContent, "bot_filename", "FILE NAME",
                    this.botFileName, 70, 268);
                this.addBotInput(this.rightRailContent, "bot_metadata_Author", "AUTHOR",
                    this.botEditor.document == null || this.botEditor.document.Author == null
                        ? "" : String(this.botEditor.document.Author), 123, 268);
                this.addBotInput(this.rightRailContent, "bot_metadata_Description", "DESCRIPTION",
                    this.botEditor.document == null || this.botEditor.document.Description == null
                        ? "" : String(this.botEditor.document.Description), 176, 268);
                this.addBotInput(this.rightRailContent, "bot_metadata_BotDelay", "BOT DELAY (MS)",
                    this.botEditor.document == null || this.botEditor.document.BotDelay == null
                        ? "500" : String(this.botEditor.document.BotDelay), 229, 268);
                this.drawRailCard(286, "EDITING NOTES",
                    "Select a command to edit its primitive fields. Nested and unknown data is preserved unchanged when saved.",
                    SECONDARY_TEXT);
                return;
            }

            this.drawRailCard(43, "COMMAND " + (this.botEditor.selectedIndex + 1),
                this.botEditor.commandName(command) + "  •  "
                + (this.botEditor.dirty ? "UNSAVED CHANGES" : "SAVED"),
                this.botEditor.dirty ? PALE_VIOLET : SUCCESS);

            var properties:Array = this.botEditor.selectedPropertyNames();
            var maximumStart:int = this.maximumPageStart(properties.length, BOT_PROPERTY_PAGE_SIZE);
            this.botPropertyPageStart = Math.max(0, Math.min(maximumStart, this.botPropertyPageStart));
            var y:Number = 124;
            for (var i:int = this.botPropertyPageStart;
                i < properties.length && i < this.botPropertyPageStart + BOT_PROPERTY_PAGE_SIZE; i++)
            {
                var property:String = String(properties[i]);
                this.addBotInput(this.rightRailContent, "bot_property_" + property,
                    property.toUpperCase(), command[property] == null ? "" : String(command[property]),
                    y, 268);
                y += 53;
            }
            if (properties.length == 0)
            {
                this.drawRailCard(124, "NO EDITABLE FIELDS",
                    "This command has no primitive properties. Its type and nested data will still be preserved.",
                    SECONDARY_TEXT);
            }

            var firstShown:int = properties.length == 0 ? 0 : this.botPropertyPageStart + 1;
            var lastShown:int = Math.min(properties.length, this.botPropertyPageStart + BOT_PROPERTY_PAGE_SIZE);
            this.rightRailContent.addChild(this.createAction("bot_properties_previous", "‹", 0, 401, 42, 27));
            this.addText(this.rightRailContent,
                properties.length == 0 ? "NO FIELDS" : firstShown + "–" + lastShown + " / " + properties.length,
                49, 406, 170, 17, 8, SECONDARY_TEXT, true, "_sans", TextFormatAlign.CENTER);
            this.rightRailContent.addChild(this.createAction("bot_properties_next", "›", 226, 401, 42, 27));
        }

        private function addBotInput(parent:Sprite, id:String, label:String, value:String,
            y:Number, width:Number):TextField
        {
            this.addText(parent, label, 2, y, width - 4, 16, 8, SECONDARY_TEXT, true);
            var input:TextField = new TextField();
            input.name = id;
            input.type = TextFieldType.INPUT;
            input.defaultTextFormat = new TextFormat("_sans", 9, PRIMARY_TEXT);
            input.background = true;
            input.backgroundColor = CONTROL;
            input.border = true;
            input.borderColor = DIVIDER;
            input.x = 0;
            input.y = y + 18;
            input.width = width;
            input.height = 27;
            input.maxChars = 512;
            input.text = value == null ? "" : value;
            input.addEventListener(Event.CHANGE, this.onBotEditorInputChanged);
            parent.addChild(input);
            return input;
        }

        private function drawRailCard(y:Number, title:String, body:String, accent:uint):void
        {
            var card:Shape = new Shape();
            this.drawPanel(card, 0, y, 268, 74, 11, ELEVATED, accent, 0.8);
            this.rightRailContent.addChild(card);
            this.addText(this.rightRailContent, title, 11, y + 9, 246, 18,
                10, accent, true);
            var bodyField:TextField = this.addText(this.rightRailContent, body,
                11, y + 29, 246, 37, 8, PRIMARY_TEXT, false);
            bodyField.wordWrap = true;
        }

        private function sectionSubtitle(section:String):String
        {
            if (section == "Home") return "Overview and player controls";
            if (section == "Bot") return "Create, edit, and run legacy GBots";
            if (section == "Options") return "Desktop-compatible client options";
            if (section == "Packet") return "Bounded capture, replay, and packet send";
            if (section == "Tools") return "In-game Grimoire utilities";
            if (section == "Runner") return "Background execution and status notices";
            return "General, keys, and advanced";
        }

        private function renderOptions():void
        {
            this.sidebarContent.addChild(this.createAction("options_previous", "‹", 0, 43, 42, 26));
            this.addText(this.sidebarContent, this.optionsPage == 0 ? "COMBAT / DISPLAY" : "SESSION / MOVEMENT",
                49, 47, 186, 17, 8, SECONDARY_TEXT, true, "_sans", TextFormatAlign.CENTER);
            this.sidebarContent.addChild(this.createAction("options_next", "›", 242, 43, 42, 26));

            if (this.optionsPage == 0)
            {
                this.addOptionToggle("option_infinite_range", "INFINITE RANGE", this.infiniteRangeEnabled, 78);
                this.addOptionToggle("option_provoke_cell", "PROVOKE IN CELL", this.provokeCellEnabled, 112);
                this.addOptionToggle("option_provoke_map", "PROVOKE IN MAP", this.provokeMapEnabled, 146);
                this.addOptionToggle("option_enemy_magnet", "TARGET MAGNET", this.enemyMagnetEnabled, 180);
                this.addOptionToggle("option_lag_killer", "LAG KILLER", this.lagKillerEnabled, 214);
                this.addOptionToggle("option_hide_players", "HIDE PLAYERS", this.playersHidden, 248);
                this.addOptionToggle("option_disable_animations", "DISABLE ANIMATIONS", this.disableAnimationsEnabled, 282);
            }
            else
            {
                this.addOptionToggle("option_skip_cutscenes", "SKIP CUTSCENES", this.skipCutscenesEnabled, 78);
                this.addOptionToggle("option_untarget_self", "UNTARGET SELF", this.untargetSelfEnabled, 112);
                this.addOptionToggle("option_auto_save", "AUTO-SAVE STATE", this.autoSaveStateEnabled, 146);
                this.addOptionToggle("option_fast_walk", "FAST WALK SPEED", this.fastWalkEnabled, 180);
                this.sidebarContent.addChild(this.createAction("option_death_ads", "DISABLE DEATH ADS", 0, 224, 284, 34));
                this.sidebarContent.addChild(this.createAction("option_enable_chat", "ENABLE CHAT", 0, 266, 284, 34));
            }
        }

        private function addOptionToggle(id:String, label:String, enabled:Boolean, y:Number):void
        {
            this.addSettingValue(id, label, enabled ? "ON" : "OFF", y,
                enabled ? SUCCESS : SECONDARY_TEXT);
        }

        private function renderPackets():void
        {
            this.addText(this.sidebarContent, packetCaptureEnabled ? "CAPTURE ON" : "CAPTURE OFF",
                3, 43, 86, 18, 8, packetCaptureEnabled ? SUCCESS : SECONDARY_TEXT, true);
            this.sidebarContent.addChild(this.createAction("packet_capture",
                packetCaptureEnabled ? "PAUSE" : "RESUME", 194, 39, 90, 26));

            var packetY:Number = 70;
            var first:int = Math.max(0, this.packetEntries.length - 5);
            for (var i:int = first; i < this.packetEntries.length; i++)
            {
                var entry:Object = this.packetEntries[i];
                var line:String = String(entry.direction) + "  " + this.ellipsize(String(entry.packet), 42);
                this.addText(this.sidebarContent, line, 6, packetY, 272, 18, 8,
                    entry.direction == "OUT" ? PALE_VIOLET : SECONDARY_TEXT, false);
                packetY += 20;
            }
            if (this.packetEntries.length == 0)
            {
                this.addText(this.sidebarContent, "No packets captured yet.", 6, 78, 272, 20,
                    8, SECONDARY_TEXT, false);
            }

            this.packetInput = new TextField();
            this.packetInput.type = TextFieldType.INPUT;
            this.packetInput.defaultTextFormat = new TextFormat("_sans", 9, PRIMARY_TEXT);
            this.packetInput.background = true;
            this.packetInput.backgroundColor = CONTROL;
            this.packetInput.border = true;
            this.packetInput.borderColor = DIVIDER;
            this.packetInput.multiline = true;
            this.packetInput.wordWrap = true;
            this.packetInput.maxChars = 2048;
            this.packetInput.x = 0;
            this.packetInput.y = 177;
            this.packetInput.width = 284;
            this.packetInput.height = 62;
            this.packetInput.text = this.packetDraft;
            this.packetInput.addEventListener(Event.CHANGE, this.onPacketDraftChanged);
            this.sidebarContent.addChild(this.packetInput);

            this.sidebarContent.addChild(this.createAction("packet_use_last", "USE LAST", 0, 247, 90, 27));
            this.sidebarContent.addChild(this.createAction("packet_clear", "CLEAR", 97, 247, 90, 27));
            this.sidebarContent.addChild(this.createAction("packet_send_server", "TO SERVER", 0, 282, 138, 31));
            this.sidebarContent.addChild(this.createAction("packet_send_client", "TO CLIENT", 146, 282, 138, 31));
        }

        private function renderBotManager():void
        {
            if (this.botMode == "editor")
            {
                this.renderBotCommandEditor();
                return;
            }
            if (this.botMode == "templates")
            {
                this.renderBotTemplatePicker();
                return;
            }

            var entry:Object = this.botLibrary.selectedEntry;
            var selectedName:String = entry == null ? "NO BOT SELECTED" : String(entry.name).toUpperCase();
            var source:String = entry == null ? "IMPORT OR SELECT A BOT"
                : (entry.community ? "COMMUNITY" : "IMPORTED");
            this.drawInfoCard(43, selectedName, source + "  •  " + this.botLibrary.status);

            var entries:Array = this.botLibrary.entries;
            var pageSize:int = BOT_PAGE_SIZE;
            var maximumStart:int = this.maximumBotPageStart(entries.length);
            this.botPageStart = Math.max(0, Math.min(maximumStart, this.botPageStart));
            if (this.botLibrary.selectedIndex >= 0
                && (this.botLibrary.selectedIndex < this.botPageStart
                    || this.botLibrary.selectedIndex >= this.botPageStart + pageSize))
            {
                this.botPageStart = Math.min(maximumStart,
                    Math.floor(this.botLibrary.selectedIndex / pageSize) * pageSize);
            }

            var y:Number = 124;
            for (var i:int = this.botPageStart;
                i < entries.length && i < this.botPageStart + pageSize; i++)
            {
                var item:Object = entries[i];
                var marker:String = i == this.botLibrary.selectedIndex ? "● " : "○ ";
                this.sidebarContent.addChild(this.createAction("bot_select_" + i,
                    marker + this.ellipsize(String(item.name), 28), 0, y, 284, 27, TextFormatAlign.LEFT));
                y += 29;
            }
            if (entries.length == 0)
            {
                this.addText(this.sidebarContent, "No bundled or imported bots are available.",
                    8, y + 8, 268, 34, 9, SECONDARY_TEXT, false);
            }

            var firstShown:int = entries.length == 0 ? 0 : this.botPageStart + 1;
            var lastShown:int = Math.min(entries.length, this.botPageStart + pageSize);
            this.sidebarContent.addChild(this.createAction("bot_previous", "‹", 0, 211, 42, 24));
            this.addText(this.sidebarContent,
                entries.length == 0 ? "EMPTY" : firstShown + "–" + lastShown + " / " + entries.length,
                49, 215, 186, 17, 8, SECONDARY_TEXT, true, "_sans", TextFormatAlign.CENTER);
            this.sidebarContent.addChild(this.createAction("bot_next", "›", 242, 211, 42, 24));

            this.sidebarContent.addChild(this.createAction("bot_new", "NEW", 0, 239, 90, 26));
            this.sidebarContent.addChild(this.createAction("bot_import", "IMPORT", 97, 239, 90, 26));
            this.sidebarContent.addChild(this.createAction("bot_refresh", "REFRESH", 194, 239, 90, 26));
            this.sidebarContent.addChild(this.createAction("bot_edit", "EDIT", 0, 270, 90, 28));
            this.sidebarContent.addChild(this.createAction("bot_start", "START", 97, 270, 90, 28));
            this.sidebarContent.addChild(this.createAction("bot_delete", "DELETE", 194, 270, 90, 28));
        }

        private function renderBotCommandEditor():void
        {
            var dirtyLabel:String = this.botEditor.dirty ? "SAVE*" : "SAVED";
            this.sidebarContent.addChild(this.createAction("bot_editor_back", "BACK", 0, 43, 60, 27));
            this.sidebarContent.addChild(this.createAction("bot_metadata", "DETAILS", 65, 43, 70, 27));
            this.sidebarContent.addChild(this.createAction("bot_add_command", "ADD", 140, 43, 65, 27));
            this.sidebarContent.addChild(this.createAction("bot_save", dirtyLabel, 210, 43, 74, 27));

            var commands:Array = this.botEditor.commands;
            var maximumStart:int = this.maximumPageStart(commands.length, BOT_COMMAND_PAGE_SIZE);
            this.botCommandPageStart = Math.max(0, Math.min(maximumStart, this.botCommandPageStart));
            if (this.botEditor.selectedIndex >= 0
                && (this.botEditor.selectedIndex < this.botCommandPageStart
                    || this.botEditor.selectedIndex >= this.botCommandPageStart + BOT_COMMAND_PAGE_SIZE))
            {
                this.botCommandPageStart = Math.min(maximumStart,
                    Math.floor(this.botEditor.selectedIndex / BOT_COMMAND_PAGE_SIZE) * BOT_COMMAND_PAGE_SIZE);
            }

            var y:Number = 77;
            for (var i:int = this.botCommandPageStart;
                i < commands.length && i < this.botCommandPageStart + BOT_COMMAND_PAGE_SIZE; i++)
            {
                var marker:String = i == this.botEditor.selectedIndex ? "● " : "○ ";
                this.sidebarContent.addChild(this.createAction("bot_command_select_" + i,
                    marker + this.ellipsize(this.botEditor.commandSummary(commands[i]), 37),
                    0, y, 284, 27, TextFormatAlign.LEFT));
                y += 29;
            }
            if (commands.length == 0)
            {
                this.drawInfoCard(85, "EMPTY BOT", "Tap ADD to insert a desktop-compatible command template.");
            }

            var firstShown:int = commands.length == 0 ? 0 : this.botCommandPageStart + 1;
            var lastShown:int = Math.min(commands.length, this.botCommandPageStart + BOT_COMMAND_PAGE_SIZE);
            this.sidebarContent.addChild(this.createAction("bot_commands_previous", "‹", 0, 253, 42, 24));
            this.addText(this.sidebarContent,
                commands.length == 0 ? "NO COMMANDS" : firstShown + "–" + lastShown + " / " + commands.length,
                49, 257, 186, 17, 8, SECONDARY_TEXT, true, "_sans", TextFormatAlign.CENTER);
            this.sidebarContent.addChild(this.createAction("bot_commands_next", "›", 242, 253, 42, 24));

            this.sidebarContent.addChild(this.createAction("bot_command_up", "UP", 0, 281, 66, 27));
            this.sidebarContent.addChild(this.createAction("bot_command_down", "DOWN", 72, 281, 66, 27));
            this.sidebarContent.addChild(this.createAction("bot_command_duplicate", "COPY", 144, 281, 66, 27));
            this.sidebarContent.addChild(this.createAction("bot_command_delete", "DELETE", 216, 281, 68, 27));
        }

        private function renderBotTemplatePicker():void
        {
            this.sidebarContent.addChild(this.createAction("bot_templates_back", "BACK", 0, 43, 70, 27));
            this.addText(this.sidebarContent, "ADD COMMAND TEMPLATE", 78, 48, 206, 18,
                9, PALE_VIOLET, true, "_sans", TextFormatAlign.RIGHT);

            var templates:Array = this.botEditor.templates;
            var maximumStart:int = this.maximumPageStart(templates.length, BOT_TEMPLATE_PAGE_SIZE);
            this.botTemplatePageStart = Math.max(0, Math.min(maximumStart, this.botTemplatePageStart));
            var y:Number = 78;
            for (var i:int = this.botTemplatePageStart;
                i < templates.length && i < this.botTemplatePageStart + BOT_TEMPLATE_PAGE_SIZE; i++)
            {
                var label:String = this.botEditor.templateCategory(i).toUpperCase() + "  •  "
                    + this.botEditor.templateLabel(i);
                this.sidebarContent.addChild(this.createAction("bot_template_" + i,
                    this.ellipsize(label, 38), 0, y, 284, 30, TextFormatAlign.LEFT));
                y += 33;
            }

            var firstShown:int = templates.length == 0 ? 0 : this.botTemplatePageStart + 1;
            var lastShown:int = Math.min(templates.length, this.botTemplatePageStart + BOT_TEMPLATE_PAGE_SIZE);
            this.sidebarContent.addChild(this.createAction("bot_templates_previous", "‹", 0, 281, 42, 27));
            this.addText(this.sidebarContent, firstShown + "–" + lastShown + " / " + templates.length,
                49, 286, 186, 17, 8, SECONDARY_TEXT, true, "_sans", TextFormatAlign.CENTER);
            this.sidebarContent.addChild(this.createAction("bot_templates_next", "›", 242, 281, 42, 27));
        }

        private function maximumBotPageStart(count:int):int
        {
            return count <= 0 ? 0
                : Math.floor((count - 1) / BOT_PAGE_SIZE) * BOT_PAGE_SIZE;
        }

        private function maximumPageStart(count:int, pageSize:int):int
        {
            return count <= 0 ? 0 : Math.floor((count - 1) / pageSize) * pageSize;
        }

        private function renderSettings():void
        {
            this.sidebarContent.addChild(this.createAction("settings_general", "GENERAL", 0, 43, 90, 30));
            this.sidebarContent.addChild(this.createAction("settings_keys", "KEYS", 97, 43, 90, 30));
            this.sidebarContent.addChild(this.createAction("settings_advanced", "ADVANCED", 194, 43, 90, 30));

            if (this.settingsPage == 0)
            {
                this.addSettingToggle("pref_start_focused", "START IN FOCUS MODE", this.preferences.startFocused, 80);
                this.addSettingToggle("pref_hide_status", "HIDE STATUS STRIP", this.preferences.hideStatus, 114);
                this.addSettingToggle("pref_confirm_exit", "CONFIRM EXIT", this.preferences.confirmExit, 148);
                this.addSettingToggle("pref_reduced_motion", "REDUCED MOTION", this.preferences.reducedMotion, 182);
                this.addSettingToggle("pref_keep_awake", "KEEP SCREEN AWAKE", this.preferences.keepAwake, 216);
                this.addSettingValue("pref_fps", "FRAME RATE", String(this.preferences.frameRate) + " FPS", 250);
                this.addSettingValue("pref_quality", "RENDER QUALITY", this.preferences.quality.toUpperCase(), 284);
            }
            else if (this.settingsPage == 1)
            {
                this.addBindingRow("startBot", "START BOT", 80);
                this.addBindingRow("stopBot", "STOP BOT", 114);
                this.addBindingRow("toggleChrome", "SHOW / HIDE UI", 148);
                this.addBindingRow("openSettings", "OPEN SETTINGS", 182);
                this.addBindingRow("lagKiller", "LAG KILLER", 216);
                this.addBindingRow("hidePlayers", "HIDE PLAYERS", 250);
                this.addText(this.sidebarContent, "Tap a row to cycle None and F5–F12.",
                    7, 289, 270, 24, 8, SECONDARY_TEXT, false);
            }
            else
            {
                this.sidebarContent.addChild(this.createAction("advanced_credentials", "DELETE CHARACTER INFO", 0, 88, 284, 38));
                this.sidebarContent.addChild(this.createAction("advanced_update", "CHECK FOR UPDATE", 0, 136, 284, 38));
                var resetLabel:String = getTimer() - this.resetArmedAt <= 3000
                    ? "CONFIRM FULL RESET" : "FULL RESET";
                this.sidebarContent.addChild(this.createAction("advanced_reset", resetLabel, 0, 184, 284, 38));
                this.drawInfoCard(235, "MOBILE DATA", "Reset removes mobile settings and session data. Imported and Community bots, plus the desktop installation, are preserved.");
            }
        }

        private function renderRunner():void
        {
            this.addSettingToggle("runner_enabled", "BACKGROUND RUNNER",
                this.preferences.runnerEnabled, 43);
            this.addSettingToggle("runner_stop_notifications", "BOT STOP NOTICES",
                this.preferences.runnerStopNotifications, 77);
            this.addSettingToggle("runner_keep_cpu_awake", "KEEP CPU AWAKE",
                this.preferences.runnerKeepCpuAwake, 111);
            this.sidebarContent.addChild(this.createAction("runner_battery_settings",
                "OPEN ANDROID BATTERY SETTINGS", 0, 153, 284, 34));

            var title:String = this.preferences.runnerEnabled
                ? "RUNNER " + this.runnerStatusLabel() : "RUNNER DISABLED";
            var body:String = this.runnerBridge == null
                ? "The Android notification bridge is unavailable in this build."
                : (this.preferences.runnerKeepCpuAwake
                    ? "Reliable mode uses more battery and holds the CPU awake only during an active bot run."
                    : "Balanced mode uses no CPU wake lock. Switching apps remains supported; device sleep may pause AIR timers.");
            this.drawInfoCard(197, title, body);
        }

        private function addSettingToggle(id:String, label:String, enabled:Boolean, y:Number):void
        {
            this.addSettingValue(id, label, enabled ? "ON" : "OFF", y,
                enabled ? SUCCESS : SECONDARY_TEXT);
        }

        private function addSettingValue(id:String, label:String, value:String, y:Number, valueColor:uint = PALE_VIOLET):void
        {
            var button:Sprite = this.createAction(id, "", 0, y, 284, 30);
            this.addText(button, label, 10, 6, 194, 18, 9, PRIMARY_TEXT, true);
            this.addText(button, value, 203, 6, 70, 18, 9, valueColor, true, "_sans", TextFormatAlign.RIGHT);
            this.sidebarContent.addChild(button);
        }

        private function addBindingRow(id:String, label:String, y:Number):void
        {
            this.addSettingValue("key_" + id, label,
                MobilePreferences.keyLabel(this.preferences.bindingFor(id)), y);
        }

        private function drawSectionCard(title:String, subtitle:String, y:Number, labels:Array):void
        {
            var card:Shape = new Shape();
            var rows:int = Math.ceil(labels.length / 3);
            var height:Number = 52 + (rows * 43);
            this.drawPanel(card, 0, y, 284, height, 11, ELEVATED, DIVIDER, 1);
            this.sidebarContent.addChild(card);
            this.addText(this.sidebarContent, title, 10, y + 8, 264, 18, 10, PALE_VIOLET, true);
            this.addText(this.sidebarContent, subtitle, 10, y + 25, 264, 16, 8, SECONDARY_TEXT, false);

            var i:int;
            var x:Number;
            var buttonY:Number;
            for (i = 0; i < labels.length; i++)
            {
                x = 9 + ((i % 3) * 89);
                buttonY = y + 46 + (Math.floor(i / 3) * 43);
                this.sidebarContent.addChild(this.createSidebarAction(labels[i], x, buttonY, 82, 35));
            }
        }

        private function drawInfoCard(y:Number, title:String, body:String):void
        {
            var card:Shape = new Shape();
            this.drawPanel(card, 0, y, 284, 78, 11, ELEVATED, DIVIDER, 1);
            this.sidebarContent.addChild(card);
            this.addText(this.sidebarContent, title, 10, y + 9, 264, 18, 10, PALE_VIOLET, true);
            var bodyField:TextField = this.addText(this.sidebarContent, body, 10, y + 28, 264, 43, 8, SECONDARY_TEXT, false);
            bodyField.wordWrap = true;
        }

        private function createSidebarAction(label:String, x:Number, y:Number, width:Number, height:Number):Sprite
        {
            var button:Sprite = new Sprite();
            button.name = "command_" + label.toLowerCase();
            button.x = x;
            button.y = y;
            button.buttonMode = true;
            button.useHandCursor = true;
            button.graphics.beginFill(CONTROL, 1);
            button.graphics.lineStyle(1, DIVIDER, 1);
            button.graphics.drawRoundRect(0, 0, width, height, 9, 9);
            button.graphics.endFill();
            this.addText(button, label, 0, 9, width, 18, 9, PRIMARY_TEXT, true, "_sans", TextFormatAlign.CENTER);
            button.addEventListener(MouseEvent.CLICK, this.onCommandClick);
            return button;
        }

        private function createAction(id:String, label:String, x:Number, y:Number,
            width:Number, height:Number, align:String = TextFormatAlign.CENTER):Sprite
        {
            var button:Sprite = new Sprite();
            button.name = id;
            button.x = x;
            button.y = y;
            button.buttonMode = true;
            button.useHandCursor = true;
            button.graphics.beginFill(CONTROL, 0.98);
            button.graphics.lineStyle(1, DIVIDER, 1);
            button.graphics.drawRoundRect(0, 0, width, height, 9, 9);
            button.graphics.endFill();
            this.addText(button, label, align == TextFormatAlign.LEFT ? 10 : 0,
                Math.max(6, (height - 18) / 2), align == TextFormatAlign.LEFT ? width - 20 : width,
                18, 9, PRIMARY_TEXT, true, "_sans", align);
            button.addEventListener(MouseEvent.CLICK, this.onCommandClick);
            return button;
        }

        private function onCommandClick(e:MouseEvent):void
        {
            var id:String = Sprite(e.currentTarget).name;
            if (id == "header_play" || id == "command_start" || id == "bot_start")
            {
                this.startSelectedBot();
            }
            else if (id == "header_stop" || id == "command_stop" || id == "bot_stop")
            {
                this.botRunner.stop();
            }
            else if (id == "command_pause" || id == "bot_pause")
            {
                this.botRunner.togglePause();
            }
            else if (id == "command_settings")
            {
                this.showSection("Settings");
            }
            else if (id == "header_close")
            {
                this.closeOverlay();
            }
            else if (id == "command_bot")
            {
                this.showSection("Bot");
            }
            else if (id == "command_focus")
            {
                this.toggleChrome();
            }
            else if (id == "command_rest")
            {
                HostBridge.invoke("Rest");
            }
            else if (id == "command_spawn")
            {
                HostBridge.invoke("SetSpawnPoint");
            }
            else if (id == "command_cancel target")
            {
                HostBridge.invoke("CancelTarget");
            }
            else if (id == "command_cancel attack")
            {
                HostBridge.invoke("CancelAutoAttack");
            }
            else if (id == "command_lag killer")
            {
                this.toggleLagKiller();
            }
            else if (id == "command_hide players")
            {
                this.toggleHidePlayers();
            }
            else if (id == "command_jump")
            {
                HostBridge.invoke("Jump", "Enter", "Spawn");
            }
            else if (id == "command_anti afk")
            {
                HostBridge.invoke("cancelAfk");
            }
            else if (id == "command_bank")
            {
                HostBridge.invoke("ShowBank");
                this.closeOverlay();
            }
            else if (id == "command_fps 30")
            {
                HostBridge.invoke("SetFPS", 30);
            }
            else if (id == "command_fps 60")
            {
                HostBridge.invoke("SetFPS", 60);
            }
            else if (id == "bot_new")
            {
                this.botEditor.createNew();
                this.botFileName = "Untitled Bot";
                this.botEditorCreatesCopy = true;
                this.botMode = "editor";
                this.botCommandPageStart = 0;
                this.botPropertyPageStart = 0;
                this.renderSidebar("Bot");
            }
            else if (id == "bot_import")
            {
                this.botLibrary.browseForImport();
            }
            else if (id == "bot_refresh")
            {
                this.botLibrary.refresh();
            }
            else if (id == "bot_previous")
            {
                this.botPageStart = Math.max(0, this.botPageStart - BOT_PAGE_SIZE);
                this.renderSidebar("Bot");
            }
            else if (id == "bot_next")
            {
                this.botPageStart = Math.min(this.maximumBotPageStart(this.botLibrary.entries.length),
                    this.botPageStart + BOT_PAGE_SIZE);
                this.renderSidebar("Bot");
            }
            else if (id == "bot_delete")
            {
                this.botLibrary.deleteSelected();
            }
            else if (id == "bot_edit")
            {
                if (this.botLibrary.selectedDocument == null)
                {
                    this.botLibraryStatus("SELECT A BOT BEFORE EDITING");
                }
                else
                {
                    this.botEditor.load(this.botLibrary.selectedDocument);
                    this.botFileName = this.botLibrary.selectedEntry == null
                        ? "Untitled Bot" : String(this.botLibrary.selectedEntry.name);
                    this.botEditorCreatesCopy = false;
                    this.botMode = "editor";
                    this.botCommandPageStart = 0;
                    this.botPropertyPageStart = 0;
                    this.renderSidebar("Bot");
                }
            }
            else if (id == "bot_editor_back")
            {
                if (this.botEditor.dirty && getTimer() - this.botDiscardArmedAt > 3000)
                {
                    this.botDiscardArmedAt = getTimer();
                    this.botLibraryStatus("UNSAVED CHANGES — TAP BACK AGAIN TO LEAVE");
                }
                else
                {
                    this.botMode = "library";
                    this.renderSidebar("Bot");
                }
            }
            else if (id == "bot_templates_back")
            {
                this.botMode = "editor";
                this.renderSidebar("Bot");
            }
            else if (id == "bot_metadata")
            {
                this.botEditor.select(-1);
                this.botPropertyPageStart = 0;
                this.renderSidebar("Bot");
            }
            else if (id == "bot_add_command")
            {
                this.botMode = "templates";
                this.botTemplatePageStart = 0;
                this.renderSidebar("Bot");
            }
            else if (id == "bot_save")
            {
                if (this.botLibrary.saveEditedBot(this.botEditor.exportDocument(),
                    this.botFileName, this.botEditorCreatesCopy))
                {
                    this.botEditor.load(this.botLibrary.selectedDocument);
                    this.botEditor.markSaved();
                    this.botFileName = this.botLibrary.selectedEntry == null
                        ? this.botFileName : String(this.botLibrary.selectedEntry.name);
                    this.botEditorCreatesCopy = false;
                    this.botMode = "editor";
                }
                this.renderSidebar("Bot");
            }
            else if (id.indexOf("bot_command_select_") == 0)
            {
                this.botEditor.select(int(id.substr(19)));
                this.botPropertyPageStart = 0;
                this.renderSidebar("Bot");
            }
            else if (id == "bot_commands_previous")
            {
                this.botCommandPageStart = Math.max(0,
                    this.botCommandPageStart - BOT_COMMAND_PAGE_SIZE);
                this.renderSidebar("Bot");
            }
            else if (id == "bot_commands_next")
            {
                this.botCommandPageStart = Math.min(
                    this.maximumPageStart(this.botEditor.commands.length, BOT_COMMAND_PAGE_SIZE),
                    this.botCommandPageStart + BOT_COMMAND_PAGE_SIZE);
                this.renderSidebar("Bot");
            }
            else if (id == "bot_command_up" || id == "bot_command_down")
            {
                this.botEditor.moveSelected(id == "bot_command_up" ? -1 : 1);
                this.renderSidebar("Bot");
            }
            else if (id == "bot_command_duplicate")
            {
                this.botEditor.duplicateSelected();
                this.renderSidebar("Bot");
            }
            else if (id == "bot_command_delete")
            {
                this.botEditor.deleteSelected();
                this.renderSidebar("Bot");
            }
            else if (id == "bot_templates_previous")
            {
                this.botTemplatePageStart = Math.max(0,
                    this.botTemplatePageStart - BOT_TEMPLATE_PAGE_SIZE);
                this.renderSidebar("Bot");
            }
            else if (id == "bot_templates_next")
            {
                this.botTemplatePageStart = Math.min(
                    this.maximumPageStart(this.botEditor.templates.length, BOT_TEMPLATE_PAGE_SIZE),
                    this.botTemplatePageStart + BOT_TEMPLATE_PAGE_SIZE);
                this.renderSidebar("Bot");
            }
            else if (id.indexOf("bot_template_") == 0)
            {
                if (this.botEditor.addTemplate(int(id.substr(13))))
                {
                    this.botMode = "editor";
                    this.botPropertyPageStart = 0;
                }
                this.renderSidebar("Bot");
            }
            else if (id == "bot_properties_previous")
            {
                this.botPropertyPageStart = Math.max(0,
                    this.botPropertyPageStart - BOT_PROPERTY_PAGE_SIZE);
                this.renderSidebar("Bot");
            }
            else if (id == "bot_properties_next")
            {
                this.botPropertyPageStart = Math.min(
                    this.maximumPageStart(this.botEditor.selectedPropertyNames().length,
                        BOT_PROPERTY_PAGE_SIZE),
                    this.botPropertyPageStart + BOT_PROPERTY_PAGE_SIZE);
                this.renderSidebar("Bot");
            }
            else if (id.indexOf("bot_select_") == 0)
            {
                this.botMode = "library";
                this.botLibrary.select(int(id.substr(11)));
            }
            else if (id == "runner_battery_settings")
            {
                if (this.runnerBridge == null || !this.runnerBridge.openBatterySettings())
                {
                    this.botLibraryStatus("ANDROID BATTERY SETTINGS COULD NOT BE OPENED");
                }
            }
            else if (id.indexOf("runner_") == 0)
            {
                this.toggleRunnerPreference(id);
            }
            else if (id.indexOf("settings_") == 0)
            {
                this.settingsPage = id == "settings_general" ? 0 : (id == "settings_keys" ? 1 : 2);
                this.renderSidebar("Settings");
            }
            else if (id.indexOf("pref_") == 0)
            {
                this.togglePreference(id);
            }
            else if (id.indexOf("key_") == 0)
            {
                this.preferences.cycleBinding(id.substr(4));
                this.renderSidebar("Settings");
            }
            else if (id == "options_previous" || id == "options_next")
            {
                this.optionsPage = this.optionsPage == 0 ? 1 : 0;
                this.renderSidebar("Options");
            }
            else if (id.indexOf("option_") == 0)
            {
                this.toggleClientOption(id);
            }
            else if (id == "packet_capture")
            {
                this.packetCaptureEnabled = !this.packetCaptureEnabled;
                this.renderSidebar("Packet");
            }
            else if (id == "packet_clear")
            {
                this.packetEntries = [];
                this.renderSidebar("Packet");
            }
            else if (id == "packet_use_last")
            {
                if (this.packetEntries.length > 0)
                {
                    this.packetDraft = String(this.packetEntries[this.packetEntries.length - 1].packet);
                }
                this.renderSidebar("Packet");
            }
            else if (id == "packet_send_server")
            {
                this.sendPacket(false);
            }
            else if (id == "packet_send_client")
            {
                this.sendPacket(true);
            }
            else if (id == "advanced_credentials")
            {
                Root.username = null;
                Root.password = null;
                try
                {
                    if (Root.Game != null && Root.Game.mcLogin != null)
                    {
                        if (Root.Game.mcLogin.ni != null) Root.Game.mcLogin.ni.text = "";
                        if (Root.Game.mcLogin.pi != null) Root.Game.mcLogin.pi.text = "";
                    }
                }
                catch (credentialError:Error)
                {
                }
                this.botLibraryStatus("CACHED MOBILE LOGIN FIELDS CLEARED");
            }
            else if (id == "advanced_update")
            {
                if (this.availableUpdateUrl != null)
                {
                    navigateToURL(new URLRequest(this.availableUpdateUrl), "_blank");
                    this.botLibraryStatus("OPENED THE VERIFIED MOBILE RELEASE ASSET");
                }
                else
                {
                    this.checkForUpdate();
                }
            }
            else if (id == "advanced_reset")
            {
                this.fullReset();
            }
            else
            {
                HostBridge.call("mobileCommand", id);
            }
        }

        private function onBotEditorInputChanged(event:Event):void
        {
            var input:TextField = event.currentTarget as TextField;
            if (input == null)
            {
                return;
            }

            var accepted:Boolean = true;
            if (input.name == "bot_filename")
            {
                this.botFileName = input.text;
            }
            else if (input.name.indexOf("bot_metadata_") == 0)
            {
                accepted = this.botEditor.setMetadata(input.name.substr(13), input.text);
            }
            else if (input.name.indexOf("bot_property_") == 0)
            {
                accepted = this.botEditor.setSelectedProperty(input.name.substr(13), input.text);
            }
            input.borderColor = accepted ? DIVIDER : DANGER;
        }

        private function createToggleButton():Sprite
        {
            var button:Sprite = new Sprite();
            button.name = "ciel_overlay_skill";
            button.buttonMode = true;
            button.useHandCursor = true;
            button.mouseChildren = false;
            button.addEventListener(MouseEvent.CLICK, this.onToggleClick);
            button.addEventListener(MouseEvent.MOUSE_DOWN, this.onCielDragStart);
            button.addEventListener(MouseEvent.MOUSE_OVER, this.onCielHint);
            this.drawToggleButton(button);

            this.cielImageFrame = new Sprite();
            this.cielImageFrame.x = -CIEL_ICON_SIZE / 2;
            this.cielImageFrame.y = -CIEL_ICON_SIZE / 2;
            this.cielImageFrame.mouseEnabled = false;
            this.cielImageFrame.scrollRect = new Rectangle(0, 0, CIEL_ICON_SIZE, CIEL_ICON_SIZE);
            this.cielImageFrame.graphics.beginFill(0x17122C, 1);
            this.cielImageFrame.graphics.drawRect(0, 0, CIEL_ICON_SIZE, CIEL_ICON_SIZE);
            this.cielImageFrame.graphics.endFill();
            this.addText(this.cielImageFrame, "C", 0, 7, CIEL_ICON_SIZE, 27,
                19, PALE_VIOLET, true, "Georgia", TextFormatAlign.CENTER);
            button.addChild(this.cielImageFrame);

            this.cielSkillLoader = new Loader();
            this.cielSkillLoader.contentLoaderInfo.addEventListener(Event.COMPLETE, this.onCielSkillLoaded);
            this.cielSkillLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, this.onCielSkillError);
            this.cielImageFrame.addChild(this.cielSkillLoader);
            try
            {
                this.cielSkillLoader.load(new URLRequest("app:/assets/ciel_skill.png"));
            }
            catch (error:Error)
            {
                this.detachCielSkillLoaderListeners();
            }

            this.addText(button, CIEL_NAME.toUpperCase(), -28, 24, 56, 12,
                7, PRIMARY_TEXT, true, "_sans", TextFormatAlign.CENTER);
            return button;
        }

        private function drawToggleButton(button:Sprite):void
        {
            button.graphics.clear();
            button.graphics.beginFill(0x090B13, 0.96);
            button.graphics.lineStyle(2, this.chromeVisible ? BRIGHT_VIOLET : PALE_VIOLET, 1);
            button.graphics.drawRoundRect(-24, -24, 48, 48, 10, 10);
            button.graphics.endFill();
            button.graphics.lineStyle(1, 0xFFFFFF, this.chromeVisible ? 0.34 : 0.18);
            button.graphics.drawRoundRect(-20, -20, 40, 40, 6, 6);
        }

        private function createCielTooltip():Sprite
        {
            var tooltip:Sprite = new Sprite();
            tooltip.x = CIEL_X - 116;
            tooltip.y = CIEL_Y - 88;
            tooltip.mouseEnabled = false;
            tooltip.mouseChildren = false;
            tooltip.visible = false;

            var panel:Shape = new Shape();
            this.drawPanel(panel, 0, 0, 232, 57, 10, SURFACE, BRIGHT_VIOLET, 0.9);
            tooltip.addChild(panel);
            this.addText(tooltip, CIEL_NAME.toUpperCase(), 11, 8, 210, 18,
                11, PALE_VIOLET, true);
            var description:TextField = this.addText(tooltip, CIEL_DESCRIPTION, 11, 27, 210, 22,
                8, PRIMARY_TEXT, false);
            description.wordWrap = true;
            return tooltip;
        }

        private function onCielSkillLoaded(event:Event):void
        {
            this.detachCielSkillLoaderListeners();
            if (this.cielSkillLoader == null || this.cielSkillLoader.content == null)
            {
                return;
            }

            var content:DisplayObject = this.cielSkillLoader.content;
            if (content.width <= 0 || content.height <= 0)
            {
                return;
            }
            var imageScale:Number = Math.max(CIEL_ICON_SIZE / content.width,
                CIEL_ICON_SIZE / content.height);
            this.cielSkillLoader.scaleX = this.cielSkillLoader.scaleY = imageScale;
            this.cielSkillLoader.x = (CIEL_ICON_SIZE - (content.width * imageScale)) / 2;
            this.cielSkillLoader.y = (CIEL_ICON_SIZE - (content.height * imageScale)) / 2;
        }

        private function onCielSkillError(event:IOErrorEvent):void
        {
            this.detachCielSkillLoaderListeners();
        }

        private function detachCielSkillLoaderListeners():void
        {
            if (this.cielSkillLoader == null)
            {
                return;
            }
            this.cielSkillLoader.contentLoaderInfo.removeEventListener(Event.COMPLETE, this.onCielSkillLoaded);
            this.cielSkillLoader.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR, this.onCielSkillError);
        }

        private function onCielHint(event:MouseEvent):void
        {
            if (this.cielTooltip == null || !this.gameConnected || this.chromeVisible)
            {
                return;
            }
            if (this.cielTooltipTimer != 0)
            {
                clearTimeout(this.cielTooltipTimer);
            }
            this.cielTooltip.visible = true;
            this.cielTooltipTimer = setTimeout(this.hideCielTooltip, 1800);
        }

        private function onCielDragStart(event:MouseEvent):void
        {
            if (!this.gameConnected || this.chromeVisible || stage == null)
            {
                return;
            }
            this.cielDragging = true;
            this.cielDragMoved = false;
            var localPointer:Point = globalToLocal(new Point(event.stageX, event.stageY));
            this.cielDragOffsetX = localPointer.x - this.toggleButton.x;
            this.cielDragOffsetY = localPointer.y - this.toggleButton.y;
            this.cielDragStage = stage;
            this.hideCielTooltip();
            this.cielDragStage.addEventListener(MouseEvent.MOUSE_MOVE, this.onCielDragMove, true, 1000);
            this.cielDragStage.addEventListener(MouseEvent.MOUSE_UP, this.onCielDragEnd, true, 1000);
            event.stopPropagation();
        }

        private function onCielDragMove(event:MouseEvent):void
        {
            if (!this.cielDragging)
            {
                return;
            }
            var localPointer:Point = globalToLocal(new Point(event.stageX, event.stageY));
            var nextX:Number = Math.max(28, Math.min(this.layoutWidth - 28,
                localPointer.x - this.cielDragOffsetX));
            var nextY:Number = Math.max(28, Math.min(this.layoutHeight - 28,
                localPointer.y - this.cielDragOffsetY));
            if (Math.abs(nextX - this.toggleButton.x) > 3
                || Math.abs(nextY - this.toggleButton.y) > 3)
            {
                this.cielDragMoved = true;
            }
            this.toggleButton.x = nextX;
            this.toggleButton.y = nextY;
            this.targetToggleX = nextX;
            this.targetToggleY = nextY;
            this.positionCielTooltip();
            event.updateAfterEvent();
        }

        private function onCielDragEnd(event:MouseEvent):void
        {
            if (!this.cielDragging)
            {
                return;
            }
            this.cielDragging = false;
            if (this.cielDragStage != null)
            {
                this.cielDragStage.removeEventListener(MouseEvent.MOUSE_MOVE, this.onCielDragMove, true);
                this.cielDragStage.removeEventListener(MouseEvent.MOUSE_UP, this.onCielDragEnd, true);
            }
            if (this.cielDragMoved)
            {
                this.preferences.cielX = this.toggleButton.x;
                this.preferences.cielY = this.toggleButton.y;
                this.preferences.save();
                event.stopPropagation();
            }
            this.cielDragStage = null;
        }

        private function hideCielTooltip():void
        {
            this.cielTooltipTimer = 0;
            if (this.cielTooltip != null)
            {
                this.cielTooltip.visible = false;
            }
        }

        private function positionCielTooltip():void
        {
            var anchor:DisplayObject = this.toggleButton as DisplayObject;
            if (anchor == null || anchor.stage == null || this.cielTooltip == null)
            {
                return;
            }
            var anchorBounds:Rectangle = anchor.getBounds(anchor);
            var globalCenter:Point = anchor.localToGlobal(new Point(
                anchorBounds.x + (anchorBounds.width / 2),
                anchorBounds.y + (anchorBounds.height / 2)));
            var localCenter:Point = globalToLocal(globalCenter);
            this.cielTooltip.x = Math.max(8, Math.min(this.layoutWidth - 240, localCenter.x - 116));
            this.cielTooltip.y = Math.max(8, localCenter.y - 88);
        }

        private function onRemovedFromStage(event:Event):void
        {
            removeEventListener(Event.REMOVED_FROM_STAGE, this.onRemovedFromStage);
            removeEventListener(Event.ENTER_FRAME, this.animateLayout);
            removeEventListener(Event.ENTER_FRAME, this.animateSection);
            HostBridge.removeEventListener(HostBridgeEvent.MESSAGE, this.onHostBridgeMessage);
            NativeApplication.nativeApplication.removeEventListener(Event.ACTIVATE,
                this.onApplicationActivate);
            if (this.optionTimer != null)
            {
                this.optionTimer.stop();
                this.optionTimer.removeEventListener(TimerEvent.TIMER, this.onOptionTimer);
            }
            if (this.cielTooltipTimer != 0)
            {
                clearTimeout(this.cielTooltipTimer);
                this.cielTooltipTimer = 0;
            }
            this.detachCielSkillLoaderListeners();
            if (this.cielDragStage != null)
            {
                this.cielDragStage.removeEventListener(MouseEvent.MOUSE_MOVE, this.onCielDragMove, true);
                this.cielDragStage.removeEventListener(MouseEvent.MOUSE_UP, this.onCielDragEnd, true);
                this.cielDragStage = null;
            }
            if (this.toggleButton != null && this.toggleButton.parent != null)
            {
                this.toggleButton.parent.removeChild(this.toggleButton);
            }
            if (this.runnerBridge != null)
            {
                this.runnerBridge.dispose();
                this.runnerBridge = null;
            }
        }

        private function onHostBridgeMessage(event:HostBridgeEvent):void
        {
            if (!this.packetCaptureEnabled || event == null || event.arguments.length == 0)
            {
                return;
            }
            if (event.method != "packetFromClient" && event.method != "packetFromServer")
            {
                return;
            }
            var packet:String = String(event.arguments[0]);
            if (packet.length > MAX_PACKET_CHARACTERS)
            {
                packet = packet.substr(0, MAX_PACKET_CHARACTERS) + "…";
            }
            this.packetEntries.push({
                direction: event.method == "packetFromClient" ? "OUT" : "IN",
                packet: packet
            });
            while (this.packetEntries.length > MAX_PACKET_ENTRIES)
            {
                this.packetEntries.shift();
            }
            if (this.selectedNavigation == "Packet" && this.chromeVisible
                && (stage == null || stage.focus !== this.packetInput))
            {
                this.renderSidebar("Packet");
            }
        }

        private function onPacketDraftChanged(event:Event):void
        {
            this.packetDraft = this.packetInput == null ? "" : this.packetInput.text;
        }

        private function sendPacket(toClient:Boolean):void
        {
            if (!this.gameConnected)
            {
                this.botLibraryStatus("SIGN IN BEFORE SENDING PACKETS");
                return;
            }
            var packet:String = this.packetDraft == null ? "" : this.packetDraft.replace(/^\s+|\s+$/g, "");
            if (packet.length == 0)
            {
                return;
            }
            var type:String = packet.charAt(0) == "{" ? "json"
                : (packet.charAt(0) == "<" ? "xml" : "str");
            if (toClient)
            {
                HostBridge.invoke("sendClientPacket", packet, type);
            }
            else
            {
                HostBridge.invoke("sendServerPacket", packet);
            }
            this.packetEntries.push({direction: toClient ? "LOCAL" : "OUT", packet: packet});
            while (this.packetEntries.length > MAX_PACKET_ENTRIES)
            {
                this.packetEntries.shift();
            }
            this.renderSidebar("Packet");
        }

        private function toggleClientOption(id:String):void
        {
            if (!this.gameConnected && id != "option_death_ads" && id != "option_enable_chat")
            {
                this.botLibraryStatus("SIGN IN BEFORE CHANGING CLIENT OPTIONS");
                return;
            }
            if (id == "option_infinite_range")
            {
                this.infiniteRangeEnabled = !this.infiniteRangeEnabled;
                HostBridge.invoke("SetInfiniteRange", this.infiniteRangeEnabled);
            }
            else if (id == "option_provoke_cell") this.provokeCellEnabled = !this.provokeCellEnabled;
            else if (id == "option_provoke_map") this.provokeMapEnabled = !this.provokeMapEnabled;
            else if (id == "option_enemy_magnet") this.enemyMagnetEnabled = !this.enemyMagnetEnabled;
            else if (id == "option_lag_killer") this.toggleLagKiller();
            else if (id == "option_hide_players") this.toggleHidePlayers();
            else if (id == "option_skip_cutscenes") this.skipCutscenesEnabled = !this.skipCutscenesEnabled;
            else if (id == "option_disable_animations")
            {
                this.disableAnimationsEnabled = !this.disableAnimationsEnabled;
                HostBridge.invoke("DisableAnimations", this.disableAnimationsEnabled);
            }
            else if (id == "option_untarget_self") this.untargetSelfEnabled = !this.untargetSelfEnabled;
            else if (id == "option_auto_save")
            {
                this.autoSaveStateEnabled = !this.autoSaveStateEnabled;
                this.lastAutoSaveAt = 0;
            }
            else if (id == "option_fast_walk")
            {
                this.fastWalkEnabled = !this.fastWalkEnabled;
                HostBridge.invoke("SetWalkSpeed", this.fastWalkEnabled ? 40 : 8);
            }
            else if (id == "option_death_ads") HostBridge.invoke("DisableDeathAd");
            else if (id == "option_enable_chat") HostBridge.invoke("EnableChat");
            this.renderSidebar("Options");
        }

        private function onOptionTimer(event:TimerEvent):void
        {
            if (!this.gameConnected)
            {
                return;
            }
            try
            {
                if (this.provokeCellEnabled) HostBridge.invoke("SetProvokeMonsters");
                if (this.provokeMapEnabled) HostBridge.invoke("SetProvokeAllMonsters");
                if (this.enemyMagnetEnabled) HostBridge.invoke("SetEnemyMagnet");
                if (this.untargetSelfEnabled) HostBridge.invoke("CancelTargetSelf");
                if (this.skipCutscenesEnabled) HostBridge.invoke("SkipActiveCutscene");
                if (this.fastWalkEnabled) HostBridge.invoke("SetWalkSpeed", 40);
                if (this.autoSaveStateEnabled
                    && (this.lastAutoSaveAt == 0 || getTimer() - this.lastAutoSaveAt >= 300000))
                {
                    this.lastAutoSaveAt = getTimer();
                    HostBridge.invoke("SaveState");
                }
            }
            catch (error:Error)
            {
                // Live AQW objects can be replaced while maps load. The next
                // bounded timer tick retries without interrupting the client.
            }
        }

        private function applyImmediateOptions():void
        {
            try
            {
                HostBridge.invoke("SetInfiniteRange", this.infiniteRangeEnabled);
                HostBridge.invoke("SetLagKiller", !this.lagKillerEnabled);
                HostBridge.invoke("DestroyPlayers", this.playersHidden);
                HostBridge.invoke("DisableAnimations", this.disableAnimationsEnabled);
                HostBridge.invoke("SetWalkSpeed", this.fastWalkEnabled ? 40 : 8);
            }
            catch (error:Error)
            {
            }
        }

        private function onToggleClick(e:MouseEvent):void
        {
            if (this.cielDragMoved)
            {
                this.cielDragMoved = false;
                e.stopImmediatePropagation();
                return;
            }
            if (this.gameConnected && !this.chromeVisible)
            {
                this.openOverlay();
            }
        }

        private function toggleChrome():void
        {
            this.setChromeVisible(!this.chromeVisible);
        }

        private function openOverlay():void
        {
            this.setChromeVisible(true);
        }

        private function closeOverlay():void
        {
            this.setChromeVisible(false);
        }

        private function setChromeVisible(visible:Boolean):void
        {
            if (this.chromeVisible == visible)
            {
                this.updateOverlayControls();
                return;
            }
            this.chromeVisible = visible;
            this.chrome.mouseChildren = this.chromeVisible;
            this.chrome.visible = true;
            this.calculateTargets();
            this.drawToggleButton(this.toggleButton);
            this.updateOverlayControls();

            this.animationStartedAt = getTimer();
            this.startToggleX = this.toggleButton.x;
            this.startToggleY = this.toggleButton.y;
            this.startChromeAlpha = this.chrome.alpha;
            if (this.preferences.reducedMotion)
            {
                this.applyTargetsImmediately();
            }
            else
            {
                removeEventListener(Event.ENTER_FRAME, this.animateLayout);
                addEventListener(Event.ENTER_FRAME, this.animateLayout);
            }
            HostBridge.call("mobileChromeChanged", this.chromeVisible);
        }

        private function calculateTargets():void
        {
            this.viewportX = (this.layoutWidth - GAME_WIDTH) / 2;
            this.viewportY = (this.layoutHeight - GAME_HEIGHT) / 2;
            this.viewportWidth = GAME_WIDTH;
            this.viewportHeight = GAME_HEIGHT;
            this.targetToggleX = this.preferences.cielX >= 0
                ? Math.max(28, Math.min(this.layoutWidth - 28, this.preferences.cielX))
                : this.layoutWidth - 36;
            this.targetToggleY = this.preferences.cielY >= 0
                ? Math.max(28, Math.min(this.layoutHeight - 28, this.preferences.cielY))
                : CIEL_Y;
            this.targetChromeAlpha = this.chromeVisible ? 1 : 0;
        }

        private function updateOverlayControls():void
        {
            if (this.toggleButton != null)
            {
                this.toggleButton.visible = this.gameConnected && !this.chromeVisible;
            }
            if (this.cielTooltip != null && !this.gameConnected)
            {
                this.cielTooltip.visible = false;
            }
        }

        private function applyTargetsImmediately():void
        {
            this.chrome.alpha = this.targetChromeAlpha;
            this.chrome.visible = this.chromeVisible;
            this.toggleButton.x = this.targetToggleX;
            this.toggleButton.y = this.targetToggleY;
            this.updateOverlayControls();
            this.positionCielTooltip();
        }

        private function animateLayout(e:Event):void
        {
            var progress:Number = Math.min(1, (getTimer() - this.animationStartedAt) / TRANSITION_MS);
            var inverse:Number = 1 - progress;
            var eased:Number = 1 - (inverse * inverse * inverse);
            this.chrome.alpha = this.startChromeAlpha + ((this.targetChromeAlpha - this.startChromeAlpha) * eased);
            this.toggleButton.x = this.startToggleX + ((this.targetToggleX - this.startToggleX) * eased);
            this.toggleButton.y = this.startToggleY + ((this.targetToggleY - this.startToggleY) * eased);

            if (progress >= 1)
            {
                this.applyTargetsImmediately();
                removeEventListener(Event.ENTER_FRAME, this.animateLayout);
            }
        }

        private function startSelectedBot():void
        {
            this.botRunner.start(this.botLibrary.selectedDocument);
            if (this.selectedNavigation == "Bot" || this.selectedNavigation == "Home")
            {
                this.renderSidebar(this.selectedNavigation);
            }
        }

        private function onBotLibraryChanged(event:Event):void
        {
            if (this.selectedNavigation == "Bot")
            {
                this.renderSidebar("Bot");
            }
        }

        private function onBotStateChanged(event:Event):void
        {
            this.syncRunnerStatus();
            if (this.selectedNavigation == "Bot" || this.selectedNavigation == "Home"
                || this.selectedNavigation == "Runner")
            {
                this.renderSidebar(this.selectedNavigation);
            }
        }

        private function onApplicationActivate(event:Event):void
        {
            if (this.preferences.runnerEnabled)
            {
                this.configureRunner();
            }
        }

        private function botLibraryStatus(message:String):void
        {
			this.feedbackMessage = message == null ? "" : message;
			this.renderSidebar(this.selectedNavigation);
        }

        private function togglePreference(id:String):void
        {
            if (id == "pref_start_focused") this.preferences.startFocused = !this.preferences.startFocused;
            else if (id == "pref_hide_status") this.preferences.hideStatus = !this.preferences.hideStatus;
            else if (id == "pref_confirm_exit") this.preferences.confirmExit = !this.preferences.confirmExit;
            else if (id == "pref_reduced_motion") this.preferences.reducedMotion = !this.preferences.reducedMotion;
            else if (id == "pref_keep_awake") this.preferences.keepAwake = !this.preferences.keepAwake;
            else if (id == "pref_fps") this.preferences.frameRate = this.preferences.frameRate >= 60 ? 30 : 60;
            else if (id == "pref_quality")
            {
                this.preferences.quality = this.preferences.quality == "low" ? "medium"
                    : (this.preferences.quality == "medium" ? "high" : "low");
            }
            this.preferences.save();
            this.preferences.apply(stage);
            this.renderSidebar("Settings");
        }

        private function toggleRunnerPreference(id:String):void
        {
            if (id == "runner_enabled")
            {
                this.preferences.runnerEnabled = !this.preferences.runnerEnabled;
            }
            else if (id == "runner_stop_notifications")
            {
                this.preferences.runnerStopNotifications =
                    !this.preferences.runnerStopNotifications;
            }
            else if (id == "runner_keep_cpu_awake")
            {
                this.preferences.runnerKeepCpuAwake =
                    !this.preferences.runnerKeepCpuAwake;
            }
            this.preferences.save();
            this.configureRunner();
            this.renderSidebar("Runner");
        }

        private function configureRunner():void
        {
            this.preferences.apply(stage);
            if (this.runnerBridge == null)
            {
                return;
            }
            try
            {
                this.runnerBridge.configure(this.preferences.runnerEnabled,
                    this.preferences.runnerStopNotifications,
                    this.preferences.runnerKeepCpuAwake, this.runnerState());
            }
            catch (error:Error)
            {
            }
        }

        private function syncRunnerStatus():void
        {
            if (this.runnerBridge == null || !this.preferences.runnerEnabled)
            {
                return;
            }
            try
            {
                this.runnerBridge.updateStatus(this.runnerState(),
                    this.preferences.runnerStopNotifications,
                    this.preferences.runnerKeepCpuAwake);
            }
            catch (error:Error)
            {
            }
        }

        private function runnerState():String
        {
            if (this.botRunner.isPaused)
            {
                return "paused";
            }
            if (this.botRunner.isRunning)
            {
                return "running";
            }
            if (this.botRunner.status == "BOT IDLE")
            {
                return "idle";
            }
            return this.botRunner.status.indexOf("ERROR") >= 0
                || this.botRunner.status.indexOf("UNSUPPORTED") >= 0
                ? "error" : "stopped";
        }

        private function runnerStatusLabel():String
        {
            var state:String = this.runnerState();
            if (state == "running") return "RUNNING";
            if (state == "paused") return "PAUSED";
            if (state == "error") return "STOPPED WITH ERROR";
            if (state == "stopped") return "STOPPED";
            return "READY";
        }

        private function fullReset():void
        {
            if (getTimer() - this.resetArmedAt > 3000)
            {
                this.resetArmedAt = getTimer();
                this.selectedNavigation = "Settings";
                this.settingsPage = 2;
                this.renderSidebar("Settings");
                return;
            }
            this.botRunner.stop();
            this.preferences.reset();
            this.configureRunner();
            Root.username = null;
            Root.password = null;
            this.chromeVisible = !this.preferences.startFocused;
            this.calculateTargets();
            this.applyTargetsImmediately();
            this.showSection("Settings");
        }

        private function checkForUpdate():void
        {
            if (this.updateLoader != null)
            {
                this.botLibraryStatus("UPDATE CHECK ALREADY RUNNING");
                return;
            }
            this.updateLoader = new URLLoader();
            this.updateLoader.addEventListener(Event.COMPLETE, this.onUpdateLoaded);
            this.updateLoader.addEventListener(IOErrorEvent.IO_ERROR, this.onUpdateFailed);
            this.updateLoader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, this.onUpdateFailed);
            this.botLibraryStatus("CHECKING OFFICIAL GITHUB RELEASES...");
            try
            {
                this.updateLoader.load(new URLRequest(
                    "https://api.github.com/repos/UnknownSecurity/grimoire-exodus/releases?per_page=10"));
            }
            catch (error:Error)
            {
                this.finishUpdateCheck("UPDATE CHECK COULD NOT START");
            }
        }

        private function toggleLagKiller():void
        {
            this.lagKillerEnabled = !this.lagKillerEnabled;
            HostBridge.invoke("SetLagKiller", !this.lagKillerEnabled);
            this.botLibraryStatus(this.lagKillerEnabled ? "LAG KILLER ENABLED" : "LAG KILLER DISABLED");
        }

        private function toggleHidePlayers():void
        {
            this.playersHidden = !this.playersHidden;
            HostBridge.invoke("DestroyPlayers", this.playersHidden);
            this.botLibraryStatus(this.playersHidden ? "OTHER PLAYERS HIDDEN" : "OTHER PLAYERS VISIBLE");
        }

        private function onUpdateLoaded(event:Event):void
        {
            var bestVersion:Array = [0, 4, 4];
            var bestUrl:String;
            try
            {
                var releases:Array = JSON.parse(String(this.updateLoader.data)) as Array;
                for each (var release:Object in releases)
                {
                    if (release == null || release.draft === true || !(release.assets is Array))
                    {
                        continue;
                    }
                    for each (var asset:Object in release.assets)
                    {
                        var name:String = asset == null || asset.name == null ? "" : String(asset.name);
                        var match:Array = /Grimoire-Exodus-Android-AIR-(\d+)\.(\d+)\.(\d+)[^\/]*\.apk$/i.exec(name);
                        var url:String = asset == null || asset.browser_download_url == null
                            ? "" : String(asset.browser_download_url);
                        if (match != null && this.isNewerVersion(match, bestVersion)
                            && url.indexOf("https://github.com/UnknownSecurity/grimoire-exodus/releases/download/") == 0)
                        {
                            bestVersion = [int(match[1]), int(match[2]), int(match[3])];
                            bestUrl = url;
                        }
                    }
                }
            }
            catch (error:Error)
            {
                this.finishUpdateCheck("OFFICIAL RELEASE RESPONSE WAS INVALID");
                return;
            }
            this.availableUpdateUrl = bestUrl;
            this.finishUpdateCheck(bestUrl == null
                ? "YOU HAVE THE LATEST PUBLIC MOBILE BUILD"
                : "MOBILE UPDATE " + bestVersion.join(".") + " AVAILABLE — CHECK AGAIN TO OPEN");
        }

        private function onUpdateFailed(event:Event):void
        {
            this.finishUpdateCheck("UPDATE CHECK FAILED — TRY AGAIN LATER");
        }

        private function finishUpdateCheck(message:String):void
        {
            if (this.updateLoader != null)
            {
                this.updateLoader.removeEventListener(Event.COMPLETE, this.onUpdateLoaded);
                this.updateLoader.removeEventListener(IOErrorEvent.IO_ERROR, this.onUpdateFailed);
                this.updateLoader.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, this.onUpdateFailed);
                try
                {
                    this.updateLoader.close();
                }
                catch (error:Error)
                {
                }
                this.updateLoader = null;
            }
            this.botLibraryStatus(message);
        }

        private function isNewerVersion(candidate:Array, current:Array):Boolean
        {
            for (var i:int = 0; i < 3; i++)
            {
                var candidatePart:int = int(candidate[i]);
                var currentPart:int = int(current[i]);
                if (candidatePart != currentPart)
                {
                    return candidatePart > currentPart;
                }
            }
            return false;
        }

        private function ellipsize(value:String, maximum:int):String
        {
            if (value == null)
            {
                return "";
            }
            return value.length <= maximum ? value : value.substr(0, maximum - 1) + "…";
        }

        private function drawPanel(target:Shape, x:Number, y:Number, width:Number, height:Number, radius:Number, fill:uint, border:uint, borderAlpha:Number):void
        {
            target.graphics.beginFill(fill, 0.98);
            target.graphics.lineStyle(1, border, borderAlpha);
            target.graphics.drawRoundRect(x, y, width, height, radius, radius);
            target.graphics.endFill();
        }

        private function addText(parent:Sprite, value:String, x:Number, y:Number, width:Number, height:Number, size:Number, color:uint, bold:Boolean, font:String = "_sans", align:String = TextFormatAlign.LEFT):TextField
        {
            var field:TextField = new TextField();
            field.defaultTextFormat = new TextFormat(font, size, color, bold, null, null, null, null, align);
            field.x = x;
            field.y = y;
            field.width = width;
            field.height = height;
            field.text = value;
            field.selectable = false;
            field.mouseEnabled = false;
            parent.addChild(field);
            return field;
        }
    }
}
