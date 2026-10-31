package grimoire
{
    import grimoire.nativebridge.AndroidDocumentPicker;

    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.events.IOErrorEvent;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.utils.ByteArray;

    /**
     * Bounded, data-only GBot library for AIR. It never resolves $type values
     * into runtime classes. Community files are read-only and imported bots
     * remain inside application storage.
     */
    public final class MobileBotLibrary extends EventDispatcher
    {
        public static const CHANGED:String = "mobileBotLibraryChanged";
        public static const MAX_BOT_BYTES:uint = 2 * 1024 * 1024;
        public static const MAX_COMMANDS:int = 5000;

        private var items:Array = [];
        private var picker:AndroidDocumentPicker;
        private var currentIndex:int = -1;
        private var currentDocument:Object;
        private var currentStatus:String = "Select a bot to inspect it.";

        public function MobileBotLibrary()
        {
            this.refresh();
        }

        public function get entries():Array
        {
            return this.items.concat();
        }

        public function get selectedIndex():int
        {
            return this.currentIndex;
        }

        public function get selectedEntry():Object
        {
            return this.currentIndex >= 0 && this.currentIndex < this.items.length
                ? this.items[this.currentIndex]
                : null;
        }

        public function get selectedDocument():Object
        {
            return this.currentDocument;
        }

        public function get status():String
        {
            return this.currentStatus;
        }

        /**
         * Resolves a nested CmdLoadBot reference only against bots already in
         * the bounded mobile library. Desktop absolute paths are reduced to a
         * file name and are never opened directly on Android.
         */
        public function loadKnownDocument(reference:String):Object
        {
            var requested:String = this.normalizedBotReference(reference);
            if (requested.length == 0)
            {
                return null;
            }
            for each (var entry:Object in this.items)
            {
                if (entry == null || entry.file == null)
                {
                    continue;
                }
                var entryName:String = this.normalizedBotReference(String(entry.name));
                var fileName:String = this.normalizedBotReference(File(entry.file).name);
                if (requested == entryName || requested == fileName)
                {
                    try
                    {
                        return this.readDocument(entry.file as File);
                    }
                    catch (error:Error)
                    {
                        return null;
                    }
                }
            }
            return null;
        }

        public function refresh():void
        {
            var previousPath:String = this.selectedEntry == null ? "" : this.selectedEntry.path;
            var refreshed:Array = [];
            this.appendDirectory(refreshed,
                File.applicationDirectory.resolvePath("bots/community"), true);
            this.appendDirectory(refreshed,
                File.applicationStorageDirectory.resolvePath("Bots"), false);
            refreshed.sortOn("sortKey", Array.CASEINSENSITIVE);
            this.items = refreshed;
            this.currentIndex = -1;
            this.currentDocument = null;

            for (var i:int = 0; i < this.items.length; i++)
            {
                if (this.items[i].path == previousPath)
                {
                    this.select(i);
                    return;
                }
            }
            this.currentStatus = this.items.length == 0
                ? "No bots yet. Import a legacy .gbot file."
                : "Select a bot to inspect it.";
            this.dispatchEvent(new Event(CHANGED));
        }

        public function select(index:int):void
        {
            if (index < 0 || index >= this.items.length)
            {
                this.currentIndex = -1;
                this.currentDocument = null;
                this.currentStatus = "Select a bot to inspect it.";
                this.dispatchEvent(new Event(CHANGED));
                return;
            }

            this.currentIndex = index;
            try
            {
                this.currentDocument = this.readDocument(this.items[index].file as File);
                this.currentStatus = "Loaded safely for mobile inspection.";
            }
            catch (error:Error)
            {
                this.currentDocument = null;
                this.currentStatus = error.message;
            }
            this.dispatchEvent(new Event(CHANGED));
        }

        public function browseForImport():void
        {
            if (this.picker != null)
            {
                return;
            }
            try
            {
                this.picker = new AndroidDocumentPicker();
                this.picker.addEventListener(Event.SELECT, this.onFileSelected);
                this.picker.addEventListener(Event.CANCEL, this.onFileCancelled);
                this.picker.addEventListener(IOErrorEvent.IO_ERROR, this.onImportError);
                if (!this.picker.browse())
                {
                    this.finishPicker("The Android document picker is already open.");
                }
            }
            catch (error:Error)
            {
                this.finishPicker("The Android document picker could not be opened.");
            }
        }

        public function deleteSelected():void
        {
            var entry:Object = this.selectedEntry;
            if (entry == null)
            {
                this.currentStatus = "Select an imported bot first.";
            }
            else if (entry.community)
            {
                this.currentStatus = "Community bots are read-only.";
            }
            else
            {
                try
                {
                    File(entry.file).deleteFile();
                    this.currentStatus = "Imported bot removed.";
                    this.currentIndex = -1;
                    this.currentDocument = null;
                    this.refresh();
                    return;
                }
                catch (error:Error)
                {
                    this.currentStatus = "The imported bot could not be removed.";
                }
            }
            this.dispatchEvent(new Event(CHANGED));
        }

        public function clearImportedBots():void
        {
            var directory:File = File.applicationStorageDirectory.resolvePath("Bots");
            if (directory.exists && directory.isDirectory)
            {
                try
                {
                    for each (var file:File in directory.getDirectoryListing())
                    {
                        if (!file.isDirectory && file.extension != null
                            && file.extension.toLowerCase() == "gbot")
                        {
                            file.deleteFile();
                        }
                    }
                }
                catch (error:Error)
                {
                    this.currentStatus = "Some imported bots could not be removed.";
                    this.dispatchEvent(new Event(CHANGED));
                    return;
                }
            }
            this.currentStatus = "Mobile data reset. Community bots were preserved.";
            this.refresh();
        }

        public function saveEditedBot(document:Object, requestedName:String = null,
            forceNewCopy:Boolean = false):Boolean
        {
            if (document == null)
            {
                this.currentStatus = "There is no edited bot to save.";
                this.dispatchEvent(new Event(CHANGED));
                return false;
            }

            try
            {
                var copy:Object = JSON.parse(JSON.stringify(document));
                delete copy.mobileCommands;
                var serialized:String = this.serializeLegacyJson(copy);
                // Reuse the import validator before any bytes reach persistent
                // storage. This keeps edited and imported bots on one contract.
                this.parseDocument(serialized);

                var bytes:ByteArray = new ByteArray();
                bytes.writeUTFBytes(serialized);
                if (bytes.length <= 0 || bytes.length > MAX_BOT_BYTES)
                {
                    throw new Error("This bot exceeds the safe mobile file limit.");
                }

                var folder:File = File.applicationStorageDirectory.resolvePath("Bots");
                if (!folder.exists)
                {
                    folder.createDirectory();
                }

                var entry:Object = this.selectedEntry;
                var destination:File;
                var savedAsCopy:Boolean = forceNewCopy || entry == null || entry.community;
                if (!savedAsCopy && File(entry.file).parent.url == folder.url)
                {
                    destination = entry.file as File;
                }
                else
                {
                    var baseName:String = requestedName;
                    if (baseName == null || baseName.replace(/^\s+|\s+$/g, "").length == 0)
                    {
                        baseName = entry == null ? "Untitled Bot" : String(entry.name) + " Mobile";
                    }
                    destination = this.uniqueDestination(folder, this.safeFileName(baseName));
                }

                var temporary:File = folder.resolvePath("." + destination.name + ".tmp");
                if (temporary.exists)
                {
                    temporary.deleteFile();
                }
                var stream:FileStream = new FileStream();
                try
                {
                    stream.open(temporary, FileMode.WRITE);
                    bytes.position = 0;
                    stream.writeBytes(bytes, 0, bytes.length);
                }
                finally
                {
                    stream.close();
                }
                temporary.moveTo(destination, true);

                this.currentStatus = savedAsCopy ? "Editable bot copy saved." : "Bot changes saved.";
                this.refresh();
                this.selectPath(destination.url, this.currentStatus);
                return true;
            }
            catch (error:Error)
            {
                this.currentStatus = error.message == null || error.message.length == 0
                    ? "The edited bot could not be saved." : error.message;
                this.dispatchEvent(new Event(CHANGED));
                return false;
            }
        }

        private function appendDirectory(target:Array, directory:File, community:Boolean):void
        {
            if (directory == null || !directory.exists || !directory.isDirectory)
            {
                return;
            }
            try
            {
                var files:Array = directory.getDirectoryListing();
                for each (var file:File in files)
                {
                    if (!file.isDirectory && file.extension != null
                        && file.extension.toLowerCase() == "gbot")
                    {
                        target.push({
                            name: this.displayName(file.name),
                            sortKey: this.displayName(file.name).toLowerCase(),
                            community: community,
                            path: file.url,
                            file: file
                        });
                    }
                }
            }
            catch (error:Error)
            {
                // A missing or unreadable optional directory is simply empty.
            }
        }

        private function readDocument(file:File):Object
        {
            if (file == null || !file.exists || file.isDirectory)
            {
                throw new Error("The selected bot is no longer available.");
            }
            if (file.size <= 0 || file.size > MAX_BOT_BYTES)
            {
                throw new Error("This bot exceeds the safe mobile file limit.");
            }
            return this.parseDocument(this.readFileText(file));
        }

        private function readFileText(file:File):String
        {
            if (file == null || !file.exists || file.isDirectory)
            {
                throw new Error("The selected bot is no longer available.");
            }
            if (file.size <= 0 || file.size > MAX_BOT_BYTES)
            {
                throw new Error("This bot exceeds the safe mobile file limit.");
            }
            var stream:FileStream = new FileStream();
            var raw:String;
            try
            {
                stream.open(file, FileMode.READ);
                raw = stream.readUTFBytes(stream.bytesAvailable);
            }
            finally
            {
                stream.close();
            }
            return raw;
        }

        private function parseDocument(raw:String):Object
        {
            var document:Object;
            try
            {
                document = JSON.parse(raw);
            }
            catch (error:Error)
            {
                throw new Error("This file is not valid GBot JSON.");
            }

            var rootType:String = document == null || document["$type"] == null
                ? "" : String(document["$type"]);
            if (rootType.indexOf("Grimoire.Botting.Configuration,") != 0)
            {
                throw new Error("Unsupported GBot root type.");
            }
            var commands:Array = document.Commands == null
                ? null : document.Commands["$values"] as Array;
            if (commands == null)
            {
                throw new Error("The GBot command list is missing.");
            }
            if (commands.length > MAX_COMMANDS)
            {
                throw new Error("This GBot has too many commands for mobile.");
            }
            document.mobileCommands = commands;
            return document;
        }

        private function serializeLegacyJson(value:*, depth:int = 0):String
        {
            if (depth > 128)
            {
                throw new Error("This bot exceeds the safe JSON nesting limit.");
            }
            if (value === null)
            {
                return "null";
            }
            if (value is String)
            {
                return JSON.stringify(String(value));
            }
            if (value is Boolean)
            {
                return Boolean(value) ? "true" : "false";
            }
            if (value is Number || value is int || value is uint)
            {
                var number:Number = Number(value);
                if (isNaN(number) || !isFinite(number))
                {
                    throw new Error("A bot property contains an invalid number.");
                }
                return String(number);
            }
            if (value is Array)
            {
                var parts:Array = [];
                var array:Array = value as Array;
                for each (var item:* in array)
                {
                    parts.push(this.serializeLegacyJson(item, depth + 1));
                }
                return "[" + parts.join(",") + "]";
            }

            var keys:Array = [];
            for (var key:String in value)
            {
                if (key != "mobileCommands")
                {
                    keys.push(key);
                }
            }
            keys.sort(this.compareLegacyJsonKeys);

            var properties:Array = [];
            for each (key in keys)
            {
                properties.push(JSON.stringify(key) + ":"
                    + this.serializeLegacyJson(value[key], depth + 1));
            }
            return "{" + properties.join(",") + "}";
        }

        private function compareLegacyJsonKeys(left:Object, right:Object):Number
        {
            var leftKey:String = String(left);
            var rightKey:String = String(right);
            var leftRank:int = this.legacyMetadataRank(leftKey);
            var rightRank:int = this.legacyMetadataRank(rightKey);
            if (leftRank != rightRank)
            {
                return leftRank - rightRank;
            }
            leftKey = leftKey.toLowerCase();
            rightKey = rightKey.toLowerCase();
            return leftKey < rightKey ? -1 : (leftKey > rightKey ? 1 : 0);
        }

        private function legacyMetadataRank(key:String):int
        {
            if (key == "$type") return 0;
            if (key == "$id") return 1;
            if (key == "$ref") return 2;
            if (key == "$values") return 3;
            return 10;
        }

        private function onFileSelected(event:Event):void
        {
            if (this.picker == null)
            {
                this.finishPicker("The Android document picker closed unexpectedly.");
                return;
            }
            try
            {
                this.currentStatus = "Importing bot...";
                this.dispatchEvent(new Event(CHANGED));

                var selectedFile:File = new File(this.picker.selectedPath);
                var raw:String = this.readFileText(selectedFile);
                this.parseDocument(raw);

                var folder:File = File.applicationStorageDirectory.resolvePath("Bots");
                if (!folder.exists)
                {
                    folder.createDirectory();
                }
                var fileName:String = this.safeFileName(this.picker.selectedName);
                var destination:File = this.uniqueDestination(folder, fileName);
                var stream:FileStream = new FileStream();
                try
                {
                    stream.open(destination, FileMode.WRITE);
                    stream.writeUTFBytes(raw);
                }
                finally
                {
                    stream.close();
                }
                this.finishPicker("Bot imported.");
                this.refresh();
                this.selectPath(destination.url, "Bot imported and selected.");
            }
            catch (error:Error)
            {
                this.finishPicker(error.message.length > 0
                    ? error.message : "The selected bot could not be imported.");
            }
        }

        private function onFileCancelled(event:Event):void
        {
            this.finishPicker("Import cancelled.");
        }

        private function onImportError(event:Event):void
        {
            var ioError:IOErrorEvent = event as IOErrorEvent;
            this.finishPicker(ioError == null || ioError.text.length == 0
                ? "The selected bot could not be read." : ioError.text);
        }

        private function finishPicker(message:String):void
        {
            if (this.picker != null)
            {
                this.picker.removeEventListener(Event.SELECT, this.onFileSelected);
                this.picker.removeEventListener(Event.CANCEL, this.onFileCancelled);
                this.picker.removeEventListener(IOErrorEvent.IO_ERROR, this.onImportError);
                this.picker.dispose();
                this.picker = null;
            }
            this.currentStatus = message;
            this.dispatchEvent(new Event(CHANGED));
        }

        private function selectPath(path:String, message:String = null):void
        {
            for (var i:int = 0; i < this.items.length; i++)
            {
                if (this.items[i].path == path)
                {
                    this.select(i);
                    if (message != null && this.currentDocument != null)
                    {
                        this.currentStatus = message;
                        this.dispatchEvent(new Event(CHANGED));
                    }
                    return;
                }
            }
        }

        private function uniqueDestination(folder:File, fileName:String):File
        {
            var stem:String = fileName.substr(0, fileName.length - 5);
            var candidate:File = folder.resolvePath(fileName);
            var suffix:int = 2;
            while (candidate.exists && suffix < 1000)
            {
                candidate = folder.resolvePath(stem + " (" + suffix + ").gbot");
                suffix++;
            }
            return candidate;
        }

        private function safeFileName(value:String):String
        {
            var result:String = value == null ? "bot.gbot" : value;
            result = result.replace(/[\\\/:*?"<>|]/g, "_");
            if (result.toLowerCase().lastIndexOf(".gbot") != result.length - 5)
            {
                result += ".gbot";
            }
            return result.length > 96 ? result.substr(0, 91) + ".gbot" : result;
        }

        private function displayName(value:String):String
        {
            if (value == null)
            {
                return "Untitled bot";
            }
            return value.toLowerCase().lastIndexOf(".gbot") == value.length - 5
                ? value.substr(0, value.length - 5)
                : value;
        }

        private function normalizedBotReference(value:String):String
        {
            if (value == null)
            {
                return "";
            }
            var normalized:String = value.replace(/\\/g, "/");
            normalized = normalized.substr(normalized.lastIndexOf("/") + 1)
                .replace(/^\s+|\s+$/g, "").toLowerCase();
            return normalized.lastIndexOf(".gbot") == normalized.length - 5
                ? normalized.substr(0, normalized.length - 5) : normalized;
        }
    }
}
