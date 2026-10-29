package com.unknownsecurity.grimoireexodus.mobile.ruffle

import org.json.JSONObject
import java.net.Inet6Address
import java.net.InetAddress

internal data class RuffleServerEndpoint(
    val host: String,
    val port: Int,
)

/**
 * Rewrites AQW's public TCP endpoints to the synthetic ports Ruffle exposes
 * through its WebSocket socket-proxy API. Real destinations remain private to
 * the owning mobile client and are accepted only from official public hosts.
 */
internal class RuffleServerMap {
    private val lock = Any()
    private val endpoints = mutableMapOf<Int, RuffleServerEndpoint>()

    fun rewrite(response: String): String {
        if (response.isBlank() || !response.trimStart().startsWith("{")) return response

        val packet = JSONObject(response)
        val servers = packet.optJSONArray("servers") ?: return response
        require(servers.length() <= MAXIMUM_SLOTS) {
            "The AQW server list exceeded the Ruffle safety limit."
        }

        val next = mutableMapOf<Int, RuffleServerEndpoint>()
        for (index in 0 until servers.length()) {
            val server = servers.getJSONObject(index)
            val host = server.optString("sIP").trim().trimEnd('.')
            val port = server.optInt("iPort")
            validateEndpoint(host, port)
            next[index] = RuffleServerEndpoint(host, port)
            server.put("RealAddress", host)
            server.put("RealPort", port)
            server.put("sIP", "127.0.0.1")
            server.put("iPort", FIRST_SYNTHETIC_PORT + index)
        }

        synchronized(lock) {
            endpoints.clear()
            endpoints.putAll(next)
        }
        return packet.toString()
    }

    fun endpoint(slot: Int): RuffleServerEndpoint? = synchronized(lock) {
        endpoints[slot]
    }

    private fun validateEndpoint(host: String, port: Int) {
        require(host.isNotBlank() && host.length <= 255) {
            "AQW returned an invalid game-server address."
        }
        require(port in 1..65535) {
            "AQW returned an invalid game-server port."
        }

        parseIpv4(host)?.let { bytes ->
            require(isPublicIpv4(bytes)) {
                "AQW returned a non-public game-server address."
            }
            return
        }
        if (host.contains(':')) {
            val address = runCatching { InetAddress.getByName(host) }.getOrNull()
            require(address is Inet6Address && isPublicIpv6(address)) {
                "AQW returned a non-public game-server address."
            }
            return
        }

        val normalized = host.lowercase()
        require(ALLOWED_SUFFIXES.any { suffix ->
            normalized == suffix || normalized.endsWith(".$suffix")
        }) {
            "AQW returned an untrusted game-server host."
        }
    }

    private fun parseIpv4(value: String): IntArray? {
        val parts = value.split('.')
        if (parts.size != 4) return null
        val bytes = IntArray(4)
        parts.forEachIndexed { index, part ->
            if (part.isEmpty() || part.length > 3 || part.any { !it.isDigit() }) return null
            val parsed = part.toIntOrNull() ?: return null
            if (parsed !in 0..255) return null
            bytes[index] = parsed
        }
        return bytes
    }

    private fun isPublicIpv4(bytes: IntArray): Boolean {
        val first = bytes[0]
        val second = bytes[1]
        return first != 0 && first != 10 && first != 127 && first < 224 &&
            !(first == 100 && second in 64..127) &&
            !(first == 169 && second == 254) &&
            !(first == 172 && second in 16..31) &&
            !(first == 192 && second == 168)
    }

    private fun isPublicIpv6(address: Inet6Address): Boolean {
        val bytes = address.address
        return !address.isAnyLocalAddress && !address.isLoopbackAddress &&
            !address.isLinkLocalAddress && !address.isSiteLocalAddress &&
            !address.isMulticastAddress && (bytes[0].toInt() and 0xFE) != 0xFC &&
            (bytes[0].toInt() and 0xE0) == 0x20
    }

    companion object {
        const val FIRST_SYNTHETIC_PORT = 41000
        const val MAXIMUM_SLOTS = 64
        private val ALLOWED_SUFFIXES = setOf("aq.com", "battleon.com", "artix.com")
    }
}
