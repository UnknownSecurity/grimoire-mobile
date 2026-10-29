package grimoire
{
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.events.TimerEvent;
    import flash.utils.Timer;
    import grimoire.game.Aura;
    import grimoire.game.Bank;
    import grimoire.game.Network;
    import grimoire.game.DropStack;
    import grimoire.game.House;
    import grimoire.game.Inventory;
    import grimoire.game.Player;
    import grimoire.game.Quest;
    import grimoire.game.Setting;
    import grimoire.game.Shop;
    import grimoire.game.Skill;
    import grimoire.game.TempInventory;
    import grimoire.game.World;

    /**
     * Cooperative mobile runner for the safe foundational GBot commands. It
     * stops on unknown commands instead of resolving arbitrary Newtonsoft
     * $type values, executing embedded code, or continuing in an invalid state.
     */
    public final class MobileBotRunner extends EventDispatcher
    {
        public static const STATE_CHANGED:String = "mobileBotStateChanged";

        private var timer:Timer = new Timer(1, 1);
        private var packetTimer:Timer = new Timer(1000);
        private var commands:Array = [];
        private var index:int;
        private var running:Boolean;
        private var paused:Boolean;
        private var waitingForKill:Boolean;
        private var killEngaged:Boolean;
        private var killTarget:String;
        private var killForItem:String;
        private var killForQuantity:int;
        private var killForTemporary:Boolean;
        private var labels:Object = {};
        private var statusText:String = "BOT IDLE";
        private var botDelay:int = 500;
        private var packetSpamEnabled:Boolean;
        private var packetSpamPacket:String;
        private var configuration:Object;
        private var tempVariables:Object = {};
        private var tempIntegers:Object = {};
        private var skillSets:Object = {};
        private var activeSkillSet:String;
        private var skillCursor:int;
        private var skillDelay:int = 250;
        private var dropWhitelist:Array = [];
        private var pickupEnabled:Boolean;
        private var questList:Array = [];

        public function MobileBotRunner()
        {
            this.timer.addEventListener(TimerEvent.TIMER_COMPLETE, this.onTimer);
            this.packetTimer.addEventListener(TimerEvent.TIMER, this.onPacketTimer);
        }

        public function get isRunning():Boolean
        {
            return this.running;
        }

        public function get isPaused():Boolean
        {
            return this.paused;
        }

        public function get status():String
        {
            return this.statusText;
        }

        public function get commandCount():int
        {
            return this.commands == null ? 0 : this.commands.length;
        }

        public function get commandPosition():int
        {
            if (this.commandCount == 0)
            {
                return 0;
            }
            return Math.max(1, Math.min(this.commandCount, this.index));
        }

        public function start(document:Object):void
        {
            if (!Root.isLoggedIn)
            {
                this.setStatus("SIGN IN BEFORE STARTING A BOT");
                return;
            }
            var list:Array = document == null ? null : document.mobileCommands as Array;
            if (list == null || list.length == 0)
            {
                this.setStatus("SELECT A BOT WITH COMMANDS");
                return;
            }
            this.stopTimer();
            this.configuration = document;
            this.commands = list.concat();
            // Older GBots commonly omit BotDelay or save it as zero. Keep a
            // small cooperative delay so AQW can finish target and asset state
            // updates between commands on slower Android devices.
            this.botDelay = document.BotDelay == null ? 500
                : this.numberValue(document.BotDelay, 10, 60000);
            this.labels = {};
            this.skillDelay = document.SkillDelay == null ? 250
                : this.numberValue(document.SkillDelay, 10, 10000);
            this.buildSkillSets(document.Skills);
            this.loadConfigurationLists(document);
            this.activeSkillSet = null;
            this.skillCursor = 0;
            for (var labelIndex:int = 0; labelIndex < this.commands.length; labelIndex++)
            {
                var labelCommand:Object = this.commands[labelIndex];
                if (this.commandName(labelCommand) == "CmdLabel")
                {
                    this.labels[this.textValue(labelCommand.Name).toLowerCase()] = labelIndex;
                }
            }
            this.index = 0;
            this.running = true;
            this.paused = false;
            this.waitingForKill = false;
            this.killEngaged = false;
            this.killTarget = null;
            this.killForItem = null;
            this.packetSpamEnabled = false;
            this.packetSpamPacket = null;
            this.packetTimer.stop();
            this.setStatus("BOT RUNNING");
            this.schedule(1);
        }

        public function stop(message:String = "BOT STOPPED"):void
        {
            this.stopTimer();
            this.running = false;
            this.paused = false;
            this.waitingForKill = false;
            this.killEngaged = false;
            this.killTarget = null;
            this.killForItem = null;
            this.packetSpamEnabled = false;
            this.packetSpamPacket = null;
            this.packetTimer.stop();
            try
            {
                Player.cancelTarget();
            }
            catch (error:Error)
            {
            }
            this.setStatus(message);
        }

        public function togglePause():void
        {
            if (!this.running)
            {
                this.setStatus("BOT IS NOT RUNNING");
                return;
            }
            this.paused = !this.paused;
            this.stopTimer();
            if (this.paused)
            {
                this.packetTimer.stop();
            }
            else if (this.packetSpamEnabled && this.packetSpamPacket != null
                && this.packetSpamPacket.length > 0)
            {
                this.packetTimer.start();
            }
            this.setStatus(this.paused ? "BOT PAUSED" : "BOT RUNNING");
            if (!this.paused)
            {
                this.schedule(1);
            }
        }

        private function onTimer(event:TimerEvent):void
        {
            if (!this.running || this.paused)
            {
                return;
            }
            if (!Root.isLoggedIn)
            {
                this.stop("BOT STOPPED: CLIENT DISCONNECTED");
                return;
            }
            if (this.waitingForKill)
            {
                this.continueKill();
                return;
            }
            this.collectWhitelistedDrops();
            if (this.maintainQuestList())
            {
                return;
            }
            if (this.index >= this.commands.length)
            {
                this.restartCommandLoop();
                return;
            }

            var command:Object = this.commands[this.index++];
            var kind:String = this.commandName(command);
            var delay:int = this.botDelay;
            try
            {
                switch (kind)
                {
                    case "CmdDelay":
                        delay = this.numberValue(command.Delay, 0, 600000);
                        break;
                    case "CmdBotDelay":
                    case "CmdBotDelay2":
                        this.botDelay = this.numberValue(command.Delay, 0, 60000);
                        delay = this.botDelay;
                        break;
                    case "CmdJoin":
                        Player.join(this.resolveText(command.Map),
                            this.resolveText(command.Cell, "Enter"),
                            this.resolveText(command.Pad, "Spawn"));
                        delay = 1800;
                        break;
                    case "CmdJoin2":
                        var map:String = this.resolveText(command.Map);
                        var room:String = this.resolveText(command.Room);
                        Player.join(map + (room.length > 0 ? "-" + room : ""),
                            this.resolveText(command.Cell, "Enter"),
                            this.resolveText(command.Pad, "Spawn"));
                        delay = 1800;
                        break;
                    case "CmdMoveToCell":
                    case "CmdJump":
                        Player.jump(this.resolveText(command.Cell, "Enter"),
                            this.resolveText(command.Pad, "Spawn"));
                        delay = 350;
                        break;
                    case "CmdWalk":
                        Player.walkToPoint(this.resolveText(command.X), this.resolveText(command.Y));
                        delay = 200;
                        break;
                    case "CmdAttack":
                        Player.attackMonster(this.resolveText(command.Monster, "*"));
                        delay = 250;
                        break;
                    case "CmdKill":
                        this.killTarget = this.resolveText(command.Monster, "*");
                        this.killForItem = null;
                        this.killEngaged = false;
                        this.waitingForKill = true;
                        this.continueKill();
                        return;
                    case "CmdKillFor":
                        this.killTarget = this.resolveText(command.Monster, "*");
                        this.killForItem = this.resolveText(command.ItemName);
                        this.killForQuantity = this.numberValue(this.resolveValue(command.Quantity), 1, 999999);
                        this.killForTemporary = String(command.ItemType).toLowerCase().indexOf("temp") >= 0
                            || int(command.ItemType) != 0;
                        if (this.inventoryHas(this.killForItem, this.killForQuantity, this.killForTemporary))
                        {
                            this.killForItem = null;
                            break;
                        }
                        this.killEngaged = false;
                        this.waitingForKill = true;
                        this.continueKill();
                        return;
                    case "CmdUseSkill":
                    case "CmdUseSkill2":
                        Skill.skillAction(this.resolveText(command.Index, "1"));
                        delay = 250;
                        break;
                    case "CmdSkillSet":
                        this.activeSkillSet = this.resolveText(command.Name).toUpperCase();
                        this.skillCursor = 0;
                        delay = 1;
                        break;
                    case "CmdRest":
                        Player.rest();
                        delay = command.Full === true ? 1400 : 350;
                        break;
                    case "CmdAcceptQuest":
                    case "CmdAcceptQuest2":
                        Quest.acceptQuest(this.questId(command));
                        delay = 750;
                        break;
                    case "CmdCompleteQuest":
                    case "CmdCompleteQuest2":
                        Quest.completeQuest(this.questId(command),
                            this.resolveText(command.ItemID, "-1"));
                        delay = 750;
                        break;
                    case "CmdSetSpawn":
                        World.setSpawnPoint();
                        break;
                    case "CmdGetDrop":
                        DropStack.getDrop(this.resolveText(command.ItemName));
                        delay = 350;
                        break;
                    case "CmdEquip":
                        var itemId:String = this.inventoryItemId(this.resolveText(command.ItemName));
                        if (itemId.length > 0)
                        {
                            Player.equipItem(itemId);
                        }
                        delay = 500;
                        break;
                    case "CmdBuy":
                    case "CmdBuy2":
                    case "CmdBuyFast":
                        Shop.buyItem(this.resolveText(command.ItemName));
                        delay = 500;
                        break;
                    case "CmdBuyByID":
                    case "CmdBuyFastByID":
                        Shop.buyItemByID(this.intValue(this.resolveValue(command.ItemID)),
                            this.intValue(this.resolveValue(command.ShopID)),
                            this.intValue(this.resolveValue(command.ShopItemID)),
                            command.Manual === true);
                        delay = 500;
                        break;
                    case "CmdLoad":
                    case "CmdLoad2":
                        Shop.load(this.resolveText(command.ShopId));
                        delay = 800;
                        break;
                    case "CmdSell":
                        Shop.sellItem(this.resolveText(command.ItemName));
                        delay = 500;
                        break;
                    case "CmdBankTransfer":
                        Bank.transfer(command.TransferFromBank === true ? "Inventory" : "Bank",
                            this.resolveText(command.ItemName));
                        delay = 700;
                        break;
                    case "CmdBankSwap":
                        Bank.bankSwap(this.resolveText(command.InventoryItemName),
                            this.resolveText(command.BankItemName));
                        delay = 700;
                        break;
                    case "CmdMapItem":
                    case "CmdMapItem2":
                        Player.getMapItem(this.resolveText(command.ItemId != null
                            ? command.ItemId : command.ItemID));
                        delay = 1500;
                        break;
                    case "CmdUseBoost":
                        var boostItem:Object = Inventory.getItem(this.resolveText(command.ItemName));
                        if (boostItem != null && boostItem.ItemID != null)
                        {
                            Player.useBoost(String(boostItem.ItemID));
                        }
                        delay = 500;
                        break;
                    case "CmdLoadMapSwf":
                        World.loadMap(this.resolveText(command.Name));
                        delay = 1500;
                        break;
                    case "CmdChange":
                        if (command.Guild === true)
                        {
                            Player.changeGuild(this.resolveText(command.Text));
                        }
                        else
                        {
                            Player.changeName(this.resolveText(command.Text));
                        }
                        break;
                    case "CmdGotoPlayer":
                        Player.goTo(this.resolveText(command.PlayerName));
                        delay = 1500;
                        break;
                    case "CmdCancelTarget":
                        Player.cancelTarget();
                        break;
                    case "CmdCancelAutoAttack":
                        Player.cancelAutoAttack();
                        break;
                    case "CmdSetFPS":
                        Root.setFPS(this.numberValue(command.FPS, 20, 60));
                        break;
                    case "CmdSetClientLevel":
                        var levelCap:int = 100;
                        if (Root.Game != null && Root.Game.intLevelCap != null)
                        {
                            levelCap = int(Root.Game.intLevelCap);
                        }
                        Root.sendClientPacket("{\"t\":\"xt\",\"b\":{\"r\":-1,\"o\":{\"cmd\":\"levelUp\",\"intExpToLevel\":\"0\",\"intLevel\":"
                            + String(levelCap) + "}}}", "json");
                        break;
                    case "CmdToggleProvoke":
                        if (int(command.Type) != 0)
                        {
                            Setting.provokeMonsters();
                        }
                        break;
                    case "CmdClientMessage":
                        Root.gameMessage(this.resolveText(command.Messages));
                        break;
                    case "CmdPacket":
                    case "CmdPacket2":
                        var preparedPacket:String = this.preparePacket(this.resolveText(command.Packet));
                        if (command.Client === true)
                        {
                            Root.sendClientPacket(preparedPacket, this.packetType(preparedPacket));
                        }
                        else
                        {
                            Root.sendServerPacket(preparedPacket);
                        }
                        delay = command.Delay == null
                            ? (preparedPacket.indexOf("%xt%zm%gar%") >= 0 ? 700 : 2000)
                            : this.numberValue(command.Delay, 1, 60000);
                        break;
                    case "CmdPacketlist2":
                        var packetMode:int = int(command.Type);
                        this.packetSpamPacket = this.resolveText(command.Packet);
                        this.packetTimer.delay = this.numberValue(command.Delay, 10, 60000);
                        this.packetSpamEnabled = packetMode == 0 ? false
                            : (packetMode == 1 ? true : !this.packetSpamEnabled);
                        if (this.packetSpamEnabled && this.packetSpamPacket.length > 0)
                        {
                            this.packetTimer.start();
                        }
                        else
                        {
                            this.packetTimer.stop();
                        }
                        break;
                    case "CmdLogout":
                        Network.logout();
                        delay = 1000;
                        break;
                    case "CmdRestart":
                        this.index = 0;
                        break;
                    case "CmdClearTemp":
                        this.tempVariables = {};
                        this.tempIntegers = {};
                        break;
                    case "CmdSetVar":
                        this.tempVariables[this.textValue(command.Value1)] =
                            this.textValue(command.Value2);
                        break;
                    case "CmdUpdateVar":
                        var updateKey:String = this.textValue(command.Value1);
                        if (this.tempVariables.hasOwnProperty(updateKey))
                        {
                            this.tempVariables[updateKey] = this.textValue(command.Value2);
                        }
                        else
                        {
                            this.index++;
                        }
                        break;
                    case "CmdGetClassWithVar":
                        this.tempVariables[this.textValue(command.Value1)] =
                            this.gameString(Player.className());
                        break;
                    case "CmdInt":
                        this.executeIntegerCommand(command);
                        break;
                    case "CmdWhitelist":
                        this.executeWhitelistCommand(command);
                        break;
                    case "CmdQuestlist":
                        this.executeQuestListCommand(command);
                        delay = 750;
                        break;
                    case "CmdGotoLabel":
                        var targetLabel:String = this.textValue(command.Label).toLowerCase();
                        if (this.labels[targetLabel] != null)
                        {
                            this.index = int(this.labels[targetLabel]);
                        }
                        break;
                    case "CmdIndex":
                        var indexType:String = String(command.Type).toLowerCase();
                        var amount:int = this.numberValue(command.Index, 0, this.commands.length);
                        if (indexType == "0" || indexType.indexOf("up") >= 0)
                        {
                            this.index = Math.max(0, this.index - amount - 1);
                        }
                        else if (indexType == "1" || indexType.indexOf("down") >= 0)
                        {
                            this.index = Math.min(this.commands.length, this.index + amount - 1);
                        }
                        else
                        {
                            this.index = Math.max(0, Math.min(this.commands.length, amount - 1));
                        }
                        break;
                    case "CmdStop":
                        this.stop("BOT STOPPED");
                        return;
                    case "CmdStopBotWithMessage":
                        this.stop(this.textValue(command.Message, "BOT STOPPED"));
                        return;
                    case "CmdBlank":
                    case "CmdBlank2":
                    case "CmdBlank3":
                    case "CmdLabel":
                    case "CmdLog":
                    case "CmdBankList":
                    case "CmdFollow":
                        break;
                    default:
                        if (this.executeStatement(kind, command))
                        {
                            break;
                        }
                        // Continuing after a missing condition or control-flow
                        // command can make later actions unsafe. Stop at the
                        // exact unsupported command and preserve ordering.
                        this.stop("UNSUPPORTED COMMAND " + kind.toUpperCase());
                        return;
                }
            }
            catch (error:Error)
            {
                this.stop("BOT ERROR AT COMMAND " + String(this.index));
                return;
            }
            this.schedule(delay);
        }

        private function continueKill():void
        {
            try
            {
                if (Player.hasTarget() == Root.trueString)
                {
                    this.killEngaged = true;
                    if (!this.useConfiguredSkill())
                    {
                        for (var skill:int = 1; skill <= 4; skill++)
                        {
                            Skill.skillAction(String(skill));
                        }
                    }
                    this.schedule(this.activeSkillSet == null ? 500 : this.skillDelay);
                    return;
                }
                if (!this.killEngaged && World.isMonsterAvailable(this.killTarget) == Root.trueString)
                {
                    Player.attackMonster(this.killTarget);
                    this.schedule(350);
                    return;
                }
            }
            catch (error:Error)
            {
                this.stop("BOT ERROR WHILE FIGHTING");
                return;
            }
            if (this.killForItem != null
                && !this.inventoryHas(this.killForItem, this.killForQuantity, this.killForTemporary))
            {
                DropStack.getDrop(this.killForItem);
                this.killEngaged = false;
                this.schedule(650);
                return;
            }
            this.waitingForKill = false;
            this.killEngaged = false;
            this.killTarget = null;
            this.killForItem = null;
            this.schedule(120);
        }

        private function restartCommandLoop():void
        {
            this.index = 0;
            this.setStatus("BOT RUNNING");
            this.schedule(Math.max(1, this.botDelay));
        }

        private function buildSkillSets(raw:*):void
        {
            this.skillSets = {};
            var skills:Array = this.listValues(raw);
            var current:Array = [];
            this.skillSets[""] = current;
            for each (var skill:Object in skills)
            {
                if (skill == null)
                {
                    continue;
                }
                var typeText:String = String(skill.Type).toLowerCase();
                var isLabel:Boolean = int(skill.Type) == 2 || typeText.indexOf("label") >= 0;
                if (isLabel)
                {
                    var label:String = this.textValue(skill.Text).replace(/^\[|\]$/g, "").toUpperCase();
                    current = [];
                    this.skillSets[label] = current;
                }
                else
                {
                    current.push(skill);
                }
            }
        }

        private function useConfiguredSkill():Boolean
        {
            if (this.activeSkillSet == null)
            {
                return false;
            }
            var skills:Array = this.skillSets[this.activeSkillSet] as Array;
            if (skills == null || skills.length == 0)
            {
                return false;
            }
            if (this.skillCursor >= skills.length)
            {
                this.skillCursor = 0;
            }
            var skill:Object = skills[this.skillCursor++];
            var shouldUse:Boolean = true;
            var typeText:String = String(skill.Type).toLowerCase();
            if (int(skill.Type) == 1 || typeText.indexOf("safe") >= 0)
            {
                var threshold:Number = Number(skill.SafePercentage);
                var actual:Number = threshold;
                if (skill.SafeHp === true)
                {
                    actual = this.percentage(Player.health(), Player.maxHealth());
                }
                else if (skill.SafeMp === true)
                {
                    actual = this.percentage(Player.mana(), Player.maxMana());
                }
                shouldUse = skill.ComparisonType === true
                    ? actual >= threshold : actual <= threshold;
            }
            if (shouldUse)
            {
                Skill.skillAction(this.textValue(skill.Index, "1"));
            }
            return true;
        }

        private function loadConfigurationLists(document:Object):void
        {
            this.dropWhitelist = [];
            this.pickupEnabled = document != null && document.EnablePickup === true;
            var rawDrops:Array = this.listValues(document == null ? null : document.Drops);
            for each (var rawDrop:* in rawDrops)
            {
                this.addUniqueText(this.dropWhitelist, this.textValue(rawDrop));
            }

            this.questList = [];
            var rawQuests:Array = this.listValues(document == null ? null : document.Quests);
            var questIds:Array = [];
            for each (var rawQuest:Object in rawQuests)
            {
                if (rawQuest == null)
                {
                    continue;
                }
                var id:String = this.textValue(rawQuest.Id != null
                    ? rawQuest.Id : rawQuest.QuestID);
                if (id.length == 0)
                {
                    continue;
                }
                this.questList.push({ id: id, itemId: this.textValue(rawQuest.ItemId, "-1") });
                questIds.push(id);
            }
            if (questIds.length > 0)
            {
                Quest.loadMultipleQuests(questIds.join(","));
            }
        }

        private function executeWhitelistCommand(command:Object):void
        {
            var rawState:* = command.State;
            var stateText:String = String(rawState).toLowerCase();
            if (stateText == "0" || stateText == "on")
            {
                this.pickupEnabled = true;
            }
            else if (stateText == "1" || stateText == "off")
            {
                this.pickupEnabled = false;
            }
            else if (stateText == "2" || stateText == "clear")
            {
                this.dropWhitelist = [];
            }
            else if (stateText == "3" || stateText == "add")
            {
                this.addUniqueText(this.dropWhitelist, this.resolveText(command.Item));
            }
            else if (stateText == "4" || stateText == "remove")
            {
                this.removeText(this.dropWhitelist, this.resolveText(command.Item));
            }
        }

        private function executeQuestListCommand(command:Object):void
        {
            var rawState:* = command.state;
            var stateText:String = String(rawState).toLowerCase();
            var id:String = this.resolveText(command.QuestID);
            var itemId:String = this.resolveText(command.ItemID, "-1");
            if (stateText == "0" || stateText == "add")
            {
                this.removeQuest(id, itemId);
                this.questList.push({ id: id, itemId: itemId });
                Quest.loadQuest(id);
                Quest.acceptQuest(id);
            }
            else if (stateText == "1" || stateText == "remove")
            {
                this.removeQuest(id, itemId);
            }
            else if (stateText == "2" || stateText == "clear")
            {
                this.questList = [];
            }
        }

        private function maintainQuestList():Boolean
        {
            for each (var quest:Object in this.questList)
            {
                try
                {
                    if (this.isTrue(Quest.canComplete(String(quest.id))))
                    {
                        Quest.completeQuest(String(quest.id), this.textValue(quest.itemId, "-1"));
                        this.schedule(750);
                        return true;
                    }
                    if (!this.isTrue(Quest.isInProgress(String(quest.id)))
                        && this.isTrue(Quest.isAvailable(String(quest.id))))
                    {
                        Quest.acceptQuest(String(quest.id));
                        this.schedule(750);
                        return true;
                    }
                }
                catch (error:Error)
                {
                    // The quest may still be loading. The command loop retries
                    // without stopping or skipping unrelated legacy commands.
                }
            }
            return false;
        }

        private function collectWhitelistedDrops():void
        {
            if (!this.pickupEnabled)
            {
                return;
            }
            for each (var rawName:* in this.dropWhitelist)
            {
                var name:String = this.resolveText(rawName);
                if (name.length > 0 && this.isTrue(DropStack.hasDrop(name)))
                {
                    DropStack.getDrop(name);
                }
            }
        }

        private function addUniqueText(values:Array, value:String):void
        {
            if (value == null || value.length == 0)
            {
                return;
            }
            for each (var existing:* in values)
            {
                if (String(existing).toLowerCase() == value.toLowerCase())
                {
                    return;
                }
            }
            if (values.length < 256)
            {
                values.push(value);
            }
        }

        private function removeText(values:Array, value:String):void
        {
            for (var i:int = values.length - 1; i >= 0; i--)
            {
                if (String(values[i]).toLowerCase() == value.toLowerCase())
                {
                    values.splice(i, 1);
                }
            }
        }

        private function removeQuest(id:String, itemId:String):void
        {
            for (var i:int = this.questList.length - 1; i >= 0; i--)
            {
                var quest:Object = this.questList[i];
                if (String(quest.id) == id && (itemId.length == 0
                    || String(quest.itemId) == itemId))
                {
                    this.questList.splice(i, 1);
                }
            }
        }

        private function onPacketTimer(event:TimerEvent):void
        {
            if (!this.running || this.paused || !this.packetSpamEnabled
                || !Root.isLoggedIn || this.packetSpamPacket == null
                || this.packetSpamPacket.length == 0)
            {
                this.packetTimer.stop();
                return;
            }
            try
            {
                Root.sendServerPacket(this.preparePacket(this.packetSpamPacket));
            }
            catch (error:Error)
            {
                this.packetTimer.stop();
                this.stop("BOT PACKET ERROR");
            }
        }

        private function preparePacket(value:String):String
        {
            var packet:String = value == null ? "" : value;
            var roomId:String = "0";
            var roomNumber:String = "0";
            var playerName:String = "";
            var map:String = "";
            try
            {
                roomId = World.roomID();
                roomNumber = World.roomNumber();
                map = this.gameString(Player.map());
                if (Root.Game != null && Root.Game.world != null
                    && Root.Game.world.myAvatar != null)
                {
                    playerName = String(Root.Game.world.myAvatar.objData.strUsername);
                }
            }
            catch (error:Error)
            {
            }
            packet = packet.split("{ROOM_ID}").join(roomId)
                .split("{ROOM_NUMBER}").join(roomNumber)
                .split("PLAYERNAME").join(playerName)
                .split("{GETMAP}").join(map);
            while (packet.indexOf("--") >= 0)
            {
                packet = packet.split("--").join("-");
            }
            packet = packet.replace(/1e[0-9]+/gi,
                "1e" + String(1001 + int(Math.random() * 98999)));
            return packet;
        }

        private function packetType(packet:String):String
        {
            return packet != null && packet.charAt(0) == "{" ? "json"
                : (packet != null && packet.charAt(0) == "<" ? "xml" : "str");
        }

        private function executeStatement(kind:String, command:Object):Boolean
        {
            var condition:Boolean;
            var value1:String = this.resolveText(command.Value1);
            var value2:String = this.resolveText(command.Value2);
            switch (kind)
            {
                case "CmdInInventory":
                    condition = this.inventoryHas(value1, this.quantityValue(value2), false);
                    break;
                case "CmdNotInInventory":
                    condition = !this.inventoryHas(value1, this.quantityValue(value2), false);
                    break;
                case "CmdInTemp":
                    condition = this.inventoryHas(value1, this.quantityValue(value2), true);
                    break;
                case "CmdNotInTemp":
                    condition = !this.inventoryHas(value1, this.quantityValue(value2), true);
                    break;
                case "CmdIsMaxStack":
                    condition = this.inventoryIsMaxed(value1, false);
                    break;
                case "CmdIsNotMaxStack":
                    condition = !this.inventoryIsMaxed(value1, false);
                    break;
                case "CmdLevelGreaterThan":
                    condition = Player.level() > this.intValue(value1);
                    break;
                case "CmdLevelLessThan":
                    condition = Player.level() < this.intValue(value1);
                    break;
                case "CmdLevelIs":
                    condition = Player.level() == this.intValue(value1);
                    break;
                case "CmdGoldGreaterThan":
                    condition = Player.gold() > this.intValue(value1);
                    break;
                case "CmdGoldLessThan":
                    condition = Player.gold() < this.intValue(value1);
                    break;
                case "CmdHealthGreaterThan":
                    condition = Player.health() > this.intValue(value1);
                    break;
                case "CmdHealthLessThan":
                    condition = Player.health() < this.intValue(value1);
                    break;
                case "CmdHealthPercentageGreaterThan":
                    condition = this.percentage(Player.health(), Player.maxHealth()) > this.intValue(value1);
                    break;
                case "CmdHealthPercentageLessThan":
                    condition = this.percentage(Player.health(), Player.maxHealth()) < this.intValue(value1);
                    break;
                case "CmdManaGreaterThan":
                    condition = Player.mana() > this.intValue(value1);
                    break;
                case "CmdManaLessThan":
                    condition = Player.mana() < this.intValue(value1);
                    break;
                case "CmdCellIs":
                    condition = this.gameString(Player.cell()).toLowerCase() == value1.toLowerCase();
                    break;
                case "CmdCellIsNot":
                    condition = this.gameString(Player.cell()).toLowerCase() != value1.toLowerCase();
                    break;
                case "CmdMapIs":
                    condition = this.mapName(this.gameString(Player.map())) == this.mapName(value1);
                    break;
                case "CmdMapIsNot":
                    condition = this.mapName(this.gameString(Player.map())) != this.mapName(value1);
                    break;
                case "CmdInCombat":
                    condition = Player.state() == 2;
                    break;
                case "CmdNotInCombat":
                    condition = Player.state() != 2;
                    break;
                case "CmdIsMember":
                    condition = this.isTrue(Player.isMember());
                    break;
                case "CmdIsNotMember":
                    condition = !this.isTrue(Player.isMember());
                    break;
                case "CmdMonsterInRoom":
                    condition = this.isTrue(World.isMonsterAvailable(value1));
                    break;
                case "CmdMonsterNotInRoom":
                    condition = !this.isTrue(World.isMonsterAvailable(value1));
                    break;
                case "CmdSkillIsAvailable":
                    condition = this.isTrue(Skill.isSkillAvailable(value1));
                    break;
                case "CmdSkillIsNotAvailable":
                    condition = !this.isTrue(Skill.isSkillAvailable(value1));
                    break;
                case "CmdQuestInProgress":
                    condition = this.isTrue(Quest.isInProgress(value1));
                    break;
                case "CmdQuestNotInProgress":
                    condition = !this.isTrue(Quest.isInProgress(value1));
                    break;
                case "CmdQuestCompleted":
                    condition = this.isTrue(Quest.canComplete(value1));
                    break;
                case "CmdQuestNotCompleted":
                    condition = !this.isTrue(Quest.canComplete(value1));
                    break;
                case "CmdQuestAvailable":
                    condition = this.isTrue(Quest.isAvailable(value1));
                    break;
                case "CmdQuestNotAvailable":
                    condition = !this.isTrue(Quest.isAvailable(value1));
                    break;
                case "CmdFactionRankGreaterThan":
                    condition = this.factionRank(value1) > this.intValue(value2);
                    break;
                case "CmdFactionRankLessThan":
                    condition = this.factionRank(value1) < this.intValue(value2);
                    break;
                case "CmdEquipped":
                    condition = this.isEquipped(value1);
                    break;
                case "CmdNotEquipped":
                    condition = !this.isEquipped(value1);
                    break;
                case "CmdInBank":
                    condition = this.itemHasQuantity(Bank.getItem(value1), this.quantityValue(value2));
                    break;
                case "CmdNotInBank":
                    condition = !this.itemHasQuantity(Bank.getItem(value1), this.quantityValue(value2));
                    break;
                case "CmdInHouse":
                    condition = this.itemHasQuantity(House.getItem(value1), this.quantityValue(value2));
                    break;
                case "CmdNotInHouse":
                    condition = !this.itemHasQuantity(House.getItem(value1), this.quantityValue(value2));
                    break;
                case "CmdItemPickupable":
                    condition = this.isTrue(DropStack.hasDrop(value1));
                    break;
                case "CmdItemNotPickupable":
                    condition = !this.isTrue(DropStack.hasDrop(value1));
                    break;
                case "CmdListInInv":
                    condition = this.allConfiguredItemsInInventory();
                    break;
                case "CmdIntIs":
                    condition = this.integerValue(value1) == this.intValue(value2);
                    break;
                case "CmdIntIsNot":
                    condition = this.integerValue(value1) != this.intValue(value2);
                    break;
                case "CmdIntGreaterThan":
                    condition = this.integerValue(value1) > this.intValue(value2);
                    break;
                case "CmdIntLessThan":
                    condition = this.integerValue(value1) < this.intValue(value2);
                    break;
                case "CmdIntEqualInt":
                    condition = this.integerValue(value1) == this.integerValue(value2);
                    break;
                case "CmdIntNotEqualInt":
                    condition = this.integerValue(value1) != this.integerValue(value2);
                    break;
                case "CmdAvailableMonstersGreaterThan":
                    condition = this.monsterCount(false) > this.intValue(value1);
                    break;
                case "CmdAvailableMonstersLessThan":
                    condition = this.monsterCount(false) < this.intValue(value1);
                    break;
                case "CmdVisibleMonstersGreaterThan":
                    condition = this.monsterCount(true) > this.intValue(value1);
                    break;
                case "CmdVisibleMonstersLessThan":
                    condition = this.monsterCount(true) < this.intValue(value1);
                    break;
                case "CmdMonsterHealthGreaterThan":
                    condition = World.monsterHealth(value1) > this.intValue(value2);
                    break;
                case "CmdMonsterHealthLessThan":
                    condition = World.monsterHealth(value1) < this.intValue(value2);
                    break;
                case "CmdPlayersGreaterThan":
                    condition = this.playerCount(null) > this.intValue(value1);
                    break;
                case "CmdPlayersLessThan":
                    condition = this.playerCount(null) < this.intValue(value1);
                    break;
                case "CmdPlayersInCellGreaterThan":
                    condition = this.playerCount(value1) > this.intValue(value2);
                    break;
                case "CmdPlayersInCellLessThan":
                    condition = this.playerCount(value1) < this.intValue(value2);
                    break;
                case "CmdPlayersInMyCellGreaterThan":
                    condition = this.playerCount(this.gameString(Player.cell())) > this.intValue(value1);
                    break;
                case "CmdPlayersInMyCellLessThan":
                    condition = this.playerCount(this.gameString(Player.cell())) < this.intValue(value1);
                    break;
                case "CmdPlayerInRoom":
                    condition = this.findPlayer(value1, null) != null;
                    break;
                case "CmdPlayerNotInRoom":
                    condition = this.findPlayer(value1, null) == null;
                    break;
                case "CmdPlayerIsInCell":
                    condition = this.findPlayer(value1, value2) != null;
                    break;
                case "CmdPlayerIsNotInCell":
                    condition = this.findPlayer(value1, value2) == null;
                    break;
                case "CmdPlayerIsInMyCell":
                    condition = this.findPlayer(value1, this.gameString(Player.cell())) != null;
                    break;
                case "CmdPlayerIsNotInMyCell":
                    condition = this.findPlayer(value1, this.gameString(Player.cell())) == null;
                    break;
                case "CmdPlayerInCombat":
                    condition = this.isTrue(World.isPlayerInCombat(value1));
                    break;
                case "CmdPlayerNotInCombat":
                    condition = !this.isTrue(World.isPlayerInCombat(value1));
                    break;
                case "CmdPlayerEquippedClass":
                    condition = this.isTrue(World.isPlayerWithClass(value1, value2));
                    break;
                case "CmdPlayerNotEquippedClass":
                    condition = !this.isTrue(World.isPlayerWithClass(value1, value2));
                    break;
                case "CmdPlayerAuraIsActive":
                    condition = this.auraActive("Self", value1);
                    break;
                case "CmdPlayerAuraIsNotActive":
                    condition = !this.auraActive("Self", value1);
                    break;
                case "CmdTargetAuraIsActive":
                    condition = this.auraActive("Target", value1);
                    break;
                case "CmdTargetAuraIsNotActive":
                    condition = !this.auraActive("Target", value1);
                    break;
                case "CmdPlayerAuraStringValIs":
                    condition = this.auraStringValue("Self", value1, value2);
                    break;
                case "CmdPlayerAuraStringValIsNot":
                    condition = !this.auraStringValue("Self", value1, value2);
                    break;
                case "CmdTargetAuraStringValIs":
                    condition = this.auraStringValue("Target", value1, value2);
                    break;
                case "CmdTargetAuraStringValIsNot":
                    condition = !this.auraStringValue("Target", value1, value2);
                    break;
                case "CmdPlayerAuraValIs":
                    condition = this.auraNumberValue("Self", "Equal", value1, this.intValue(value2));
                    break;
                case "CmdPlayerAuraValIsNot":
                    condition = !this.auraNumberValue("Self", "Equal", value1, this.intValue(value2));
                    break;
                case "CmdPlayerAuraValIsGreaterThan":
                    condition = this.auraNumberValue("Self", "Greater", value1, this.intValue(value2));
                    break;
                case "CmdPlayerAuraValIsLessThan":
                    condition = this.auraNumberValue("Self", "Less", value1, this.intValue(value2));
                    break;
                case "CmdTargetAuraValIs":
                    condition = this.auraNumberValue("Target", "Equal", value1, this.intValue(value2));
                    break;
                case "CmdTargetAuraValIsNot":
                    condition = !this.auraNumberValue("Target", "Equal", value1, this.intValue(value2));
                    break;
                case "CmdTargetAuraValIsGreaterThan":
                    condition = this.auraNumberValue("Target", "Greater", value1, this.intValue(value2));
                    break;
                case "CmdTargetAuraValIsLessThan":
                    condition = this.auraNumberValue("Target", "Less", value1, this.intValue(value2));
                    break;
                default:
                    return false;
            }
            if (!condition)
            {
                // Desktop statement commands skip the command immediately
                // following a false condition. `index` already points there.
                this.index++;
            }
            return true;
        }

        private function executeIntegerCommand(command:Object):void
        {
            var key:String = this.textValue(command.Int);
            var typeText:String = String(command.type).toLowerCase();
            if (typeText == "0" || typeText.indexOf("set") >= 0)
            {
                this.tempIntegers[key] = this.intValue(command.Value);
            }
            else
            {
                var current:int = this.tempIntegers.hasOwnProperty(key)
                    ? int(this.tempIntegers[key]) : 0;
                this.tempIntegers[key] = typeText == "1" || typeText.indexOf("upper") >= 0
                    ? current + 1 : current - 1;
            }
        }

        private function resolveValue(value:*):*
        {
            if (value == null)
            {
                return value;
            }
            var text:String = String(value);
            if (text.length >= 2 && text.charAt(0) == "["
                && text.charAt(text.length - 1) == "]")
            {
                var key:String = text.substring(1, text.length - 1).split("'").join("");
                if (this.tempVariables.hasOwnProperty(key))
                {
                    return this.tempVariables[key];
                }
            }
            return value;
        }

        private function resolveText(value:*, fallback:String = ""):String
        {
            var resolved:* = this.resolveValue(value);
            return resolved == null ? fallback : String(resolved);
        }

        private function listValues(value:*):Array
        {
            if (value is Array)
            {
                return value as Array;
            }
            if (value != null && value["$values"] is Array)
            {
                return value["$values"] as Array;
            }
            return [];
        }

        private function integerValue(key:String):int
        {
            return this.tempIntegers.hasOwnProperty(key) ? int(this.tempIntegers[key]) : 0;
        }

        private function itemHasQuantity(item:Object, quantity:int):Boolean
        {
            if (item == null)
            {
                return false;
            }
            var raw:* = item.iQty != null ? item.iQty
                : (item.Quantity != null ? item.Quantity : 1);
            return int(raw) >= quantity;
        }

        private function isEquipped(name:String):Boolean
        {
            var item:Object = Inventory.getItem(name);
            return item != null && (item.bEquip === true || int(item.bEquip) == 1
                || item.IsEquipped === true || int(item.IsEquipped) == 1);
        }

        private function allConfiguredItemsInInventory():Boolean
        {
            var items:Array = this.listValues(this.configuration == null
                ? null : this.configuration.Items);
            for each (var value:* in items)
            {
                var name:String = value is String ? String(value)
                    : this.textValue(value == null ? null : value.Name);
                if (name.length > 0 && !this.inventoryHas(this.resolveText(name), 1, false))
                {
                    return false;
                }
            }
            return true;
        }

        private function monsterCount(visibleOnly:Boolean):int
        {
            var monsters:Array = this.jsonArray(visibleOnly
                ? World.getVisibleMonstersInCell() : World.getMonstersInCell());
            var count:int;
            for each (var monster:Object in monsters)
            {
                if (monster != null && (monster.intState == null || int(monster.intState) > 0))
                {
                    count++;
                }
            }
            return count;
        }

        private function playerCount(cell:String):int
        {
            var players:Array = this.jsonArray(World.avatarsInMap());
            if (cell == null || cell.length == 0)
            {
                return players.length;
            }
            var count:int;
            for each (var player:Object in players)
            {
                if (player != null && player.strFrame != null
                    && String(player.strFrame).toLowerCase() == cell.toLowerCase())
                {
                    count++;
                }
            }
            return count;
        }

        private function findPlayer(name:String, cell:String):Object
        {
            var players:Array = this.jsonArray(World.avatarsInMap());
            for each (var player:Object in players)
            {
                if (player == null)
                {
                    continue;
                }
                var playerName:String = player.strUsername != null
                    ? String(player.strUsername) : this.textValue(player.uoName);
                if (playerName.toLowerCase() == name.toLowerCase()
                    && (cell == null || cell.length == 0
                        || (player.strFrame != null
                            && String(player.strFrame).toLowerCase() == cell.toLowerCase())))
                {
                    return player;
                }
            }
            return null;
        }

        private function auraActive(target:String, name:String):Boolean
        {
            try
            {
                return this.isTrue(Aura.isAuraActive(target, name));
            }
            catch (error:Error)
            {
                return false;
            }
        }

        private function auraStringValue(target:String, name:String, value:String):Boolean
        {
            try
            {
                return this.isTrue(Aura.isAuraWithStrValActive(target, name, value));
            }
            catch (error:Error)
            {
                return false;
            }
        }

        private function auraNumberValue(target:String, comparison:String,
            name:String, value:int):Boolean
        {
            try
            {
                return this.isTrue(Aura.auraComparison(target, comparison, name, value));
            }
            catch (error:Error)
            {
                return false;
            }
        }

        private function jsonArray(raw:String):Array
        {
            try
            {
                var value:* = JSON.parse(raw);
                return value is Array ? value as Array : [];
            }
            catch (error:Error)
            {
                return [];
            }
        }

        private function gameString(value:String):String
        {
            if (value == null || value.length == 0)
            {
                return "";
            }
            try
            {
                var decoded:* = JSON.parse(value);
                return decoded == null ? "" : String(decoded);
            }
            catch (error:Error)
            {
                return value;
            }
        }

        private function mapName(value:String):String
        {
            var normalized:String = value == null ? "" : value.toLowerCase();
            return normalized.indexOf("-") >= 0 ? normalized.split("-")[0] : normalized;
        }

        private function quantityValue(value:String):int
        {
            return value == null || value.length == 0 || value == "*"
                ? 1 : Math.max(1, this.intValue(value));
        }

        private function intValue(value:*):int
        {
            var parsed:Number = Number(value);
            return isNaN(parsed) ? 0 : int(parsed);
        }

        private function percentage(value:int, maximum:int):Number
        {
            return maximum <= 0 ? 0 : (Number(value) / Number(maximum)) * 100;
        }

        private function isTrue(value:String):Boolean
        {
            return value != null && (value == Root.trueString
                || value.toLowerCase() == "true" || value.toLowerCase() == '"true"');
        }

        private function inventoryIsMaxed(name:String, temporary:Boolean):Boolean
        {
            var item:Object = this.inventoryItem(name, temporary);
            return item != null && item.iQty != null && item.iStk != null
                && int(item.iQty) >= int(item.iStk);
        }

        private function inventoryItem(name:String, temporary:Boolean):Object
        {
            try
            {
                var raw:String = temporary ? TempInventory.tempItems() : Inventory.inventoryItems();
                var items:Array = JSON.parse(raw) as Array;
                for each (var item:Object in items)
                {
                    if (item != null && item.sName != null
                        && String(item.sName).toLowerCase() == name.toLowerCase())
                    {
                        return item;
                    }
                }
            }
            catch (error:Error)
            {
            }
            return null;
        }

        private function factionRank(name:String):int
        {
            try
            {
                var factions:Array = JSON.parse(Player.factions()) as Array;
                for each (var faction:Object in factions)
                {
                    if (faction != null && faction.sName != null
                        && String(faction.sName).toLowerCase() == name.toLowerCase())
                    {
                        var reputation:int = int(faction.iRep);
                        if (reputation >= 302500) return 10;
                        if (reputation >= 202500) return 9;
                        if (reputation >= 129600) return 8;
                        if (reputation >= 78400) return 7;
                        if (reputation >= 44100) return 6;
                        if (reputation >= 22500) return 5;
                        if (reputation >= 10000) return 4;
                        if (reputation >= 3600) return 3;
                        if (reputation >= 900) return 2;
                        return 1;
                    }
                }
            }
            catch (error:Error)
            {
            }
            return 0;
        }

        private function inventoryHas(name:String, quantity:int, temporary:Boolean):Boolean
        {
            var item:Object = this.inventoryItem(name, temporary);
            return item != null && int(item.iQty) >= quantity;
        }

        private function inventoryItemId(name:String):String
        {
            try
            {
                var items:Array = JSON.parse(Inventory.inventoryItems()) as Array;
                for each (var item:Object in items)
                {
                    if (item != null && item.sName != null && item.ItemID != null
                        && String(item.sName).toLowerCase() == name.toLowerCase())
                    {
                        return String(item.ItemID);
                    }
                }
            }
            catch (error:Error)
            {
            }
            return "";
        }

        private function schedule(delay:int):void
        {
            if (!this.running || this.paused)
            {
                return;
            }
            this.stopTimer();
            this.timer.delay = Math.max(1, delay);
            this.timer.repeatCount = 1;
            this.timer.start();
        }

        private function stopTimer():void
        {
            this.timer.stop();
            this.timer.reset();
        }

        private function setStatus(value:String):void
        {
            this.statusText = value;
            this.dispatchEvent(new Event(STATE_CHANGED));
        }

        private function commandName(command:Object):String
        {
            var qualified:String = command == null || command["$type"] == null
                ? "Unknown" : String(command["$type"]).split(",")[0];
            return qualified.substr(qualified.lastIndexOf(".") + 1);
        }

        private function questId(command:Object):String
        {
            if (command.QuestID != null)
            {
                return this.resolveText(command.QuestID);
            }
            if (command.Quest != null && command.Quest.Id != null)
            {
                return this.resolveText(command.Quest.Id);
            }
            return "0";
        }

        private function textValue(value:*, fallback:String = ""):String
        {
            return value == null ? fallback : String(value);
        }

        private function numberValue(value:*, minimum:int, maximum:int):int
        {
            var parsed:Number = Number(value);
            if (isNaN(parsed))
            {
                return minimum;
            }
            return Math.max(minimum, Math.min(maximum, int(parsed)));
        }
    }
}
