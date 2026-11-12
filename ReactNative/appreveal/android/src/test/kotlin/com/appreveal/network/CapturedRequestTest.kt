package com.appreveal.network

import org.junit.Assert.*
import org.junit.Test

class CapturedRequestTest {
    @Test fun jsTimestampsSizesAndHeadersSurviveIngestion() {
        val call = CapturedRequest.fromJs(mapOf(
            "id" to "test", "url" to "https://example.test", "method" to "POST",
            "requestTimestamp" to 1000000.0, "responseTimestamp" to 1001250.0,
            "statusCode" to 201.0, "requestBodySize" to 42.0, "responseBodySize" to 9.0,
            "requestHeaders" to mapOf("Authorization" to "private", "Accept" to "application/json"),
            "responseHeaders" to mapOf("Set-Cookie" to "private", "Content-Type" to "application/json")
        ))
        NetworkObserverService.clear()
        NetworkObserverService.addCall(call)
        val saved = NetworkObserverService.callDetail("test")!!
        assertEquals(1000000L, saved.startTime)
        assertEquals(1001250L, saved.endTime)
        assertEquals(1.25, saved.duration!!, 0.001)
        assertEquals(42, saved.requestBodySize)
        assertEquals(9, saved.responseBodySize)
        assertEquals("[REDACTED]", saved.requestHeaders["Authorization"])
        assertEquals("application/json", saved.requestHeaders["Accept"])
        assertEquals("[REDACTED]", saved.responseHeaders!!["Set-Cookie"])
        assertTrue(NetworkObserverService.recentCalls(-1).isEmpty())
    }
}
