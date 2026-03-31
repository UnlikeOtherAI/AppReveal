package com.appreveal.mcpserver

import fi.iki.elonen.NanoHTTPD

/**
 * MCP HTTP server built on NanoHTTPD.
 * Accepts POST requests with JSON-RPC 2.0 payloads, routes through MCPRouter.
 */
internal class MCPServer(
    port: Int = 0,
) : NanoHTTPD(port) {
    /**
     * The actual port the server is listening on (valid after start()).
     */
    val actualPort: Int
        get() = super.getListeningPort()

    override fun serve(session: IHTTPSession): Response {
        if (session.method != Method.POST) {
            return newFixedLengthResponse(
                Response.Status.METHOD_NOT_ALLOWED,
                MIME_PLAINTEXT,
                "Only POST is supported",
            )
        }

        return try {
            val files = HashMap<String, String>()
            session.parseBody(files)
            val json = files["postData"] ?: ""

            if (json.isBlank()) {
                return newFixedLengthResponse(
                    Response.Status.BAD_REQUEST,
                    "application/json",
                    """{"error":"Empty body"}""",
                )
            }

            val request = MCPGson.gson.fromJson(json, MCPRequest::class.java)
            val response = MCPRouter.handle(request)
            val responseJson = MCPGson.gson.toJson(response)

            newFixedLengthResponse(
                Response.Status.OK,
                "application/json",
                responseJson,
            )
        } catch (e: Exception) {
            val errorResponse =
                MCPResponse.error(
                    null,
                    MCPError.internalError(e.message ?: "Server error"),
                )
            newFixedLengthResponse(
                Response.Status.INTERNAL_ERROR,
                "application/json",
                MCPGson.gson.toJson(errorResponse),
            )
        }
    }
}
