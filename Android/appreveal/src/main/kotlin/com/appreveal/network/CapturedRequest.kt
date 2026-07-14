package com.appreveal.network

/**
 * Captured Server-Sent Event frame.
 */
data class CapturedSSEEvent(
    val id: String? = null,
    val event: String? = null,
    val data: String,
    val retry: Long? = null,
    val timestamp: Long = System.currentTimeMillis(),
)

/**
 * Network capture options for automatic client integrations.
 */
data class NetworkCaptureConfig(
    val maxBodyBytes: Long = 256L * 1024L,
    val maxSSEEvents: Int = 200,
    val redactedHeaders: Set<String> = CapturedRequest.defaultSensitiveHeaders,
    val captureBodies: Boolean = true,
)

/**
 * Captured network request data. Matches iOS CapturedRequest shape.
 */
data class CapturedRequest(
    val id: String =
        java.util.UUID
            .randomUUID()
            .toString(),
    val method: String,
    val url: String,
    val statusCode: Int? = null,
    val startTime: Long = System.currentTimeMillis(),
    val endTime: Long? = null,
    val duration: Double? = null,
    val requestHeaders: Map<String, String> = emptyMap(),
    val responseHeaders: Map<String, String>? = null,
    val requestBodySize: Int? = null,
    val responseBodySize: Int? = null,
    val requestBody: String? = null,
    val responseBody: String? = null,
    val requestBodyTruncated: Boolean = false,
    val responseBodyTruncated: Boolean = false,
    val sseEvents: List<CapturedSSEEvent> = emptyList(),
    val isStreaming: Boolean = false,
    val error: String? = null,
    val redirectCount: Int = 0,
) {
    companion object {
        val defaultSensitiveHeaders =
            setOf(
                "authorization",
                "cookie",
                "set-cookie",
                "x-api-key",
                "x-auth-token",
                "proxy-authorization",
            )

        fun redactSensitiveHeaders(
            headers: Map<String, String>,
            redactedHeaders: Set<String> = defaultSensitiveHeaders,
        ): Map<String, String> =
            headers.mapValues { (key, value) ->
                redactHeader(key, value, redactedHeaders)
            }

        fun redactHeader(
            key: String,
            value: String,
            redactedHeaders: Set<String> = defaultSensitiveHeaders,
        ): String = if (redactedHeaders.contains(key.lowercase())) "[REDACTED]" else value
    }

    /**
     * Returns a copy with sensitive headers redacted.
     */
    fun withRedactedHeaders(redactedHeaders: Set<String> = defaultSensitiveHeaders): CapturedRequest =
        copy(
            requestHeaders = redactSensitiveHeaders(requestHeaders, redactedHeaders),
            responseHeaders = responseHeaders?.let { redactSensitiveHeaders(it, redactedHeaders) },
        )
}
