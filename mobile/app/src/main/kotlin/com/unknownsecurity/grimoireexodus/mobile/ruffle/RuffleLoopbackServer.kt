package com.unknownsecurity.grimoireexodus.mobile.ruffle

import android.content.Context
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.EOFException
import java.io.InputStream
import java.io.OutputStream
import java.net.CookieManager
import java.net.CookiePolicy
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URI
import java.net.URL
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Loopback-only origin used by Android WebView. It serves the pinned Ruffle
 * runtime and bridge SWF, proxies only the official AQW game path, and tunnels
 * only server endpoints obtained from AQW's validated server list.
 */
internal class RuffleLoopbackServer(
    context: Context,
    private val serverMap: RuffleServerMap,
) : Closeable {
    private val assets = context.applicationContext.assets
    private val running = AtomicBoolean(true)
    private val executor = Executors.newCachedThreadPool()
    private val connectionLimit = Semaphore(MAXIMUM_CONNECTIONS)
    private val clients = ConcurrentHashMap.newKeySet<Socket>()
    private val cookies = CookieManager(null, CookiePolicy.ACCEPT_ORIGINAL_SERVER)
    private val server = ServerSocket(0, 32, InetAddress.getByName("127.0.0.1"))
    private val token = createToken()
    private val indexBytes = assets.open("ruffle-host/index.html").use { stream ->
        stream.readBytesLimited(MAXIMUM_STATIC_BYTES)
            .toString(StandardCharsets.UTF_8)
            .replace("__BASE_URL__", baseUrl)
            .toByteArray(StandardCharsets.UTF_8)
    }

    val port: Int
        get() = server.localPort

    val baseUrl: String
        get() = "http://127.0.0.1:${server.localPort}/$token/"

    val documentUrl: String
        get() = baseUrl + "index.html"

    init {
        executor.execute(::acceptLoop)
    }

    private fun acceptLoop() {
        while (running.get()) {
            val client = try {
                server.accept()
            } catch (_: Exception) {
                if (!running.get()) return
                continue
            }
            if (!connectionLimit.tryAcquire()) {
                client.closeQuietly()
                continue
            }
            clients += client
            executor.execute {
                try {
                    handleClient(client)
                } catch (_: Exception) {
                    // Fail closed. No packet or account data is written to logs.
                } finally {
                    clients -= client
                    client.closeQuietly()
                    connectionLimit.release()
                }
            }
        }
    }

    private fun handleClient(client: Socket) {
        client.tcpNoDelay = true
        client.soTimeout = READ_TIMEOUT_MILLIS
        val request = readRequest(client.getInputStream()) ?: return
        val routePrefix = "/$token/"
        if (!request.pathAndQuery.startsWith(routePrefix)) {
            writeResponse(client.getOutputStream(), 404, "Not Found", "text/plain", byteArrayOf())
            return
        }

        val route = request.pathAndQuery.removePrefix(routePrefix)
        val routePath = route.substringBefore('?')
        if (routePath == "socket" || routePath.startsWith("socket/")) {
            handleWebSocket(client, request, routePath)
            return
        }
        if (request.method != "GET" && request.method != "POST") {
            writeResponse(client.getOutputStream(), 405, "Method Not Allowed", "text/plain", byteArrayOf())
            return
        }

        when {
            routePath.isEmpty() || routePath.equals("index.html", true) ->
                writeResponse(client.getOutputStream(), 200, "OK", "text/html; charset=utf-8", indexBytes)
            routePath.equals("client.swf", true) -> serveAsset(
                client.getOutputStream(),
                "client.swf",
                "application/x-shockwave-flash",
            )
            routePath.startsWith("ruffle/", true) -> serveRuffle(
                client.getOutputStream(),
                routePath.substringAfter("ruffle/"),
            )
            route.startsWith("game/", true) -> proxyOfficialGame(
                client.getOutputStream(),
                request,
                route.substringAfter("game/"),
            )
            else -> writeResponse(client.getOutputStream(), 404, "Not Found", "text/plain", byteArrayOf())
        }
    }

    private fun serveRuffle(output: OutputStream, name: String) {
        if (!SAFE_ASSET_NAME.matches(name) || name.contains("..")) {
            writeResponse(output, 404, "Not Found", "text/plain", byteArrayOf())
            return
        }
        val contentType = when {
            name.endsWith(".wasm", true) -> "application/wasm"
            name.endsWith(".js", true) -> "application/javascript; charset=utf-8"
            else -> "text/plain; charset=utf-8"
        }
        serveAsset(output, "ruffle/$name", contentType)
    }

    private fun serveAsset(output: OutputStream, path: String, contentType: String) {
        val payload = runCatching {
            assets.open(path).use {
                it.readBytesLimited(MAXIMUM_STATIC_BYTES)
            }
        }.getOrNull()
        if (payload == null) {
            writeResponse(output, 404, "Not Found", "text/plain", byteArrayOf())
            return
        }
        writeResponse(output, 200, "OK", contentType, payload)
    }

    private fun proxyOfficialGame(output: OutputStream, request: HttpRequest, relative: String) {
        if (relative.contains("..") || relative.contains('\\')) {
            writeResponse(output, 400, "Bad Request", "text/plain", byteArrayOf())
            return
        }
        val upstream = OFFICIAL_GAME_BASE.resolve(relative)
        if (upstream.scheme != "https" || upstream.host != OFFICIAL_GAME_BASE.host ||
            !upstream.path.startsWith(OFFICIAL_GAME_BASE.path)
        ) {
            writeResponse(output, 403, "Forbidden", "text/plain", byteArrayOf())
            return
        }

        val connection = (URL(upstream.toString()).openConnection() as HttpURLConnection).apply {
            requestMethod = request.method
            instanceFollowRedirects = false
            connectTimeout = UPSTREAM_TIMEOUT_MILLIS
            readTimeout = UPSTREAM_TIMEOUT_MILLIS
            setRequestProperty("User-Agent", "Grimoire-Exodus-Mobile-Ruffle/1.0")
            request.headers["range"]?.let { setRequestProperty("Range", it) }
            request.headers["content-type"]?.let { setRequestProperty("Content-Type", it) }
            cookies.get(upstream, emptyMap()).forEach { (name, values) ->
                values.forEach { value -> addRequestProperty(name, value) }
            }
            if (request.body.isNotEmpty()) {
                doOutput = true
                setFixedLengthStreamingMode(request.body.size)
                outputStream.use { it.write(request.body) }
            }
        }

        try {
            val status = connection.responseCode
            val responseHeaders = connection.headerFields
                .filterKeys { it != null }
                .mapKeys { it.key }
            cookies.put(upstream, responseHeaders)
            val bodyStream = if (status >= 400) connection.errorStream else connection.inputStream
            val body = bodyStream?.use { it.readBytesLimited(MAXIMUM_UPSTREAM_BYTES) } ?: byteArrayOf()
            val headers = mutableMapOf<String, String>()
            connection.getHeaderField("Location")?.let { location ->
                val redirect = upstream.resolve(location)
                if (redirect.host == OFFICIAL_GAME_BASE.host &&
                    redirect.path.startsWith(OFFICIAL_GAME_BASE.path)
                ) {
                    headers["Location"] = baseUrl + "game/" +
                        redirect.toString().substringAfter(OFFICIAL_GAME_BASE.toString())
                }
            }
            listOf("Accept-Ranges", "Content-Range", "ETag", "Last-Modified").forEach { name ->
                connection.getHeaderField(name)?.takeIf { '\r' !in it && '\n' !in it }?.let {
                    headers[name] = it
                }
            }
            writeResponse(
                output = output,
                status = status,
                reason = connection.responseMessage ?: "",
                contentType = connection.contentType ?: "application/octet-stream",
                body = body,
                extraHeaders = headers,
            )
        } catch (_: Exception) {
            writeResponse(output, 502, "Bad Gateway", "text/plain", byteArrayOf())
        } finally {
            connection.disconnect()
        }
    }

    private fun handleWebSocket(client: Socket, request: HttpRequest, routePath: String) {
        val output = client.getOutputStream()
        client.soTimeout = 0
        val slot = routePath.substringAfter("socket/", "").toIntOrNull()
        val endpoint = slot?.let(serverMap::endpoint)
        val key = request.headers["sec-websocket-key"]
        val valid = endpoint != null && request.method == "GET" &&
            request.headers["upgrade"].equals("websocket", true) &&
            request.headers["connection"].orEmpty().split(',').any { it.trim().equals("upgrade", true) } &&
            request.headers["sec-websocket-version"] == "13" &&
            request.headers["origin"].equals("http://127.0.0.1:$port", true) &&
            key != null && runCatching { Base64.getDecoder().decode(key.trim()).size == 16 }.getOrDefault(false)
        if (!valid) {
            writeResponse(output, 404, "Not Found", "text/plain", byteArrayOf())
            return
        }
        val validatedEndpoint = checkNotNull(endpoint)
        val validatedKey = checkNotNull(key)

        val game = Socket()
        try {
            game.connect(
                java.net.InetSocketAddress(validatedEndpoint.host, validatedEndpoint.port),
                CONNECT_TIMEOUT_MILLIS,
            )
            game.tcpNoDelay = true
            val accept = Base64.getEncoder().encodeToString(
                MessageDigest.getInstance("SHA-1").digest(
                    (validatedKey.trim() + WEBSOCKET_GUID).toByteArray(StandardCharsets.US_ASCII),
                ),
            )
            output.write(
                ("HTTP/1.1 101 Switching Protocols\r\n" +
                    "Upgrade: websocket\r\nConnection: Upgrade\r\n" +
                    "Sec-WebSocket-Accept: $accept\r\n\r\n")
                    .toByteArray(StandardCharsets.US_ASCII),
            )
            output.flush()

            val writeLock = Any()
            val inbound = executor.submit {
                relayWebSocketToTcp(client.getInputStream(), game.getOutputStream(), output, writeLock)
            }
            val outbound = executor.submit {
                relayTcpToWebSocket(game.getInputStream(), output, writeLock)
            }
            while (running.get() && !inbound.isDone && !outbound.isDone) {
                Thread.sleep(20)
            }
            game.closeQuietly()
            client.closeQuietly()
            inbound.cancel(true)
            outbound.cancel(true)
        } finally {
            game.closeQuietly()
        }
    }

    private fun relayWebSocketToTcp(
        browser: InputStream,
        game: OutputStream,
        browserOutput: OutputStream,
        writeLock: Any,
    ) {
        val fragmented = ByteArrayOutputStream()
        var fragmentActive = false
        while (running.get() && !Thread.currentThread().isInterrupted) {
            val frame = readWebSocketFrame(browser)
            when (frame.opcode) {
                8 -> return
                9 -> {
                    writeWebSocketFrame(browserOutput, writeLock, 10, frame.payload)
                    continue
                }
                10 -> continue
                1 -> return
                2 -> {
                    if (fragmentActive) return
                    fragmented.reset()
                    fragmentActive = !frame.final
                    fragmented.write(frame.payload)
                }
                0 -> {
                    if (!fragmentActive || fragmented.size() + frame.payload.size > MAXIMUM_WEBSOCKET_BYTES) return
                    fragmented.write(frame.payload)
                    fragmentActive = !frame.final
                }
                else -> return
            }
            if (!fragmentActive) {
                game.write(fragmented.toByteArray())
                game.flush()
                fragmented.reset()
            }
        }
    }

    private fun relayTcpToWebSocket(game: InputStream, browser: OutputStream, writeLock: Any) {
        val buffer = ByteArray(16 * 1024)
        while (running.get() && !Thread.currentThread().isInterrupted) {
            val count = game.read(buffer)
            if (count < 0) return
            writeWebSocketFrame(browser, writeLock, 2, buffer.copyOf(count))
        }
    }

    private fun readWebSocketFrame(input: InputStream): WebSocketFrame {
        val first = input.read()
        val second = input.read()
        if (first < 0 || second < 0) throw EOFException()
        val final = first and 0x80 != 0
        require(first and 0x70 == 0) { "Reserved WebSocket bits are not supported." }
        val opcode = first and 0x0F
        require(opcode in setOf(0, 1, 2, 8, 9, 10)) { "Invalid WebSocket opcode." }
        require(second and 0x80 != 0) { "WebSocket client frames must be masked." }
        var length = (second and 0x7F).toLong()
        if (length == 126L) {
            val extended = input.readExactly(2)
            length = ((extended[0].toInt() and 0xFF) shl 8 or (extended[1].toInt() and 0xFF)).toLong()
        } else if (length == 127L) {
            length = 0
            input.readExactly(8).forEach { byte -> length = (length shl 8) or (byte.toLong() and 0xFF) }
        }
        require(length in 0..MAXIMUM_WEBSOCKET_BYTES.toLong()) { "WebSocket frame exceeded the safety limit." }
        require(opcode < 8 || final && length <= 125) { "Invalid WebSocket control frame." }
        val mask = input.readExactly(4)
        val payload = input.readExactly(length.toInt())
        payload.indices.forEach { index ->
            payload[index] = (payload[index].toInt() xor mask[index % 4].toInt()).toByte()
        }
        return WebSocketFrame(final, opcode, payload)
    }

    private fun writeWebSocketFrame(output: OutputStream, lock: Any, opcode: Int, payload: ByteArray) {
        synchronized(lock) {
            val frame = ByteArrayOutputStream(payload.size + 10)
            frame.write(0x80 or opcode)
            when {
                payload.size < 126 -> frame.write(payload.size)
                payload.size <= 65535 -> {
                    frame.write(126)
                    frame.write(payload.size shr 8)
                    frame.write(payload.size)
                }
                else -> {
                    frame.write(127)
                    for (shift in 56 downTo 0 step 8) frame.write(payload.size.toLong().shr(shift).toInt())
                }
            }
            frame.write(payload)
            output.write(frame.toByteArray())
            output.flush()
        }
    }

    private fun readRequest(input: InputStream): HttpRequest? {
        val buffer = ByteArrayOutputStream()
        val chunk = ByteArray(4096)
        var headerEnd = -1
        while (headerEnd < 0) {
            val count = input.read(chunk)
            if (count < 0) return null
            buffer.write(chunk, 0, count)
            require(buffer.size() <= MAXIMUM_HEADER_BYTES) {
                "HTTP header exceeded the safety limit."
            }
            headerEnd = findHeaderEnd(buffer.toByteArray())
        }

        val bytes = buffer.toByteArray()
        val lines = bytes.copyOfRange(0, headerEnd - 4)
            .toString(StandardCharsets.US_ASCII).split("\r\n")
        val requestLine = lines.first().split(' ')
        require(requestLine.size == 3 && requestLine[1].length <= 8192) { "Invalid HTTP request." }
        val headers = mutableMapOf<String, String>()
        lines.drop(1).forEach { line ->
            val separator = line.indexOf(':')
            require(separator > 0) { "Invalid HTTP header." }
            headers[line.substring(0, separator).trim().lowercase(Locale.US)] =
                line.substring(separator + 1).trim()
        }
        val contentLength = headers["content-length"]?.toIntOrNull() ?: 0
        require(contentLength in 0..MAXIMUM_REQUEST_BODY_BYTES) { "HTTP body exceeded the safety limit." }
        val body = ByteArray(contentLength)
        val bufferedBody = minOf(contentLength, bytes.size - headerEnd)
        if (bufferedBody > 0) bytes.copyInto(body, 0, headerEnd, headerEnd + bufferedBody)
        if (bufferedBody < contentLength) {
            input.readFully(body, bufferedBody, contentLength - bufferedBody)
        }
        return HttpRequest(requestLine[0].uppercase(Locale.US), requestLine[1], headers, body)
    }

    private fun writeResponse(
        output: OutputStream,
        status: Int,
        reason: String,
        contentType: String,
        body: ByteArray,
        extraHeaders: Map<String, String> = emptyMap(),
    ) {
        val header = buildString {
            append("HTTP/1.1 $status $reason\r\n")
            append("Connection: close\r\n")
            append("Cache-Control: no-store\r\n")
            append("X-Content-Type-Options: nosniff\r\n")
            append("Content-Type: $contentType\r\n")
            append("Content-Length: ${body.size}\r\n")
            extraHeaders.forEach { (name, value) -> append("$name: $value\r\n") }
            append("\r\n")
        }
        output.write(header.toByteArray(StandardCharsets.US_ASCII))
        if (body.isNotEmpty()) output.write(body)
        output.flush()
    }

    override fun close() {
        if (!running.compareAndSet(true, false)) return
        server.close()
        clients.forEach { it.closeQuietly() }
        clients.clear()
        executor.shutdownNow()
        executor.awaitTermination(2, TimeUnit.SECONDS)
    }

    private fun InputStream.readBytesLimited(maximum: Int): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(32 * 1024)
        while (true) {
            val count = read(buffer)
            if (count < 0) return output.toByteArray()
            require(output.size() + count <= maximum) { "Payload exceeded the safety limit." }
            output.write(buffer, 0, count)
        }
    }

    private fun InputStream.readExactly(count: Int): ByteArray = ByteArray(count).also {
        readFully(it, 0, count)
    }

    private fun InputStream.readFully(buffer: ByteArray, initialOffset: Int, initialCount: Int) {
        var offset = initialOffset
        var remaining = initialCount
        while (remaining > 0) {
            val count = read(buffer, offset, remaining)
            if (count < 0) throw EOFException()
            offset += count
            remaining -= count
        }
    }

    private fun findHeaderEnd(bytes: ByteArray): Int {
        for (index in 0..(bytes.size - 4)) {
            if (bytes[index] == 13.toByte() && bytes[index + 1] == 10.toByte() &&
                bytes[index + 2] == 13.toByte() && bytes[index + 3] == 10.toByte()
            ) return index + 4
        }
        return -1
    }

    private fun Socket.closeQuietly() {
        runCatching { close() }
    }

    private data class HttpRequest(
        val method: String,
        val pathAndQuery: String,
        val headers: Map<String, String>,
        val body: ByteArray,
    )

    private data class WebSocketFrame(
        val final: Boolean,
        val opcode: Int,
        val payload: ByteArray,
    )

    companion object {
        private val OFFICIAL_GAME_BASE = URI("https://game.aq.com/game/")
        private val SAFE_ASSET_NAME = Regex("[A-Za-z0-9._-]+")
        private const val WEBSOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        private const val MAXIMUM_CONNECTIONS = 24
        private const val MAXIMUM_HEADER_BYTES = 32 * 1024
        private const val MAXIMUM_REQUEST_BODY_BYTES = 8 * 1024 * 1024
        private const val MAXIMUM_STATIC_BYTES = 64 * 1024 * 1024
        private const val MAXIMUM_UPSTREAM_BYTES = 64 * 1024 * 1024
        private const val MAXIMUM_WEBSOCKET_BYTES = 4 * 1024 * 1024
        private const val READ_TIMEOUT_MILLIS = 30_000
        private const val UPSTREAM_TIMEOUT_MILLIS = 30_000
        private const val CONNECT_TIMEOUT_MILLIS = 10_000

        private fun createToken(): String {
            val bytes = ByteArray(24).also(SecureRandom()::nextBytes)
            return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
        }
    }
}
