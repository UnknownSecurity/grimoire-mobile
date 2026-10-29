package com.unknownsecurity.grimoireexodus.mobile.ruffle

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.os.SystemClock
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import com.unknownsecurity.grimoireexodus.domain.GameTransport
import com.unknownsecurity.grimoireexodus.model.ActionResult
import com.unknownsecurity.grimoireexodus.model.ConnectionState
import com.unknownsecurity.grimoireexodus.model.GameAction
import com.unknownsecurity.grimoireexodus.model.GameCapability
import com.unknownsecurity.grimoireexodus.model.MobileBridgeProfile
import com.unknownsecurity.grimoireexodus.model.MobileBridgeSession
import com.unknownsecurity.grimoireexodus.model.MobileSessionSignal
import com.unknownsecurity.grimoireexodus.model.TransportStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import kotlin.coroutines.resume
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Experimental Android transport. Ruffle owns the AVM2/display surface while the
 * checked-in ActionScript bridge preserves the same callback names used by the
 * desktop client. No WinForms or desktop updater code is referenced here.
 */
class RuffleGameTransport(
    context: Context,
) : GameTransport, AutoCloseable {
    private val appContext = context.applicationContext
    private val mutableStatus = MutableStateFlow(offlineStatus())
    private val mutablePackets = MutableStateFlow<List<RufflePacket>>(emptyList())
    private val mutableInGame = MutableStateFlow(false)
    private val mutableProfile = MutableStateFlow(RufflePlayerProfile())
    private val mutableBotStatus = MutableStateFlow("BOT IDLE")
    private val serverMap = RuffleServerMap()
    private val javascriptBridge = JavascriptBridge()
    private val optionState = ConcurrentHashMap<String, Boolean>()
    private val optionExecutor = Executors.newSingleThreadScheduledExecutor()
    private val sessionPollInFlight = AtomicBoolean(false)
    private var loopbackServer: RuffleLoopbackServer? = null
    private var webView: WebView? = null
    private var lastAutoSaveAt: Long = 0

    init {
        optionExecutor.scheduleWithFixedDelay(
            ::applyRecurringOptions,
            500,
            500,
            TimeUnit.MILLISECONDS,
        )
        optionExecutor.scheduleWithFixedDelay(
            ::pollSession,
            SESSION_POLL_INITIAL_DELAY_MILLIS,
            SESSION_POLL_INTERVAL_MILLIS,
            TimeUnit.MILLISECONDS,
        )
    }

    override val status: StateFlow<TransportStatus> = mutableStatus.asStateFlow()
    val packets: StateFlow<List<RufflePacket>> = mutablePackets.asStateFlow()
    val inGame: StateFlow<Boolean> = mutableInGame.asStateFlow()
    val profile: StateFlow<RufflePlayerProfile> = mutableProfile.asStateFlow()
    val botStatus: StateFlow<String> = mutableBotStatus.asStateFlow()

    @SuppressLint("SetJavaScriptEnabled")
    fun attach(target: WebView) {
        if (webView === target) return
        detach()

        val host = runCatching { RuffleLoopbackServer(appContext, serverMap) }
            .getOrElse {
                mutableStatus.value = failedStatus("The local Ruffle host could not start.")
                return
            }
        loopbackServer = host
        webView = target
        mutableStatus.value = TransportStatus(
            connection = ConnectionState.Connecting,
            summary = "Starting the Ruffle AQW engine",
            bridgeVersion = BRIDGE_VERSION,
        )

        target.setBackgroundColor(Color.BLACK)
        target.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = false
            allowFileAccess = false
            allowContentAccess = false
            mediaPlaybackRequiresUserGesture = false
            setSupportMultipleWindows(false)
        }
        target.isHorizontalScrollBarEnabled = false
        target.isVerticalScrollBarEnabled = false
        target.addJavascriptInterface(javascriptBridge, NATIVE_BRIDGE_NAME)
        target.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                !request.url.toString().startsWith(host.baseUrl)

            override fun onPageFinished(view: WebView, url: String) {
                if (webView === view && !url.startsWith(host.baseUrl)) {
                    mutableStatus.value = failedStatus("Ruffle left its trusted local origin.")
                }
            }
        }
        target.loadUrl(host.documentUrl)
    }

    override suspend fun connect() {
        if (webView == null) {
            mutableStatus.value = failedStatus("The Ruffle display is not attached.")
        }
    }

    override suspend fun execute(action: GameAction): ActionResult = when (action) {
        is GameAction.MoveToCell -> invoke("Jump", action.cell, action.pad)
        is GameAction.UseSkill -> invoke("UseSkill", action.slot.toString())
        GameAction.Stop -> {
            val attack = invoke("CancelAutoAttack")
            val target = invoke("CancelTarget")
            if (attack is ActionResult.Accepted && target is ActionResult.Accepted) {
                ActionResult.Accepted
            } else {
                ActionResult.Rejected("Ruffle could not stop the current action.")
            }
        }
    }

    suspend fun invoke(name: String, vararg arguments: Any?): ActionResult {
        if (name !in ALLOWED_CALLBACKS) {
            return ActionResult.Rejected("The requested mobile bridge action is not allowed.")
        }
        if (mutableStatus.value.connection != ConnectionState.Ready) {
            return ActionResult.Rejected("The Ruffle game bridge is not ready.")
        }
        val target = webView ?: return ActionResult.Rejected("The Ruffle display is not attached.")
        return withContext(Dispatchers.Main.immediate) {
            suspendCancellableCoroutine { continuation ->
                val envelope = JSONObject()
                    .put("name", name)
                    .put("args", JSONArray(arguments.toList()))
                    .toString()
                val script = bridgeInvocationScript(envelope)
                target.evaluateJavascript(script) { encoded ->
                    if (!continuation.isActive) return@evaluateJavascript
                    val response = runCatching {
                        val decoded = JSONArray("[$encoded]").getString(0)
                        JSONObject(decoded)
                    }.getOrNull()
                    continuation.resume(
                        if (response?.optBoolean("ok") == true) ActionResult.Accepted
                        else ActionResult.Rejected(
                            response?.optString("error")?.takeIf(String::isNotBlank)
                                ?: "The Ruffle game callback failed.",
                        ),
                    )
                }
            }
        }
    }

    suspend fun sendPacket(packet: String, toClient: Boolean): ActionResult {
        val normalized = packet.trim().take(MAXIMUM_PACKET_SEND_CHARACTERS)
        if (normalized.isEmpty()) return ActionResult.Rejected("Enter a packet first.")
        return if (toClient) {
            val type = when (normalized.first()) {
                '{' -> "json"
                '<' -> "xml"
                else -> "str"
            }
            invoke("sendClientPacket", normalized, type)
        } else {
            invoke("sendServerPacket", normalized)
        }
    }

    fun clearPackets() {
        mutablePackets.value = emptyList()
    }

    suspend fun startBot(validatedDocumentJson: String): ActionResult {
        if (validatedDocumentJson.length > MAXIMUM_BOT_DOCUMENT_CHARACTERS) {
            mutableBotStatus.value = "BOT LOAD REJECTED"
            return ActionResult.Rejected("The selected GBot exceeds the mobile execution limit.")
        }
        return invoke("MobileBotStart", validatedDocumentJson).also { result ->
            if (result is ActionResult.Rejected) mutableBotStatus.value = "BOT START FAILED"
        }
    }

    suspend fun pauseBot(): ActionResult = invoke("MobileBotPause").also { result ->
        if (result is ActionResult.Rejected) mutableBotStatus.value = "BOT PAUSE FAILED"
    }

    suspend fun stopBot(): ActionResult = invoke("MobileBotStop").also { result ->
        if (result is ActionResult.Rejected) mutableBotStatus.value = "BOT STOP FAILED"
    }

    fun optionEnabled(id: String): Boolean = optionState[id] == true

    fun toggleOption(id: String): Boolean {
        if (id !in OPTION_IDS) return false
        val enabled = !(optionState[id] == true)
        optionState[id] = enabled
        when (id) {
            "infiniteRange" -> invokeFireAndForget("SetInfiniteRange", enabled)
            "lagKiller" -> invokeFireAndForget("SetLagKiller", !enabled)
            "hidePlayers" -> invokeFireAndForget("DestroyPlayers", enabled)
            "disableAnimations" -> invokeFireAndForget("DisableAnimations", enabled)
            "fastWalk" -> invokeFireAndForget("SetWalkSpeed", if (enabled) 40 else 8)
            "autoSave" -> lastAutoSaveAt = 0
        }
        return enabled
    }

    override suspend fun disconnect() {
        withContext(Dispatchers.Main.immediate) { detach() }
    }

    fun detach() {
        webView?.apply {
            stopLoading()
            removeJavascriptInterface(NATIVE_BRIDGE_NAME)
            loadUrl("about:blank")
        }
        webView = null
        loopbackServer?.close()
        loopbackServer = null
        sessionPollInFlight.set(false)
        mutableInGame.value = false
        mutableProfile.value = RufflePlayerProfile()
        mutableBotStatus.value = "BOT IDLE"
        mutableStatus.value = offlineStatus()
    }

    override fun close() {
        detach()
        optionExecutor.shutdownNow()
    }

    private fun applyRecurringOptions() {
        if (mutableStatus.value.connection != ConnectionState.Ready) return
        if (optionEnabled("provokeCell")) invokeFireAndForget("SetProvokeMonsters")
        if (optionEnabled("provokeMap")) invokeFireAndForget("SetProvokeAllMonsters")
        if (optionEnabled("enemyMagnet")) invokeFireAndForget("SetEnemyMagnet")
        if (optionEnabled("skipCutscenes")) invokeFireAndForget("SkipActiveCutscene")
        if (optionEnabled("untargetSelf")) invokeFireAndForget("CancelTargetSelf")
        if (optionEnabled("fastWalk")) invokeFireAndForget("SetWalkSpeed", 40)
        if (optionEnabled("autoSave")) {
            val now = SystemClock.elapsedRealtime()
            if (lastAutoSaveAt == 0L || now - lastAutoSaveAt >= AUTO_SAVE_INTERVAL_MILLIS) {
                lastAutoSaveAt = now
                invokeFireAndForget("SaveState")
            }
        }
    }

    private fun pollSession() {
        val target = webView ?: return
        val connection = mutableStatus.value.connection
        if (connection == ConnectionState.Offline || connection == ConnectionState.Failed) return
        if (!sessionPollInFlight.compareAndSet(false, true)) return

        val posted = target.post {
            if (webView !== target) {
                finishSessionPoll()
                return@post
            }
            evaluateBridgeSession(target) { session ->
                session?.let(::applyBridgeSession)
                finishSessionPoll()
            }
        }
        if (!posted) finishSessionPoll()
    }

    private fun evaluateBridgeSession(
        target: WebView,
        onComplete: (MobileBridgeSession?) -> Unit,
    ) {
        if (webView !== target) {
            onComplete(null)
            return
        }
        target.evaluateJavascript(
            "typeof window.grimoireSessionSnapshot === 'function' " +
                "? window.grimoireSessionSnapshot() : null;",
        ) { encoded ->
            if (webView !== target) {
                onComplete(null)
                return@evaluateJavascript
            }
            onComplete(decodeBridgeSession(encoded))
        }
    }

    private fun decodeBridgeSession(encoded: String?): MobileBridgeSession? = runCatching {
        if (encoded.isNullOrBlank() || encoded == "null") return@runCatching null
        val responseText = JSONArray("[$encoded]").getString(0)
        val response = JSONObject(responseText)
        if (!response.optBoolean("ok") || response.isNull("inGame")) return@runCatching null

        val inGameValue = response.get("inGame").toString()
        if (!MobileSessionSignal.isBridgeTrue(inGameValue)) {
            return@runCatching MobileSessionSignal.reduceBridgeSession(inGameValue, null)
        }

        val profileJson = response.optJSONObject("profile")
        val profile = profileJson?.let {
            MobileBridgeProfile(
                name = normalizeBridgeText(jsonValueText(it, "name")),
                level = normalizeBridgeText(jsonValueText(it, "level"))
                    .toIntOrNull()
                    ?.takeIf { level -> level > 0 },
                characterClass = normalizeBridgeText(jsonValueText(it, "characterClass")),
            ).takeIf { candidate ->
                candidate.name.isNotBlank() || candidate.level != null ||
                    candidate.characterClass.isNotBlank()
            }
        }
        MobileSessionSignal.reduceBridgeSession(inGameValue, profile)
    }.getOrNull()

    private fun jsonValueText(source: JSONObject, name: String): String? =
        if (!source.has(name) || source.isNull(name)) null else source.get(name).toString()

    private fun evaluateBridgeValue(
        target: WebView,
        name: String,
        onComplete: (String?) -> Unit,
    ) {
        if (name !in SESSION_CALLBACKS || webView !== target) {
            onComplete(null)
            return
        }
        val envelope = JSONObject()
            .put("name", name)
            .put("args", JSONArray())
            .toString()
        target.evaluateJavascript(
            bridgeInvocationScript(envelope),
        ) { encoded ->
            if (webView !== target) {
                onComplete(null)
                return@evaluateJavascript
            }
            onComplete(decodeBridgeValue(encoded))
        }
    }

    private fun decodeBridgeValue(encoded: String?): String? = runCatching {
        if (encoded.isNullOrBlank() || encoded == "null") return@runCatching null
        val responseText = JSONArray("[$encoded]").getString(0)
        val response = JSONObject(responseText)
        if (!response.optBoolean("ok") || response.isNull("value")) return@runCatching null
        response.get("value").toString()
    }.getOrNull()

    private fun evaluateBridgeProfile(
        target: WebView,
        onComplete: (MobileBridgeProfile?) -> Unit,
    ) {
        evaluateBridgeValue(target, "Username") { nameValue ->
            evaluateBridgeValue(target, "Level") { levelValue ->
                evaluateBridgeValue(target, "Class") { classValue ->
                    val profile = MobileBridgeProfile(
                        name = normalizeBridgeText(nameValue),
                        level = normalizeBridgeText(levelValue)
                            .toIntOrNull()
                            ?.takeIf { it > 0 },
                        characterClass = normalizeBridgeText(classValue),
                    )
                    onComplete(profile.takeIf {
                        it.name.isNotBlank() || it.level != null ||
                            it.characterClass.isNotBlank()
                    })
                }
            }
        }
    }

    private fun normalizeBridgeText(value: String?): String {
        val trimmed = value?.trim().orEmpty()
        if (trimmed.length < 2 || trimmed.first() != '"' || trimmed.last() != '"') {
            return trimmed
        }
        return runCatching { JSONArray("[$trimmed]").getString(0).trim() }
            .getOrDefault(trimmed.trim('"'))
    }

    private fun applyBridgeSession(session: MobileBridgeSession) {
        val enteredGame = session.inGame && !mutableInGame.value
        mutableInGame.value = session.inGame
        if (session.inGame) {
            val profile = session.profile
            mutableProfile.value = if (profile == null) {
                mutableProfile.value.copy(connected = true)
            } else {
                RufflePlayerProfile(
                    connected = true,
                    name = profile.name,
                    level = profile.level,
                    characterClass = profile.characterClass,
                )
            }
            if (mutableStatus.value.connection != ConnectionState.Ready) {
                mutableStatus.value = readyStatus("Ruffle AQW session connected")
            }
            if (enteredGame) applyImmediateOptions()
        } else {
            mutableProfile.value = RufflePlayerProfile()
            if (mutableStatus.value.connection != ConnectionState.Offline &&
                mutableStatus.value.connection != ConnectionState.Failed
            ) {
                mutableStatus.value = TransportStatus(
                    connection = ConnectionState.Connecting,
                    summary = "Ruffle loaded; waiting for the AQW session",
                    bridgeVersion = BRIDGE_VERSION,
                )
            }
        }
    }

    private fun finishSessionPoll() {
        sessionPollInFlight.set(false)
    }

    private fun invokeFireAndForget(name: String, vararg arguments: Any?) {
        if (name !in ALLOWED_CALLBACKS || mutableStatus.value.connection != ConnectionState.Ready) return
        val target = webView ?: return
        val envelope = JSONObject()
            .put("name", name)
            .put("args", JSONArray(arguments.toList()))
            .toString()
        target.post {
            if (webView === target) {
                target.evaluateJavascript(
                    bridgeInvocationScript(envelope),
                    null,
                )
            }
        }
    }

    private fun bridgeInvocationScript(envelope: String): String =
        "typeof window.grimoireInvoke === 'function' " +
            "? window.grimoireInvoke(${JSONObject.quote(envelope)}) : null;"

    private inner class JavascriptBridge {
        @JavascriptInterface
        fun dispatch(method: String?, argumentsJson: String?): String {
            if (method.isNullOrBlank() || method.length > MAXIMUM_METHOD_CHARACTERS ||
                argumentsJson == null || argumentsJson.length > MAXIMUM_MESSAGE_CHARACTERS
            ) return ""

            val arguments = runCatching { JSONArray(argumentsJson) }.getOrNull() ?: return ""
            val first = if (arguments.length() > 0 && !arguments.isNull(0)) {
                arguments.optString(0)
            } else {
                ""
            }
            return try {
                when (method) {
                    "modifyServers" -> serverMap.rewrite(first)
                    "bridgeReady" -> {
                        mutableStatus.value = TransportStatus(
                            connection = ConnectionState.Connecting,
                            summary = "Ruffle loaded; waiting for the AQW session",
                            bridgeVersion = BRIDGE_VERSION,
                        )
                        ""
                    }
                    "progress" -> {
                        val progress = first.toIntOrNull()?.coerceIn(0, 100) ?: 0
                        mutableStatus.value = TransportStatus(
                            connection = ConnectionState.Connecting,
                            summary = "Loading AQW · $progress%",
                            bridgeVersion = BRIDGE_VERSION,
                        )
                        ""
                    }
                    "packet", "packetFromClient", "packetFromServer", "xtPacket" -> {
                        if (mutableStatus.value.connection != ConnectionState.Ready) {
                            mutableStatus.value = readyStatus("Ruffle AQW session connected")
                        }
                        if (method == "packetFromClient" || method == "packetFromServer") {
                            val entry = RufflePacket(
                                direction = if (method == "packetFromClient") "OUT" else "IN",
                                payload = first.take(MAXIMUM_PACKET_CAPTURE_CHARACTERS),
                            )
                            mutablePackets.value = (mutablePackets.value + entry)
                                .takeLast(MAXIMUM_PACKET_ENTRIES)
                        }
                        if (MobileSessionSignal.isInventoryLoaded(first)) {
                            applyBridgeSession(MobileBridgeSession(inGame = true, profile = null))
                            refreshProfile(0)
                            refreshProfile(PROFILE_RETRY_DELAY_MILLIS)
                        } else if (first.contains("action='logout'")) {
                            applyBridgeSession(MobileBridgeSession(inGame = false, profile = null))
                        }
                        ""
                    }
                    "mobileBotState" -> {
                        mutableBotStatus.value = first.take(MAXIMUM_BOT_STATUS_CHARACTERS)
                            .ifBlank { "BOT IDLE" }
                        ""
                    }
                    "disconnect" -> {
                        mutableInGame.value = false
                        mutableProfile.value = RufflePlayerProfile()
                        mutableBotStatus.value = "BOT STOPPED: CLIENT DISCONNECTED"
                        mutableStatus.value = TransportStatus(
                            connection = ConnectionState.Connecting,
                            summary = "AQW disconnected; waiting for login",
                            bridgeVersion = BRIDGE_VERSION,
                        )
                        ""
                    }
                    "loadError" -> {
                        mutableStatus.value = failedStatus(
                            first.ifBlank { "Ruffle could not initialize the AQW client." },
                        )
                        ""
                    }
                    else -> ""
                }
            } catch (_: Exception) {
                mutableStatus.value = failedStatus("The Ruffle bridge rejected an invalid response.")
                ""
            }
        }
    }

    private fun readyStatus(summary: String) = TransportStatus(
        connection = ConnectionState.Ready,
        summary = summary,
        bridgeVersion = BRIDGE_VERSION,
        capabilities = setOf(
            GameCapability.StateRead,
            GameCapability.SessionObserve,
            GameCapability.NavigationMove,
            GameCapability.CombatAct,
            GameCapability.InventoryRead,
            GameCapability.InventoryAct,
            GameCapability.QuestRead,
            GameCapability.QuestAct,
            GameCapability.ShopRead,
            GameCapability.ShopAct,
        ),
    )

    private fun refreshProfile(delayMillis: Long) {
        val target = webView ?: return
        target.postDelayed({
            if (webView !== target || !mutableInGame.value) return@postDelayed
            evaluateBridgeProfile(target) { profile ->
                if (profile == null) return@evaluateBridgeProfile
                if (mutableInGame.value) {
                    applyBridgeSession(MobileBridgeSession(inGame = true, profile = profile))
                }
            }
        }, delayMillis)
    }

    private fun applyImmediateOptions() {
        invokeFireAndForget("SetInfiniteRange", optionEnabled("infiniteRange"))
        invokeFireAndForget("SetLagKiller", !optionEnabled("lagKiller"))
        invokeFireAndForget("DestroyPlayers", optionEnabled("hidePlayers"))
        invokeFireAndForget("DisableAnimations", optionEnabled("disableAnimations"))
        invokeFireAndForget("SetWalkSpeed", if (optionEnabled("fastWalk")) 40 else 8)
    }

    private fun failedStatus(summary: String) = TransportStatus(
        connection = ConnectionState.Failed,
        summary = summary,
        bridgeVersion = BRIDGE_VERSION,
    )

    private fun offlineStatus() = TransportStatus(
        connection = ConnectionState.Offline,
        summary = "Ruffle engine is an experimental mobile client",
        bridgeVersion = BRIDGE_VERSION,
    )

    companion object {
        private const val NATIVE_BRIDGE_NAME = "grimoireNative"
        private const val BRIDGE_VERSION = "ruffle-android-v1"
        private const val MAXIMUM_METHOD_CHARACTERS = 96
        private const val MAXIMUM_MESSAGE_CHARACTERS = 1024 * 1024
        private const val MAXIMUM_PACKET_ENTRIES = 40
        private const val MAXIMUM_PACKET_CAPTURE_CHARACTERS = 320
        private const val MAXIMUM_PACKET_SEND_CHARACTERS = 8192
        private const val MAXIMUM_BOT_DOCUMENT_CHARACTERS = 2 * 1024 * 1024
        private const val MAXIMUM_BOT_STATUS_CHARACTERS = 160
        private const val AUTO_SAVE_INTERVAL_MILLIS = 300_000L
        private const val PROFILE_RETRY_DELAY_MILLIS = 1_000L
        private const val SESSION_POLL_INITIAL_DELAY_MILLIS = 750L
        private const val SESSION_POLL_INTERVAL_MILLIS = 1_000L
        private val SESSION_CALLBACKS = setOf("InGame", "Username", "Level", "Class")
        private val OPTION_IDS = setOf(
            "infiniteRange", "provokeCell", "provokeMap", "enemyMagnet",
            "lagKiller", "hidePlayers", "skipCutscenes", "disableAnimations",
            "untargetSelf", "autoSave", "fastWalk",
        )
        private val ALLOWED_CALLBACKS = setOf(
            "Jump", "UseSkill", "CancelAutoAttack", "CancelTarget",
            "Rest", "SetSpawnPoint", "cancelAfk", "ShowBank",
            "SetInfiniteRange", "SetProvokeMonsters", "SetProvokeAllMonsters",
            "SetEnemyMagnet", "SetLagKiller", "DestroyPlayers",
            "SetSkipCutscenes", "DisableAnimations", "CancelTargetSelf",
            "SkipActiveCutscene",
            "SetWalkSpeed", "DisableDeathAd", "EnableChat", "SaveState",
            "sendClientPacket", "sendServerPacket", "SetFPS",
            "MobileBotStart", "MobileBotStop", "MobileBotPause", "MobileBotStatus",
        )
    }
}

data class RufflePacket(
    val direction: String,
    val payload: String,
)

data class RufflePlayerProfile(
    val connected: Boolean = false,
    val name: String = "",
    val level: Int? = null,
    val characterClass: String = "",
)
