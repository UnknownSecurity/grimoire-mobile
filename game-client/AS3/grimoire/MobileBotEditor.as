package grimoire
{
    /**
     * Data-only editor for legacy GBot JSON. The editor never resolves a
     * Newtonsoft $type value. It edits dynamic JSON objects in place so
     * command types and properties unknown to this mobile build survive a
     * load/edit/save round trip unchanged.
     */
    public final class MobileBotEditor
    {
        private static const CONFIGURATION_TYPE:String =
            "Grimoire.Botting.Configuration, Grimoire, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null";
        private static const COMMAND_LIST_TYPE:String =
            "System.Collections.Generic.List`1[[Grimoire.Botting.IBotCommand, Grimoire, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null]], mscorlib, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089";
        private static const COMMAND_PREFIX:String = "Grimoire.Botting.Commands.";
        private static const COMMAND_SUFFIX:String =
            ", Grimoire, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null";

        private var workingDocument:Object;
        private var commandTemplates:Array;
        private var currentIndex:int = -1;
        private var changed:Boolean;

        public function MobileBotEditor()
        {
            this.commandTemplates = this.createTemplates();
        }

        public function get document():Object
        {
            return this.workingDocument;
        }

        public function get commands():Array
        {
            return this.workingDocument == null || this.workingDocument.Commands == null
                ? [] : this.workingDocument.Commands["$values"] as Array;
        }

        public function get selectedIndex():int
        {
            return this.currentIndex;
        }

        public function get selectedCommand():Object
        {
            var values:Array = this.commands;
            return this.currentIndex >= 0 && this.currentIndex < values.length
                ? values[this.currentIndex] : null;
        }

        public function get dirty():Boolean
        {
            return this.changed;
        }

        public function get templates():Array
        {
            return this.commandTemplates.concat();
        }

        public function createNew():void
        {
            this.workingDocument = {
                "$type": CONFIGURATION_TYPE,
                "Commands": {
                    "$type": COMMAND_LIST_TYPE,
                    "$values": []
                },
                "Author": "",
                "Description": "Created with Grimoire Exodus Mobile",
                "BotDelay": 500
            };
            this.attachRuntimeCommands();
            this.currentIndex = -1;
            this.changed = true;
        }

        public function load(source:Object):void
        {
            if (source == null)
            {
                this.createNew();
                return;
            }
            this.workingDocument = this.deepCopy(source);
            delete this.workingDocument.mobileCommands;
            this.ensureCommandList();
            this.attachRuntimeCommands();
            this.currentIndex = this.commands.length == 0 ? -1 : 0;
            this.changed = false;
        }

        public function select(index:int):void
        {
            var values:Array = this.commands;
            this.currentIndex = index >= 0 && index < values.length ? index : -1;
        }

        public function addTemplate(templateIndex:int):Boolean
        {
            var values:Array = this.commands;
            if (this.workingDocument == null || values.length >= MobileBotLibrary.MAX_COMMANDS
                || templateIndex < 0 || templateIndex >= this.commandTemplates.length)
            {
                return false;
            }
            var definition:Object = this.commandTemplates[templateIndex];
            var command:Object = this.deepCopy(definition.command);
            var insertAt:int = this.currentIndex < 0 ? values.length : this.currentIndex + 1;
            values.splice(insertAt, 0, command);
            this.currentIndex = insertAt;
            this.changed = true;
            return true;
        }

        public function moveSelected(offset:int):Boolean
        {
            var values:Array = this.commands;
            var destination:int = this.currentIndex + offset;
            if (this.currentIndex < 0 || destination < 0 || destination >= values.length)
            {
                return false;
            }
            var command:Object = values.splice(this.currentIndex, 1)[0];
            values.splice(destination, 0, command);
            this.currentIndex = destination;
            this.changed = true;
            return true;
        }

        public function duplicateSelected():Boolean
        {
            var values:Array = this.commands;
            if (this.selectedCommand == null || values.length >= MobileBotLibrary.MAX_COMMANDS)
            {
                return false;
            }
            var destination:int = this.currentIndex + 1;
            values.splice(destination, 0, this.deepCopy(this.selectedCommand));
            this.currentIndex = destination;
            this.changed = true;
            return true;
        }

        public function deleteSelected():Boolean
        {
            var values:Array = this.commands;
            if (this.currentIndex < 0 || this.currentIndex >= values.length)
            {
                return false;
            }
            values.splice(this.currentIndex, 1);
            if (values.length == 0)
            {
                this.currentIndex = -1;
            }
            else if (this.currentIndex >= values.length)
            {
                this.currentIndex = values.length - 1;
            }
            this.changed = true;
            return true;
        }

        public function selectedPropertyNames():Array
        {
            var command:Object = this.selectedCommand;
            var result:Array = [];
            if (command == null)
            {
                return result;
            }
            for (var property:String in command)
            {
                if (property == "$type")
                {
                    continue;
                }
                var value:* = command[property];
                if (value == null || value is String || value is Number || value is Boolean
                    || value is int || value is uint)
                {
                    result.push(property);
                }
            }
            result.sort(Array.CASEINSENSITIVE);
            return result;
        }

        public function setSelectedProperty(property:String, text:String):Boolean
        {
            var command:Object = this.selectedCommand;
            if (command == null || property == null || property.length == 0
                || property == "$type" || !command.hasOwnProperty(property))
            {
                return false;
            }

            var previous:* = command[property];
            if (previous is Boolean)
            {
                var normalized:String = text == null ? "" : text.toLowerCase();
                if (normalized != "true" && normalized != "false"
                    && normalized != "1" && normalized != "0")
                {
                    return false;
                }
                command[property] = normalized == "true" || normalized == "1";
            }
            else if (previous is Number || previous is int || previous is uint)
            {
                var numeric:Number = Number(text);
                if (isNaN(numeric))
                {
                    return false;
                }
                command[property] = numeric;
            }
            else
            {
                command[property] = text == null ? "" : text;
            }
            this.changed = true;
            return true;
        }

        public function setMetadata(property:String, value:String):Boolean
        {
            if (this.workingDocument == null || property == null
                || (property != "Author" && property != "Description" && property != "BotDelay"))
            {
                return false;
            }
            if (property == "BotDelay")
            {
                var delay:Number = Number(value);
                if (isNaN(delay))
                {
                    return false;
                }
                this.workingDocument[property] = Math.max(0, Math.min(60000, delay));
            }
            else
            {
                this.workingDocument[property] = value == null ? "" : value;
            }
            this.changed = true;
            return true;
        }

        public function commandName(command:Object = null):String
        {
            if (command == null)
            {
                command = this.selectedCommand;
            }
            var qualified:String = command == null || command["$type"] == null
                ? "Unknown" : String(command["$type"]).split(",")[0];
            var segments:Array = qualified.split(".");
            return segments.length == 0 ? "Unknown" : String(segments[segments.length - 1]);
        }

        public function commandSummary(command:Object):String
        {
            if (command == null)
            {
                return "Unknown command";
            }
            var fields:Array = ["Monster", "Map", "Cell", "ItemName", "QuestID",
                "Skill", "Index", "Delay", "Label", "PlayerName"];
            for each (var field:String in fields)
            {
                if (command.hasOwnProperty(field) && command[field] != null
                    && String(command[field]).length > 0)
                {
                    return this.commandName(command) + "  •  " + String(command[field]);
                }
            }
            return this.commandName(command);
        }

        public function templateLabel(index:int):String
        {
            return index >= 0 && index < this.commandTemplates.length
                ? String(this.commandTemplates[index].label) : "Unknown";
        }

        public function templateCategory(index:int):String
        {
            return index >= 0 && index < this.commandTemplates.length
                ? String(this.commandTemplates[index].category) : "Other";
        }

        public function exportDocument():Object
        {
            if (this.workingDocument == null)
            {
                return null;
            }
            var copy:Object = this.deepCopy(this.workingDocument);
            delete copy.mobileCommands;
            return copy;
        }

        public function markSaved():void
        {
            this.changed = false;
        }

        private function attachRuntimeCommands():void
        {
            this.workingDocument.mobileCommands = this.workingDocument.Commands["$values"];
        }

        private function ensureCommandList():void
        {
            if (this.workingDocument.Commands == null)
            {
                this.workingDocument.Commands = { "$type": COMMAND_LIST_TYPE, "$values": [] };
            }
            if (!(this.workingDocument.Commands["$values"] is Array))
            {
                this.workingDocument.Commands["$values"] = [];
            }
        }

        private function createTemplates():Array
        {
            var result:Array = [
                this.template("Combat", "Kill monster", "Combat.CmdKill", { Monster: "*", Packet: false }),
                this.template("Combat", "Kill for item", "Combat.CmdKillFor",
                    { Monster: "*", ItemName: "", ItemType: 0, Quantity: "1" }),
                this.template("Combat", "Attack monster", "Combat.CmdAttack", { Monster: "*" }),
                this.template("Combat", "Use skill", "Combat.CmdUseSkill",
                    { Skill: "", Index: "1", SafeHp: 0, SafeMp: 0, Wait: false }),
                this.template("Combat", "Use skill set", "Combat.CmdSkillSet", { Name: "" }),
                this.template("Combat", "Rest", "Combat.CmdRest", { Full: false }),
                this.template("Map", "Join map", "Map.CmdJoin",
                    { Map: "", Cell: "Enter", Pad: "Spawn" }),
                this.template("Map", "Join private map", "Map.CmdJoin2",
                    { Map: "", Room: "1e99", Cell: "Enter", Pad: "Spawn" }),
                this.template("Map", "Move to cell", "Map.CmdMoveToCell",
                    { Cell: "Enter", Pad: "Spawn" }),
                this.template("Map", "Walk to point", "Map.CmdWalk", { X: "0", Y: "0" }),
                this.template("Map", "Set spawn", "Map.CmdSetSpawn", {}),
                this.template("Map", "Get map item", "Item.CmdMapItem2", { ItemId: "" }),
                this.template("Quest", "Accept quest", "Quest.CmdAcceptQuest2", { QuestID: "" }),
                this.template("Quest", "Complete quest", "Quest.CmdCompleteQuest2",
                    { QuestID: "", ItemID: "-1" }),
                this.template("Item", "Get drop", "Item.CmdGetDrop", { ItemName: "" }),
                this.template("Item", "Equip item", "Item.CmdEquip", { ItemName: "" }),
                this.template("Item", "Buy item", "Item.CmdBuy", { ShopId: 0, ItemName: "" }),
                this.template("Item", "Sell item", "Item.CmdSell", { ItemName: "" }),
                this.template("Item", "Use boost", "Item.CmdUseBoost", { ItemName: "" }),
                this.template("Item", "Bank transfer", "Item.CmdBankTransfer",
                    { TransferFromBank: true, ItemName: "" }),
                this.template("Item", "Drop whitelist", "Item.CmdWhitelist", { Item: "", State: 3 }),
                this.template("Misc", "Delay", "Misc.CmdDelay", { Delay: 1000 }),
                this.template("Misc", "Set bot delay", "Misc.CmdBotDelay", { Delay: 500 }),
                this.template("Misc", "Go to player", "Misc.CmdGotoPlayer", { PlayerName: "" }),
                this.template("Misc", "Client message", "Misc.CmdClientMessage", { Messages: "" }),
                this.template("Misc", "Send packet", "Misc.CmdPacket2",
                    { Packet: "", Client: false, Delay: 2000 }),
                this.template("Variable", "Set variable", "Misc.Statements.CmdSetVar",
                    { Value1: "", Value2: "" }),
                this.template("Variable", "Update variable", "Misc.Statements.CmdUpdateVar",
                    { Value1: "", Value2: "" }),
                this.template("Variable", "Set integer", "Misc.CmdInt",
                    { type: 0, Int: "", Value: 0 }),
                this.template("Condition", "Item in inventory", "Misc.Statements.CmdInInventory",
                    { Value1: "", Value2: "1" }),
                this.template("Condition", "Item not in inventory", "Misc.Statements.CmdNotInInventory",
                    { Value1: "", Value2: "1" }),
                this.template("Condition", "Temp item present", "Misc.Statements.CmdInTemp",
                    { Value1: "", Value2: "1" }),
                this.template("Condition", "Level greater than", "Misc.Statements.CmdLevelGreaterThan",
                    { Value1: "", Value2: "" }),
                this.template("Condition", "Level less than", "Misc.Statements.CmdLevelLessThan",
                    { Value1: "", Value2: "" }),
                this.template("Condition", "Map is", "Misc.Statements.CmdMapIs",
                    { Value1: "", Value2: "" }),
                this.template("Condition", "Cell is", "Misc.Statements.CmdCellIs",
                    { Value1: "", Value2: "" }),
                this.template("Condition", "Quest in progress", "Misc.Statements.CmdQuestInProgress",
                    { Value1: "", Value2: "" }),
                this.template("Flow", "Label", "Misc.CmdLabel", { Name: "" }),
                this.template("Flow", "Go to label", "Misc.CmdGotoLabel", { Label: "" }),
                this.template("Flow", "Change index", "Misc.CmdIndex", { Type: 2, Index: 1 }),
                this.template("Flow", "Restart bot", "Misc.CmdRestart", {}),
                this.template("Flow", "Stop bot", "Misc.CmdStop", {}),
                this.template("Flow", "Stop with message", "Misc.CmdStopBotWithMessage",
                    { Message: "BOT STOPPED" })
            ];
            this.appendExtendedActionTemplates(result);
            this.appendStatementTemplates(result);
            return result;
        }

        private function appendExtendedActionTemplates(target:Array):void
        {
            var definitions:Array = [
                ["Quest", "Accept quest (legacy)", "Quest.CmdAcceptQuest", { QuestID: "" }],
                ["Quest", "Complete quest (legacy)", "Quest.CmdCompleteQuest",
                    { QuestID: "", ItemID: "-1" }],
                ["Item", "Bank item list", "Misc.CmdBankList", {}],
                ["Item", "Swap bank items", "Item.CmdBankSwap",
                    { BankItemName: "", InventoryItemName: "" }],
                ["Misc", "Beep", "Misc.CmdBeep", { Times: 1 }],
                ["Layout", "Blank row", "Misc.CmdBlank", {}],
                ["Layout", "Text row", "Misc.CmdBlank2", { Text: "" }],
                ["Layout", "Colored text row", "Misc.CmdBlank3",
                    { Text: "", Alpha: 255, R: 160, G: 110, B: 255 }],
                ["Misc", "Set bot delay (variable)", "Misc.CmdBotDelay2", { Delay: "500" }],
                ["Item", "Buy item from shop", "Item.CmdBuy2",
                    { ShopId: "", ItemName: "", Manual: false }],
                ["Item", "Buy item by ID", "Item.CmdBuyByID",
                    { ItemID: "", ShopID: "", ShopItemID: "", Manual: false }],
                ["Item", "Buy item fast", "Item.CmdBuyFast",
                    { ItemName: "", Manual: false }],
                ["Item", "Buy item by ID fast", "Item.CmdBuyFastByID",
                    { ItemID: "", ShopID: "", ShopItemID: "", Manual: false }],
                ["Combat", "Cancel auto attack", "Combat.CmdCancelAutoAttack", {}],
                ["Combat", "Cancel target", "Combat.CmdCancelTarget", {}],
                ["Misc", "Change name or guild", "Misc.CmdChange", { Guild: false, Text: "" }],
                ["Variable", "Clear temporary values", "Misc.CmdClearTemp", {}],
                ["Misc", "Follow player", "Misc.CmdFollow", { Name: "" }],
                ["Variable", "Store current class", "Misc.Statements.CmdGetClassWithVar",
                    { Value1: "class", Value2: "" }],
                ["Map", "Jump to cell", "Map.CmdJump", { Cell: "Enter", Pad: "Spawn" }],
                ["Item", "Load shop", "Item.CmdLoad", { ShopId: 0 }],
                ["Item", "Load shop (variable)", "Item.CmdLoad2", { ShopId: "" }],
                ["Flow", "Load nested bot", "Misc.CmdLoadBot",
                    { BotFileName: "", BotFilePath: "" }],
                ["Map", "Load map SWF", "Misc.CmdLoadMapSwf", { Name: "" }],
                ["Misc", "Write log entry", "Misc.CmdLog", { Text: "", Debug: false }],
                ["Misc", "Log out", "Misc.CmdLogout", {}],
                ["Map", "Get map item (numeric)", "Item.CmdMapItem", { ItemId: 0 }],
                ["Misc", "Send packet (legacy)", "Misc.CmdPacket",
                    { Packet: "", Client: false }],
                ["Misc", "Packet spam", "Item.CmdPacketlist2",
                    { Type: 0, Packet: "", Delay: 1000 }],
                ["Quest", "Manage quest list", "Quest.CmdQuestlist",
                    { QuestID: "", ItemID: "-1", state: 0 }],
                ["Flow", "Return from nested bot", "Misc.CmdReturn", {}],
                ["Misc", "Set client level", "Misc.CmdSetClientLevel", {}],
                ["Misc", "Set frame rate", "Misc.CmdSetFPS", { FPS: 30 }],
                ["Combat", "Toggle provoke in cell", "Misc.CmdToggleProvoke", { Type: 2 }],
                ["Combat", "Toggle provoke in map", "Misc.CmdToggleProvokeInMap",
                    { Type: 2, ProvokePacket: "" }],
                ["Combat", "Use skill (variable)", "Combat.CmdUseSkill2",
                    { Skill: "", Index: "1", SafeHp: 0, SafeMp: 0,
                        Wait: false, Monster: "" }]
            ];
            for each (var definition:Array in definitions)
            {
                this.appendTemplateIfMissing(target, String(definition[0]),
                    String(definition[1]), String(definition[2]), definition[3]);
            }
        }

        private function appendStatementTemplates(target:Array):void
        {
            var names:Array = [
                "CmdAvailableMonstersGreaterThan", "CmdAvailableMonstersLessThan",
                "CmdCellIs", "CmdCellIsNot", "CmdEquipped",
                "CmdFactionRankGreaterThan", "CmdFactionRankLessThan",
                "CmdGoldGreaterThan", "CmdGoldLessThan", "CmdHealthGreaterThan",
                "CmdHealthLessThan", "CmdHealthPercentageGreaterThan",
                "CmdHealthPercentageLessThan", "CmdInBank", "CmdInCombat",
                "CmdInHouse", "CmdInInventory", "CmdInTemp", "CmdIntEqualInt",
                "CmdIntGreaterThan", "CmdIntIs", "CmdIntIsNot", "CmdIntLessThan",
                "CmdIntNotEqualInt", "CmdIsMaxStack", "CmdIsMember",
                "CmdIsNotMaxStack", "CmdIsNotMember", "CmdItemNotPickupable",
                "CmdItemPickupable", "CmdLevelGreaterThan", "CmdLevelIs",
                "CmdLevelLessThan", "CmdListInInv", "CmdManaGreaterThan",
                "CmdManaLessThan", "CmdMapIs", "CmdMapIsNot",
                "CmdMonsterHealthGreaterThan", "CmdMonsterHealthLessThan",
                "CmdMonsterInRoom", "CmdMonsterNotInRoom", "CmdNotEquipped",
                "CmdNotInBank", "CmdNotInCombat", "CmdNotInHouse",
                "CmdNotInInventory", "CmdNotInTemp", "CmdPlayerAuraIsActive",
                "CmdPlayerAuraIsNotActive", "CmdPlayerAuraStringValIs",
                "CmdPlayerAuraStringValIsNot", "CmdPlayerAuraValIs",
                "CmdPlayerAuraValIsGreaterThan", "CmdPlayerAuraValIsLessThan",
                "CmdPlayerAuraValIsNot", "CmdPlayerEquippedClass",
                "CmdPlayerInCombat", "CmdPlayerInRoom", "CmdPlayerIsInCell",
                "CmdPlayerIsInMyCell", "CmdPlayerIsNotInCell",
                "CmdPlayerIsNotInMyCell", "CmdPlayerNotEquippedClass",
                "CmdPlayerNotInCombat", "CmdPlayerNotInRoom", "CmdPlayersGreaterThan",
                "CmdPlayersInCellGreaterThan", "CmdPlayersInCellLessThan",
                "CmdPlayersInMyCellGreaterThan", "CmdPlayersInMyCellLessThan",
                "CmdPlayersLessThan", "CmdQuestAvailable", "CmdQuestCompleted",
                "CmdQuestInProgress", "CmdQuestNotAvailable", "CmdQuestNotCompleted",
                "CmdQuestNotInProgress", "CmdSkillIsAvailable",
                "CmdSkillIsNotAvailable", "CmdTargetAuraIsActive",
                "CmdTargetAuraIsNotActive", "CmdTargetAuraStringValIs",
                "CmdTargetAuraStringValIsNot", "CmdTargetAuraValIs",
                "CmdTargetAuraValIsGreaterThan", "CmdTargetAuraValIsLessThan",
                "CmdTargetAuraValIsNot", "CmdVisibleMonstersGreaterThan",
                "CmdVisibleMonstersLessThan"
            ];
            for each (var name:String in names)
            {
                this.appendTemplateIfMissing(target, "Condition",
                    this.friendlyCommandName(name), "Misc.Statements." + name,
                    { Value1: "", Value2: "" });
            }
        }

        private function appendTemplateIfMissing(target:Array, category:String,
            label:String, typeName:String, fields:Object):void
        {
            var expected:String = typeName.substr(typeName.lastIndexOf(".") + 1);
            for each (var definition:Object in target)
            {
                if (this.commandName(definition.command) == expected)
                {
                    return;
                }
            }
            target.push(this.template(category, label, typeName, fields));
        }

        private function friendlyCommandName(name:String):String
        {
            var value:String = name.indexOf("Cmd") == 0 ? name.substr(3) : name;
            return value.replace(/([a-z0-9])([A-Z])/g, "$1 $2");
        }

        private function template(category:String, label:String, typeName:String, fields:Object):Object
        {
            // Newtonsoft metadata is most portable when $type is the first
            // serialized property, matching desktop-generated GBot files.
            var command:Object = { "$type": COMMAND_PREFIX + typeName + COMMAND_SUFFIX };
            for (var property:String in fields)
            {
                command[property] = fields[property];
            }
            return { category: category, label: label, command: command };
        }

        private function deepCopy(value:Object):Object
        {
            return JSON.parse(JSON.stringify(value));
        }
    }
}
