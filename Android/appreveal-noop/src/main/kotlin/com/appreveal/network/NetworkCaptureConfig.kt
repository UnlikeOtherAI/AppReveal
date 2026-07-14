package com.appreveal.network

data class NetworkCaptureConfig(
    val maxBodyBytes: Long = 256L * 1024L,
    val maxSSEEvents: Int = 200,
    val redactedHeaders: Set<String> = defaultSensitiveHeaders,
    val captureBodies: Boolean = true,
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
    }
}
