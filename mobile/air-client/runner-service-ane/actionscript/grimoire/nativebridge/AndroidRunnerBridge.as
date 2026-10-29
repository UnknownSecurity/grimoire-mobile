package grimoire.nativebridge
{
    import flash.external.ExtensionContext;

    /**
     * Minimal AIR bridge for the Android foreground Runner service. Only
     * generic lifecycle states cross this boundary; bot names, account data,
     * rooms, packets, and command payloads never enter Android notifications.
     */
    public final class AndroidRunnerBridge
    {
        public static const EXTENSION_ID:String =
            "com.unknownsecurity.grimoireexodus.mobile.runner";

        private var context:ExtensionContext;

        public function AndroidRunnerBridge()
        {
            this.context = ExtensionContext.createExtensionContext(EXTENSION_ID, null);
            if (this.context == null)
            {
                throw new Error("The Android Runner bridge is unavailable.");
            }
        }

        public function configure(enabled:Boolean, notifyStops:Boolean,
            keepCpuAwake:Boolean, state:String):Boolean
        {
            return this.context != null && Boolean(this.context.call("configure",
                enabled, notifyStops, keepCpuAwake, state));
        }

        public function updateStatus(state:String, notifyStops:Boolean,
            keepCpuAwake:Boolean):Boolean
        {
            return this.context != null && Boolean(this.context.call("updateStatus",
                state, notifyStops, keepCpuAwake));
        }

        public function openBatterySettings():Boolean
        {
            return this.context != null
                && Boolean(this.context.call("openBatterySettings"));
        }

        public function dispose():void
        {
            if (this.context == null)
            {
                return;
            }
            this.context.dispose();
            this.context = null;
        }
    }
}
