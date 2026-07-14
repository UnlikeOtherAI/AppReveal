package com.appreveal.network

import com.appreveal.AppRevealOkHttp
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class OkHttpCaptureTest {
    private lateinit var server: MockWebServer

    @Before
    fun setUp() {
        NetworkObserverService.clear()
        server = MockWebServer()
        server.start()
    }

    @After
    fun tearDown() {
        server.shutdown()
        NetworkObserverService.clear()
    }

    @Test
    fun `okhttp interceptor captures request and response details`() {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setHeader("Set-Cookie", "session=secret")
                .setBody("""{"updated_at":"2026-07-14T21:36:14Z"}"""),
        )
        val client =
            OkHttpClient.Builder()
                .addInterceptor(AppRevealOkHttp.interceptor(NetworkCaptureConfig(maxBodyBytes = 1024)))
                .build()
        val request =
            Request.Builder()
                .url(server.url("/converse/session/abc"))
                .header("Authorization", "Bearer secret")
                .post("""{"resume":true}""".toRequestBody("application/json".toMediaType()))
                .build()

        client.newCall(request).execute().use { response ->
            assertEquals("""{"updated_at":"2026-07-14T21:36:14Z"}""", response.body!!.string())
        }

        val call = NetworkObserverService.recentCalls(limit = 10).single()
        assertEquals("POST", call.method)
        assertTrue(call.url.endsWith("/converse/session/abc"))
        assertEquals(200, call.statusCode)
        assertEquals("[REDACTED]", call.requestHeaders["Authorization"])
        assertEquals("[REDACTED]", call.responseHeaders?.get("Set-Cookie"))
        assertEquals("""{"resume":true}""", call.requestBody)
        assertEquals("""{"updated_at":"2026-07-14T21:36:14Z"}""", call.responseBody)
        assertNotNull(call.endTime)
        assertTrue((call.responseBodySize ?: 0) > 0)
    }

    @Test
    fun `okhttp interceptor captures server sent event frames`() {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "text/event-stream")
                .setBody("id: 1\nevent: token\ndata: hello\n\ndata: world\n\n"),
        )
        val client =
            OkHttpClient.Builder()
                .addInterceptor(AppRevealOkHttp.interceptor(NetworkCaptureConfig(maxBodyBytes = 1024)))
                .build()
        val request = Request.Builder().url(server.url("/converse/stream")).build()

        client.newCall(request).execute().use { response ->
            assertTrue(response.body!!.string().contains("hello"))
        }

        val call = NetworkObserverService.recentCalls(limit = 10).single()
        assertTrue(call.isStreaming)
        assertTrue(call.responseBody?.contains("data: hello") == true)
        assertEquals(2, call.sseEvents.size)
        assertEquals("token", call.sseEvents[0].event)
        assertEquals("hello", call.sseEvents[0].data)
        assertEquals("world", call.sseEvents[1].data)
    }
}
