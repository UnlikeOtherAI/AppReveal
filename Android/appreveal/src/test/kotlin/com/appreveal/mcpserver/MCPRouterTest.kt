package com.appreveal.mcpserver

import com.appreveal.network.CapturedRequest
import com.appreveal.network.CapturedSSEEvent
import com.appreveal.network.NetworkObserverService
import com.google.gson.JsonArray
import com.google.gson.JsonObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class MCPRouterTest {
    @Before
    fun setUp() {
        MCPRouter.clearAll()
        NetworkObserverService.clear()
    }

    @After
    fun tearDown() {
        MCPRouter.clearAll()
        NetworkObserverService.clear()
    }

    @Test
    fun `screenshot returns image content and metadata for png and jpeg`() {
        listOf("png" to "image/png", "jpeg" to "image/jpeg").forEach { (format, mimeType) ->
            MCPRouter.clearAll()
            registerTool("screenshot") {
                JsonObject().apply {
                    addProperty("image", "base64-$format")
                    addProperty("width", 100)
                    addProperty("height", 200)
                    addProperty("scale", 2.0)
                    addProperty("format", format)
                }
            }

            val result = callTool("screenshot")
            val content = result.getAsJsonArray("content")
            val image = content[0].asJsonObject
            val metadata = result.getAsJsonObject("structuredContent")

            assertEquals("image", image.get("type").asString)
            assertEquals("base64-$format", image.get("data").asString)
            assertEquals(mimeType, image.get("mimeType").asString)
            assertFalse(metadata.has("image"))
            assertEquals(100, metadata.get("width").asInt)
            assertEquals(metadata, MCPGson.gson.fromJson(content[1].asJsonObject.get("text").asString, JsonObject::class.java))
        }
    }

    @Test
    fun `failed screenshot remains text and is marked as an error`() {
        registerTool("screenshot") {
            JsonObject().apply { addProperty("error", "capture failed") }
        }

        val result = callTool("screenshot")

        assertTrue(result.get("isError").asBoolean)
        assertEquals("text", result.getAsJsonArray("content")[0].asJsonObject.get("type").asString)
        assertFalse(result.has("structuredContent"))
    }

    @Test
    fun `ordinary tool result remains a single text block`() {
        registerTool("get_state") {
            JsonObject().apply { addProperty("count", 2) }
        }

        val result = callTool("get_state")

        assertEquals(1, result.getAsJsonArray("content").size())
        assertEquals("text", result.getAsJsonArray("content")[0].asJsonObject.get("type").asString)
        assertFalse(result.has("structuredContent"))
        assertFalse(result.has("isError"))
    }

    @Test
    fun `batch rejects screenshot with direct call instruction`() {
        registerBuiltInTools()
        val arguments =
            JsonObject().apply {
                add(
                    "actions",
                    JsonArray().apply {
                        add(JsonObject().apply { addProperty("tool", "screenshot") })
                    },
                )
            }

        val result = callTool("batch", arguments)
        val batchResult =
            MCPGson.gson.fromJson(
                result.getAsJsonArray("content")[0].asJsonObject.get("text").asString,
                JsonObject::class.java,
            )

        assertEquals(
            "screenshot must be called directly to return MCP image content",
            batchResult.getAsJsonArray("results")[0].asJsonObject.get("error").asString,
        )
    }

    @Test
    fun `network call detail exposes headers bodies and sse frames`() {
        registerBuiltInTools()
        NetworkObserverService.addCall(
            CapturedRequest(
                id = "call-1",
                method = "GET",
                url = "https://api.example.com/converse/stream",
                statusCode = 200,
                requestHeaders = mapOf("Authorization" to "Bearer secret"),
                responseHeaders = mapOf("Content-Type" to "text/event-stream", "Set-Cookie" to "session=secret"),
                responseBody = "data: hello\n\n",
                responseBodySize = 13,
                sseEvents = listOf(CapturedSSEEvent(event = "message", data = "hello")),
                isStreaming = true,
            ),
        )

        val summary = callTool("get_network_calls")
        val summaryText = summary.getAsJsonArray("content")[0].asJsonObject.get("text").asString
        val summaryJson = MCPGson.gson.fromJson(summaryText, JsonObject::class.java)
        val listedCall = summaryJson.getAsJsonArray("calls")[0].asJsonObject
        assertEquals("call-1", listedCall.get("id").asString)
        assertEquals(1, listedCall.get("sseEventCount").asInt)

        val detailArgs = JsonObject().apply { addProperty("id", "call-1") }
        val detail = callTool("get_network_call_detail", detailArgs)
        val detailText = detail.getAsJsonArray("content")[0].asJsonObject.get("text").asString
        val detailJson = MCPGson.gson.fromJson(detailText, JsonObject::class.java)

        assertEquals(
            "[REDACTED]",
            detailJson.getAsJsonObject("request").getAsJsonObject("headers").get("Authorization").asString,
        )
        assertEquals(
            "[REDACTED]",
            detailJson.getAsJsonObject("response").getAsJsonObject("headers").get("Set-Cookie").asString,
        )
        assertEquals("data: hello\n\n", detailJson.getAsJsonObject("response").get("body").asString)
        assertEquals("hello", detailJson.getAsJsonArray("sseEvents")[0].asJsonObject.get("data").asString)
    }

    private fun registerTool(
        name: String,
        handler: () -> JsonObject,
    ) {
        MCPRouter.register(
            MCPToolDefinition(
                name = name,
                description = name,
                inputSchema = JsonObject(),
                handler = { handler() },
            ),
        )
    }

    private fun callTool(
        name: String,
        arguments: JsonObject = JsonObject(),
    ): JsonObject {
        val params =
            JsonObject().apply {
                addProperty("name", name)
                add("arguments", arguments)
            }
        val response = MCPRouter.handle(MCPRequest("2.0", 1, "tools/call", params))
        return response.result!!.asJsonObject
    }
}
