package com.appreveal.network

/**
 * Captured network request data. Matches iOS CapturedRequest exactly.
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
    val error: String? = null,
    val redirectCount: Int = 0,
) {
    companion object {
        private val sensitiveHeaders =
            setOf(
                "authorization",
                "cookie",
                "set-cookie",
                "x-api-key",
                "x-auth-token",
                "proxy-authorization",
            )

        fun redactSensitiveHeaders(headers: Map<String, String>): Map<String, String> =
            headers.mapValues { (key, value) ->
                if (sensitiveHeaders.contains(key.lowercase())) "[REDACTED]" else value
            }
    }

    /**
     * Returns a copy with sensitive request headers redacted.
     */
    fun withRedactedHeaders(): CapturedRequest = copy(requestHeaders = redactSensitiveHeaders(requestHeaders))
}
