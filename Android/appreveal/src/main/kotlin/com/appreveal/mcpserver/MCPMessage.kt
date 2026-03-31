package com.appreveal.mcpserver

import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.google.gson.JsonArray
import com.google.gson.JsonDeserializationContext
import com.google.gson.JsonDeserializer
import com.google.gson.JsonElement
import com.google.gson.JsonNull
import com.google.gson.JsonObject
import com.google.gson.JsonPrimitive
import com.google.gson.JsonSerializationContext
import com.google.gson.JsonSerializer
import java.lang.reflect.Type

/**
 * JSON-RPC 2.0 request.
 */
internal data class MCPRequest(
    val jsonrpc: String,
    val id: Any?,
    val method: String,
    val params: JsonObject?,
)

/**
 * JSON-RPC 2.0 response.
 */
internal data class MCPResponse(
    val jsonrpc: String = "2.0",
    val id: Any?,
    val result: JsonElement? = null,
    val error: MCPError? = null,
) {
    companion object {
        fun success(
            id: Any?,
            result: JsonElement,
        ): MCPResponse = MCPResponse(id = id, result = result)

        fun error(
            id: Any?,
            error: MCPError,
        ): MCPResponse = MCPResponse(id = id, error = error)
    }
}

/**
 * JSON-RPC 2.0 error object.
 */
internal data class MCPError(
    val code: Int,
    val message: String,
    val data: JsonElement? = null,
) {
    companion object {
        fun methodNotFound(method: String): MCPError = MCPError(code = -32601, message = "Method not found: $method")

        fun invalidParams(detail: String): MCPError = MCPError(code = -32602, message = "Invalid params: $detail")

        fun internalError(detail: String): MCPError = MCPError(code = -32603, message = detail)
    }
}

/**
 * Gson instance configured for MCP JSON-RPC serialization.
 * Handles Any? id field (can be int, string, or null).
 */
internal object MCPGson {
    val gson: Gson =
        GsonBuilder()
            .registerTypeAdapter(MCPRequest::class.java, MCPRequestDeserializer())
            .registerTypeAdapter(MCPResponse::class.java, MCPResponseSerializer())
            .create()

    private class MCPRequestDeserializer : JsonDeserializer<MCPRequest> {
        override fun deserialize(
            json: JsonElement,
            typeOfT: Type,
            context: JsonDeserializationContext,
        ): MCPRequest {
            val obj = json.asJsonObject
            val jsonrpc = obj.get("jsonrpc")?.asString ?: "2.0"
            val method = obj.get("method")?.asString ?: ""
            val idElement = obj.get("id")
            val id: Any? =
                when {
                    idElement == null || idElement.isJsonNull -> null
                    idElement.asJsonPrimitive.isNumber -> idElement.asInt
                    else -> idElement.asString
                }
            val params = obj.getAsJsonObject("params")
            return MCPRequest(jsonrpc, id, method, params)
        }
    }

    private class MCPResponseSerializer : JsonSerializer<MCPResponse> {
        override fun serialize(
            src: MCPResponse,
            typeOfSrc: Type,
            context: JsonSerializationContext,
        ): JsonElement {
            val obj = JsonObject()
            obj.addProperty("jsonrpc", src.jsonrpc)
            when (val id = src.id) {
                null -> obj.add("id", JsonNull.INSTANCE)
                is Int -> obj.addProperty("id", id)
                is Long -> obj.addProperty("id", id)
                is String -> obj.addProperty("id", id)
                else -> obj.addProperty("id", id.toString())
            }
            if (src.result != null) {
                obj.add("result", src.result)
            }
            if (src.error != null) {
                val errorObj = JsonObject()
                errorObj.addProperty("code", src.error.code)
                errorObj.addProperty("message", src.error.message)
                if (src.error.data != null) {
                    errorObj.add("data", src.error.data)
                }
                obj.add("error", errorObj)
            }
            return obj
        }
    }
}
