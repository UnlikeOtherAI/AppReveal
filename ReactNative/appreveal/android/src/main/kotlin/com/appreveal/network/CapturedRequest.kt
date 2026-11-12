package com.appreveal.network

/**
 * Captured network request data. Matches iOS CapturedRequest exactly.
 */
data class CapturedRequest(
    val id: String = java.util.UUID.randomUUID().toString(),
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
    val redirectCount: Int = 0
) {
    companion object {
        fun fromJs(call: Map<String, Any?>): CapturedRequest {
            val start = (call["requestTimestamp"] as? Number)?.toLong() ?: System.currentTimeMillis()
            val end = (call["responseTimestamp"] as? Number)?.toLong()
            fun headers(key: String): Map<String, String>? = (call[key] as? Map<*, *>)?.entries
                ?.mapNotNull { (key, value) -> if (key is String && value is String) key to value else null }?.toMap()
            return CapturedRequest(
                id = call["id"] as? String ?: java.util.UUID.randomUUID().toString(),
                method = call["method"] as? String ?: "GET",
                url = call["url"] as? String ?: "",
                statusCode = (call["statusCode"] as? Number)?.toInt(),
                startTime = start,
                endTime = end,
                duration = end?.let { (it - start).coerceAtLeast(0) / 1000.0 },
                requestHeaders = headers("requestHeaders") ?: emptyMap(),
                responseHeaders = headers("responseHeaders"),
                requestBodySize = (call["requestBodySize"] as? Number)?.toInt(),
                responseBodySize = (call["responseBodySize"] as? Number)?.toInt(),
                error = call["error"] as? String
            )
        }

        private val sensitiveHeaders = setOf(
            "authorization", "cookie", "set-cookie",
            "x-api-key", "x-auth-token", "proxy-authorization"
        )

        fun redactSensitiveHeaders(headers: Map<String, String>): Map<String, String> {
            return headers.mapValues { (key, value) ->
                if (sensitiveHeaders.contains(key.lowercase())) "[REDACTED]" else value
            }
        }
    }

    /**
     * Returns a copy with sensitive request headers redacted.
     */
    fun withRedactedHeaders(): CapturedRequest {
        return copy(requestHeaders = redactSensitiveHeaders(requestHeaders), responseHeaders = responseHeaders?.let(::redactSensitiveHeaders))
    }
}
