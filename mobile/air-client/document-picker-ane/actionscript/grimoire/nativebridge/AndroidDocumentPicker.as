package grimoire.nativebridge
{
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.events.IOErrorEvent;
    import flash.events.StatusEvent;
    import flash.external.ExtensionContext;

    /** Android Storage Access Framework bridge used only by the AIR client. */
    public final class AndroidDocumentPicker extends EventDispatcher
    {
        public static const EXTENSION_ID:String =
            "com.unknownsecurity.grimoireexodus.mobile.documentpicker";

        private var context:ExtensionContext;
        private var pathValue:String;
        private var nameValue:String;

        public function AndroidDocumentPicker()
        {
            this.context = ExtensionContext.createExtensionContext(EXTENSION_ID, null);
            if (this.context == null)
            {
                throw new Error("The Android document picker bridge is unavailable.");
            }
            this.context.addEventListener(StatusEvent.STATUS, this.onStatus);
        }

        public function get selectedPath():String
        {
            return this.pathValue;
        }

        public function get selectedName():String
        {
            return this.nameValue;
        }

        public function browse():Boolean
        {
            return this.context != null && Boolean(this.context.call("browse"));
        }

        public function dispose():void
        {
            if (this.context == null)
            {
                return;
            }
            if (this.pathValue != null && this.pathValue.length > 0)
            {
                this.context.call("cleanup", this.pathValue);
            }
            this.context.removeEventListener(StatusEvent.STATUS, this.onStatus);
            this.context.dispose();
            this.context = null;
            this.pathValue = null;
            this.nameValue = null;
        }

        private function onStatus(event:StatusEvent):void
        {
            if (event.code == "select")
            {
                try
                {
                    var payload:Object = JSON.parse(event.level);
                    this.pathValue = payload == null || payload.path == null
                        ? null : String(payload.path);
                    this.nameValue = payload == null || payload.name == null
                        ? "selected.gbot" : String(payload.name);
                    if (this.pathValue == null || this.pathValue.length == 0)
                    {
                        throw new Error("The selected document has no readable path.");
                    }
                    this.dispatchEvent(new Event(Event.SELECT));
                }
                catch (error:Error)
                {
                    this.dispatchEvent(new IOErrorEvent(IOErrorEvent.IO_ERROR,
                        false, false, "The selected document could not be opened."));
                }
            }
            else if (event.code == "cancel")
            {
                this.dispatchEvent(new Event(Event.CANCEL));
            }
            else
            {
                this.dispatchEvent(new IOErrorEvent(IOErrorEvent.IO_ERROR,
                    false, false, event.level == null || event.level.length == 0
                        ? "The Android document picker failed." : event.level));
            }
        }
    }
}
