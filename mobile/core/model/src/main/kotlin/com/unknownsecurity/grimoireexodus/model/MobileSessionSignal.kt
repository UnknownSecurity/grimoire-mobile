package com.unknownsecurity.grimoireexodus.model

data class MobileBridgeProfile(
    val name: String = "",
    val level: Int? = null,
    val characterClass: String = "",
)

data class MobileBridgeSession(
    val inGame: Boolean,
    val profile: MobileBridgeProfile?,
)

object MobileSessionSignal {
    fun isInventoryLoaded(payload: String): Boolean {
        if (!payload.contains("loadInventoryBig")) return false

        val normalized = payload
            .replace("&quot;", "\"", ignoreCase = true)
            .filterNot(Char::isWhitespace)
        return normalized.contains("\"cmd\":\"loadInventoryBig\"")
    }

    fun bridgeBoolean(value: String?): Boolean? = when (
        value?.trim()?.trim('"')?.lowercase()
    ) {
        "true" -> true
        "false" -> false
        else -> null
    }

    fun isBridgeTrue(value: String?): Boolean = bridgeBoolean(value) == true

    fun reduceBridgeSession(
        inGameValue: String?,
        profile: MobileBridgeProfile?,
    ): MobileBridgeSession? = when (bridgeBoolean(inGameValue)) {
        true -> MobileBridgeSession(inGame = true, profile = profile)
        false -> MobileBridgeSession(inGame = false, profile = null)
        null -> null
    }
}
