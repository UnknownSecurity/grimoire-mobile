package grimoire
{
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.events.TimerEvent;
    import flash.utils.Timer;
    import grimoire.game.Network;
    import grimoire.game.DropStack;
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
            this.commands = list.concat();
            // Older GBots commonly omit BotDelay or save it as zero. Keep a
            // small cooperative delay so AQW can finish target and asset state
            // updates between commands on slower Android devices.
            this.botDelay = document.BotDelay == null ? 500
                : this.numberValue(document.BotDelay, 10, 60000);
            this.labels = {};
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
            if (this.index >= this.commands.length)
            {
                this.stop("BOT COMPLETED");
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
                        Player.join(this.textValue(command.Map),
                            this.textValue(command.Cell, "Enter"),
                            this.textValue(command.Pad, "Spawn"));
                        delay = 1800;
                        break;
                    case "CmdJoin2":
                        var map:String = this.textValue(command.Map);
                        var room:String = this.textValue(command.Room);
                        Player.join(map + (room.length > 0 ? "-" + room : ""),
                            this.textValue(command.Cell, "Enter"),
                            this.textValue(command.Pad, "Spawn"));
                        delay = 1800;
                        break;
                    case "CmdMoveToCell":
                    case "CmdJump":
                        Player.jump(this.textValue(command.Cell, "Enter"),
                            this.textValue(command.Pad, "Spawn"));
                        delay = 350;
                        break;
                    case "CmdWalk":
                        Player.walkToPoint(this.textValue(command.X), this.textValue(command.Y));
                        delay = 200;
                        break;
                    case "CmdAttack":
                        Player.attackMonster(this.textValue(command.Monster, "*"));
                        delay = 250;
                        break;
                    case "CmdKill":
                        this.killTarget = this.textValue(command.Monster, "*");
                        this.killForItem = null;
                        this.killEngaged = false;
                        this.waitingForKill = true;
                        this.continueKill();
                        return;
                    case "CmdKillFor":
                        this.killTarget = this.textValue(command.Monster, "*");
                        this.killForItem = this.textValue(command.ItemName);
                        this.killForQuantity = this.numberValue(command.Quantity, 1, 999999);
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
                        Skill.skillAction(this.textValue(command.Index, "1"));
                        delay = 250;
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
                            this.textValue(command.ItemID, "-1"));
                        delay = 750;
                        break;
                    case "CmdSetSpawn":
                        World.setSpawnPoint();
                        break;
                    case "CmdGetDrop":
                        DropStack.getDrop(this.textValue(command.ItemName));
                        delay = 350;
                        break;
                    case "CmdEquip":
                        var itemId:String = this.inventoryItemId(this.textValue(command.ItemName));
                        if (itemId.length > 0)
                        {
                            Player.equipItem(itemId);
                        }
                        delay = 500;
                        break;
                    case "CmdBuy":
                    case "CmdBuy2":
                        Shop.buyItem(this.textValue(command.ItemName));
                        delay = 500;
                        break;
                    case "CmdGotoPlayer":
                        Player.goTo(this.textValue(command.PlayerName));
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
                    case "CmdToggleProvoke":
                        if (int(command.Type) != 0)
                        {
                            Setting.provokeMonsters();
                        }
                        break;
                    case "CmdClientMessage":
                        Root.gameMessage(this.textValue(command.Messages));
                        break;
                    case "CmdPacket":
                    case "CmdPacket2":
                        var preparedPacket:String = this.preparePacket(this.textValue(command.Packet));
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
                        this.packetSpamPacket = this.textValue(command.Packet);
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
                    for (var skill:int = 1; skill <= 4; skill++)
                    {
                        Skill.skillAction(String(skill));
                    }
                    this.schedule(500);
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
            var value1:String = this.textValue(command.Value1);
            var value2:String = this.textValue(command.Value2);
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
                return String(command.QuestID);
            }
            if (command.Quest != null && command.Quest.Id != null)
            {
                return String(command.Quest.Id);
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
