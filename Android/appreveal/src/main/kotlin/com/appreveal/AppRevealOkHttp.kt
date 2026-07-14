package com.appreveal

import com.appreveal.network.CapturedRequest
import com.appreveal.network.CapturedSSEEvent
import com.appreveal.network.NetworkCaptureConfig
import com.appreveal.network.NetworkObserverService
import okhttp3.Headers
import okhttp3.Interceptor
import okhttp3.MediaType
import okhttp3.OkHttpClient
import okhttp3.RequestBody
import okhttp3.Response
import okhttp3.ResponseBody
import okio.Buffer
import okio.BufferedSource
import okio.Source
import okio.Timeout
import okio.buffer
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.nio.charset.Charset
import java.util.UUID

/**
 * Optional OkHttp integration for automatic AppReveal network capture.
 *
 * Install on the app's debug OkHttpClient builder:
 * `AppRevealOkHttp.install(builder)`.
 */
object AppRevealOkHttp {
    @JvmStatic
    @JvmOverloads
    fun install(
        builder: OkHttpClient.Builder,
        config: NetworkCaptureConfig = NetworkCaptureConfig(),
    ): OkHttpClient.Builder = builder.addInterceptor(interceptor(config))

    @JvmStatic
    @JvmOverloads
    fun interceptor(config: NetworkCaptureConfig = NetworkCaptureConfig()): Interceptor = NetworkCaptureInterceptor(config)
}

private class NetworkCaptureInterceptor(
    private val config: NetworkCaptureConfig,
) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val id = UUID.randomUUID().toString()
        val startTime = System.currentTimeMillis()
        val requestSnapshot = request.body.capture(config)

        NetworkObserverService.addCall(
            CapturedRequest(
                id = id,
                method = request.method,
                url = request.url.toString(),
                startTime = startTime,
                requestHeaders = request.headers.toMap(),
                requestBodySize = requestSnapshot.size,
                requestBody = requestSnapshot.body,
                requestBodyTruncated = requestSnapshot.truncated,
            ).withRedactedHeaders(config.redactedHeaders),
        )

        return try {
            val response = chain.proceed(request)
            captureResponse(id, startTime, response)
        } catch (error: IOException) {
            NetworkObserverService.updateCall(id) { existing ->
                existing.copy(
                    endTime = System.currentTimeMillis(),
                    duration = elapsedSeconds(startTime),
                    error = error.message ?: error.javaClass.simpleName,
                )
            }
            throw error
        }
    }

    private fun captureResponse(
        id: String,
        startTime: Long,
        response: Response,
    ): Response {
        val responseBody = response.body
        val mediaType = responseBody?.contentType()
        val streaming = response.isStreaming(mediaType)

        NetworkObserverService.updateCall(id) { existing ->
            existing.copy(
                statusCode = response.code,
                responseHeaders = response.headers.toMap(),
                responseBodySize = responseBody?.contentLength()?.takeIf { it >= 0 }?.coerceToInt(),
                isStreaming = streaming,
                redirectCount = response.priorResponseCount(),
                endTime = if (responseBody == null) System.currentTimeMillis() else existing.endTime,
                duration = if (responseBody == null) elapsedSeconds(startTime) else existing.duration,
            )
        }

        if (responseBody == null) {
            return response
        }

        val wrappedBody =
            CapturingResponseBody(
                id = id,
                startTime = startTime,
                delegate = responseBody,
                config = config,
                captureText = config.captureBodies && mediaType.isTextLike(),
                parseSSE = streaming,
            )
        return response.newBuilder().body(wrappedBody).build()
    }
}

private class CapturingResponseBody(
    private val id: String,
    private val startTime: Long,
    private val delegate: ResponseBody,
    private val config: NetworkCaptureConfig,
    private val captureText: Boolean,
    parseSSE: Boolean,
) : ResponseBody() {
    private val accumulator = BodyAccumulator(config.maxBodyBytes, captureText, delegate.contentType())
    private val sseParser = if (parseSSE) SSEEventAccumulator(config.maxSSEEvents) else null
    private var bufferedSource: BufferedSource? = null

    override fun contentLength(): Long = delegate.contentLength()

    override fun contentType(): MediaType? = delegate.contentType()

    override fun source(): BufferedSource {
        if (bufferedSource == null) {
            bufferedSource =
                CapturingSource(
                    delegate = delegate.source(),
                    onBytes = ::captureBytes,
                    onComplete = ::complete,
                ).buffer()
        }
        return bufferedSource!!
    }

    private fun captureBytes(bytes: ByteArray) {
        accumulator.append(bytes)
        val sseEvents = sseParser?.append(bytes, delegate.contentType())

        NetworkObserverService.updateCall(id) { existing ->
            existing.copy(
                responseBodySize = accumulator.totalBytes.coerceToInt(),
                responseBody = accumulator.body,
                responseBodyTruncated = accumulator.truncated,
                sseEvents = sseEvents ?: existing.sseEvents,
            )
        }
    }

    private fun complete(error: IOException?) {
        val finalEvents = sseParser?.finish()
        NetworkObserverService.updateCall(id) { existing ->
            existing.copy(
                endTime = System.currentTimeMillis(),
                duration = elapsedSeconds(startTime),
                responseBodySize = accumulator.totalBytes.coerceToInt(),
                responseBody = accumulator.body,
                responseBodyTruncated = accumulator.truncated,
                sseEvents = finalEvents ?: existing.sseEvents,
                error = error?.message ?: existing.error,
            )
        }
    }
}

private class CapturingSource(
    private val delegate: Source,
    private val onBytes: (ByteArray) -> Unit,
    private val onComplete: (IOException?) -> Unit,
) : Source {
    private var completed = false

    override fun read(
        sink: Buffer,
        byteCount: Long,
    ): Long {
        val buffer = Buffer()
        return try {
            val read = delegate.read(buffer, byteCount)
            if (read > 0) {
                val bytes = buffer.clone().readByteArray()
                sink.write(buffer, read)
                onBytes(bytes)
            } else if (read == -1L) {
                complete(null)
            }
            read
        } catch (error: IOException) {
            complete(error)
            throw error
        }
    }

    override fun timeout(): Timeout = delegate.timeout()

    override fun close() {
        try {
            delegate.close()
        } finally {
            complete(null)
        }
    }

    private fun complete(error: IOException?) {
        if (!completed) {
            completed = true
            onComplete(error)
        }
    }
}

private data class BodySnapshot(
    val size: Int?,
    val body: String?,
    val truncated: Boolean,
)

private fun RequestBody?.capture(config: NetworkCaptureConfig): BodySnapshot {
    if (this == null) return BodySnapshot(size = null, body = null, truncated = false)

    val knownSize = runCatching { contentLength().takeIf { it >= 0 }?.coerceToInt() }.getOrNull()
    if (!config.captureBodies || isDuplex() || isOneShot() || !contentType().isTextLike()) {
        return BodySnapshot(size = knownSize, body = null, truncated = false)
    }

    return runCatching {
        val buffer = Buffer()
        writeTo(buffer)
        val totalSize = buffer.size
        val snapshotSize = minOf(totalSize, config.maxBodyBytes.coerceAtLeast(0))
        val bytes = buffer.readByteArray(snapshotSize)
        BodySnapshot(
            size = totalSize.coerceToInt(),
            body = String(bytes, contentType().charsetOrUtf8()),
            truncated = totalSize > snapshotSize,
        )
    }.getOrElse {
        BodySnapshot(size = knownSize, body = null, truncated = false)
    }
}

private class BodyAccumulator(
    private val maxBodyBytes: Long,
    private val captureText: Boolean,
    private val mediaType: MediaType?,
) {
    private val output = ByteArrayOutputStream()
    var totalBytes: Long = 0
        private set
    var truncated: Boolean = false
        private set

    val body: String?
        get() {
            if (!captureText) return null
            return String(output.toByteArray(), mediaType.charsetOrUtf8())
        }

    fun append(bytes: ByteArray) {
        totalBytes += bytes.size
        if (!captureText) return

        val remaining = maxBodyBytes.coerceAtLeast(0) - output.size()
        if (remaining <= 0) {
            truncated = truncated || bytes.isNotEmpty()
            return
        }

        val toWrite = minOf(bytes.size.toLong(), remaining).toInt()
        output.write(bytes, 0, toWrite)
        if (toWrite < bytes.size) truncated = true
    }
}

private class SSEEventAccumulator(
    private val maxEvents: Int,
) {
    private val events = mutableListOf<CapturedSSEEvent>()
    private var lineBuffer = StringBuilder()
    private var dataLines = mutableListOf<String>()
    private var eventName: String? = null
    private var eventId: String? = null
    private var retry: Long? = null

    fun append(
        bytes: ByteArray,
        mediaType: MediaType?,
    ): List<CapturedSSEEvent> {
        lineBuffer.append(String(bytes, mediaType.charsetOrUtf8()))
        drainLines()
        return events.toList()
    }

    fun finish(): List<CapturedSSEEvent> {
        if (lineBuffer.isNotEmpty()) {
            handleLine(lineBuffer.toString())
            lineBuffer = StringBuilder()
        }
        emitIfNeeded()
        return events.toList()
    }

    private fun drainLines() {
        while (true) {
            val lineEnd = lineBuffer.indexOfFirstNewline()
            if (lineEnd == -1) return

            var line = lineBuffer.substring(0, lineEnd)
            val newlineLength =
                if (lineBuffer.getOrNull(lineEnd) == '\r' && lineBuffer.getOrNull(lineEnd + 1) == '\n') {
                    2
                } else {
                    1
                }
            lineBuffer.delete(0, lineEnd + newlineLength)
            if (line.endsWith('\r')) line = line.dropLast(1)
            handleLine(line)
        }
    }

    private fun handleLine(line: String) {
        if (line.isEmpty()) {
            emitIfNeeded()
            return
        }
        if (line.startsWith(":")) return

        val separator = line.indexOf(':')
        val field = if (separator == -1) line else line.substring(0, separator)
        val rawValue = if (separator == -1) "" else line.substring(separator + 1)
        val value = if (rawValue.startsWith(" ")) rawValue.drop(1) else rawValue

        when (field) {
            "data" -> dataLines.add(value)
            "event" -> eventName = value
            "id" -> eventId = value
            "retry" -> retry = value.toLongOrNull()
        }
    }

    private fun emitIfNeeded() {
        if (dataLines.isEmpty() && eventName == null && eventId == null && retry == null) return

        events.add(
            CapturedSSEEvent(
                id = eventId,
                event = eventName ?: "message",
                data = dataLines.joinToString("\n"),
                retry = retry,
            ),
        )
        while (events.size > maxEvents.coerceAtLeast(0)) {
            events.removeAt(0)
        }

        dataLines = mutableListOf()
        eventName = null
        eventId = null
        retry = null
    }
}

private fun Headers.toMap(): Map<String, String> = names().associateWith { name -> values(name).joinToString(", ") }

private fun Response.isStreaming(mediaType: MediaType?): Boolean {
    val contentType = mediaType?.toString()?.lowercase().orEmpty()
    val cacheControl = header("Cache-Control").orEmpty().lowercase()
    return contentType.contains("text/event-stream") ||
        header("X-Accel-Buffering").equals("no", ignoreCase = true) ||
        cacheControl.contains("no-transform")
}

private fun Response.priorResponseCount(): Int {
    var count = 0
    var current = priorResponse
    while (current != null) {
        count += 1
        current = current.priorResponse
    }
    return count
}

private fun MediaType?.isTextLike(): Boolean {
    val value = this?.toString()?.lowercase() ?: return false
    return value.startsWith("text/") ||
        value.contains("json") ||
        value.contains("xml") ||
        value.contains("x-www-form-urlencoded") ||
        value.contains("graphql") ||
        value.contains("event-stream")
}

private fun MediaType?.charsetOrUtf8(): Charset = this?.charset(Charsets.UTF_8) ?: Charsets.UTF_8

private fun Long.coerceToInt(): Int =
    when {
        this > Int.MAX_VALUE -> Int.MAX_VALUE
        this < Int.MIN_VALUE -> Int.MIN_VALUE
        else -> toInt()
    }

private fun elapsedSeconds(startTime: Long): Double = (System.currentTimeMillis() - startTime) / 1000.0

private fun StringBuilder.indexOfFirstNewline(): Int {
    val lf = indexOf("\n")
    val cr = indexOf("\r")
    return when {
        lf == -1 -> cr
        cr == -1 -> lf
        else -> minOf(lf, cr)
    }
}
