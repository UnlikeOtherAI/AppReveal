package com.appreveal.mcpserver

import com.google.gson.JsonArray
import com.google.gson.JsonElement
import com.google.gson.JsonObject

/**
 * Tool definition for the MCP router.
 */
internal data class MCPToolDefinition(
    val name: String,
    val description: String,
    val inputSchema: JsonObject,
    val handler: (params: JsonObject?) -> JsonElement
)

/**
 * MCP tool registry and request dispatcher (singleton).
 */
internal object MCPRouter {

    private val tools = mutableMapOf<String, MCPToolDefinition>()

    fun register(tool: MCPToolDefinition) {
        tools[tool.name] = tool
    }

    fun tool(named: String): MCPToolDefinition? = tools[named]

    fun clearAll() {
        tools.clear()
    }

    fun handle(request: MCPRequest): MCPResponse {
        return when (request.method) {
            "initialize" -> {
                val result = JsonObject().apply {
                    addProperty("protocolVersion", "2025-06-18")
                    add("capabilities", JsonObject().apply {
                        add("tools", JsonObject())
                    })
                    add("serverInfo", JsonObject().apply {
                        addProperty("name", "AppReveal")
                        addProperty("version", "0.6.0")
                    })
                }
                MCPResponse.success(request.id, result)
            }

            "tools/list" -> {
                val toolList = JsonArray()
                for (tool in tools.values) {
                    val toolObj = JsonObject().apply {
                        addProperty("name", tool.name)
                        addProperty("description", tool.description)
                        add("inputSchema", tool.inputSchema)
                    }
                    toolList.add(toolObj)
                }
                val result = JsonObject().apply {
                    add("tools", toolList)
                }
                MCPResponse.success(request.id, result)
            }

            "tools/call" -> {
                val params = request.params
                val toolName = params?.get("name")?.asString
                if (toolName == null) {
                    return MCPResponse.error(request.id, MCPError.invalidParams("Missing tool name"))
                }

                val tool = tools[toolName]
                    ?: return MCPResponse.error(request.id, MCPError.methodNotFound(toolName))

                try {
                    val arguments = params.getAsJsonObject("arguments")
                    val handlerResult = tool.handler(arguments)
                    val resultJson = MCPGson.gson.toJson(handlerResult)

                    val content = JsonArray().apply {
                        add(JsonObject().apply {
                            addProperty("type", "text")
                            addProperty("text", resultJson)
                        })
                    }
                    val result = JsonObject().apply {
                        add("content", content)
                    }
                    MCPResponse.success(request.id, result)
                } catch (e: Exception) {
                    MCPResponse.error(request.id, MCPError.internalError(e.message ?: "Unknown error"))
                }
            }

            else -> MCPResponse.error(request.id, MCPError.methodNotFound(request.method))
        }
    }
}
